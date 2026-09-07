import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm sandbox — the local-dev sandbox under {ckfs_root}/development/local_sandbox.
///
/// `refresh` snapshots the LIVE marketplace world into the sandbox: db via the
/// daemon's Online Backup (the only prod touch, a read), repo via
/// `git clone --local` (committed state only), sub-ckfs via rsync of the
/// marketplace project subtree (kbites are never copied). The staged db copy
/// is retargeted OFFLINE (SandboxRetarget) before any sandbox daemon can
/// boot, then installed atomically; snapshot_meta.json is written LAST as the
/// commit record — its absence marks a partial snapshot, and re-running is
/// always the recovery path.
struct Sandbox: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Local-dev sandbox: snapshot the live marketplace world under {ckfs_root}/development/local_sandbox.",
        subcommands: [Refresh.self, SandboxStatus.self])

    // MARK: layout

    struct Layout {
        let root: URL          // {ckfs_root}/development/local_sandbox
        let runtime: URL       // sandbox GMCC_ROOT
        let runtimeBin: URL
        let repo: URL          // repo/gmcc-marketplace clone
        let ckfs: URL          // sandbox GMCC_CKFS_ROOT
        let staging: URL
        let meta: URL

        init(ckfsRoot: URL) {
            root = ckfsRoot
                .appendingPathComponent("development", isDirectory: true)
                .appendingPathComponent("local_sandbox", isDirectory: true)
            runtime = root.appendingPathComponent("runtime", isDirectory: true)
            runtimeBin = runtime.appendingPathComponent("bin", isDirectory: true)
            repo = root.appendingPathComponent("repo", isDirectory: true)
                .appendingPathComponent("gmcc-marketplace", isDirectory: true)
            ckfs = root.appendingPathComponent("ckfs", isDirectory: true)
            staging = root.appendingPathComponent(".staging", isDirectory: true)
            meta = root.appendingPathComponent("snapshot_meta.json", isDirectory: false)
        }
    }

    struct Meta: Codable {
        var generation: Int
        var sourceSha: String
        var backupPath: String
        var oldInstanceCode: String
        var newInstanceCode: String
        var createdAt: String
        /// "complete" or "refreshing". A refresh rewrites the previous
        /// generation's meta to "refreshing" BEFORE its first mutation, so a
        /// killed run can never leave a stale meta asserting completeness.
        /// nil (pre-field metas) reads as complete.
        var state: String?
    }

    // MARK: - refresh

    struct Refresh: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create or refresh the sandbox from the live daemon + this checkout (run from the gmcc-marketplace repo root).")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let env = ProcessInfo.processInfo.environment

            // Preflight 1 — never snapshot from inside a sandbox.
            if let root = env["GMCC_ROOT"], !root.isEmpty {
                throw ValidationError(
                    "refusing to run inside a sandbox environment (GMCC_ROOT is set) — run from a normal prod session.")
            }

            // Preflight 2 — must run from the marketplace checkout.
            let git = try GitContext.detect()
            guard git.repoName == "gmcc-marketplace" else {
                throw ValidationError(
                    "gm sandbox refresh must run from the gmcc-marketplace checkout (found \(git.repoName)).")
            }

            // Preflight 3 — the running prod daemon must be at least as new as
            // the installed binary (the development/ watcher prune must be
            // live BEFORE a sandbox starts churning under the watched tree).
            // Fails CLOSED: an unverifiable state is a refusal, not a pass.
            let status = try withClient { try $0.status() }
            guard let binMtime = try FileManager.default
                .attributesOfItem(atPath: Paths.binDaemon.path)[.modificationDate] as? Date,
                let startedAt = ISO8601DateFormatter().date(from: status.startedAt)
            else {
                throw ValidationError(
                    "cannot verify prod daemon freshness (binary mtime / startedAt unreadable) — refusing.")
            }
            if binMtime > startedAt {
                throw ValidationError(
                    "prod daemon predates the installed binary (started \(status.startedAt)) — restart it first: gm daemon restart")
            }

            // Canonical layout: sessions inside the snapshot hash git's
            // PHYSICAL path, so the sandbox tree is addressed by realpath.
            let layout = Layout(ckfsRoot: CkfsYaml.root.resolvingSymlinksInPath())
            let fm = FileManager.default

            // Preflight 4 — refuse when this checkout IS the sandbox clone
            // (bare shell inside the snapshot passes preflights 1-2).
            let canonicalRepoRoot = URL(fileURLWithPath: git.repoRoot)
                .resolvingSymlinksInPath().path
            if canonicalRepoRoot.hasPrefix(layout.root.path + "/") {
                throw ValidationError(
                    "refusing: this checkout is the sandbox clone itself — run from the real gmcc-marketplace checkout.")
            }
            for dir in [layout.root, layout.runtime, layout.runtimeBin,
                        layout.repo.deletingLastPathComponent(), layout.ckfs] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            // FIRST MUTATION: invalidate the previous generation's commit
            // record before touching anything, so a killed run can never be
            // mistaken for the complete generation it overwrote.
            let previous = (try? JSONDecoder().decode(Meta.self, from: Data(contentsOf: layout.meta)))
            if var invalidated = previous {
                invalidated.state = "refreshing"
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(invalidated).write(to: layout.meta, options: .atomic)
            }

            // Quiesce any sandbox daemon from a previous generation.
            quiesceSandboxDaemon(runtime: layout.runtime)

            // 1. DB — sanctioned Online Backup read of prod, staged locally.
            let backup = try withClient { try $0.backup() }
            try? fm.removeItem(at: layout.staging)
            try fm.createDirectory(at: layout.staging, withIntermediateDirectories: true)
            let stagedDb = layout.staging.appendingPathComponent("gmcc.db")
            try fm.copyItem(at: URL(fileURLWithPath: backup.backupPath), to: stagedDb)

            // 2. Offline retarget — BEFORE any sandbox daemon can exist.
            let kbites = layout.ckfs.appendingPathComponent("kbites", isDirectory: true)
            let result = try SandboxRetarget.run(
                dbPath: stagedDb.path,
                oldRepoPath: git.repoRoot,
                newRepoPath: layout.repo.path,
                ckfsRoot: layout.ckfs.path,
                kbiteRoot: kbites.path,
                kbiteOpenRoot: kbites.appendingPathComponent("open").path,
                kbiteDigestedRoot: kbites.appendingPathComponent("digested").path)

            // 3. Sub-ckfs — marketplace project subtree only; kbites NEVER copied.
            let liveProject = CkfsYaml.root
                .appendingPathComponent("projects/gmcc-marketplace", isDirectory: true)
            let sandboxProject = layout.ckfs
                .appendingPathComponent("projects/gmcc-marketplace", isDirectory: true)
            try fm.createDirectory(at: sandboxProject.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try runProcess("/usr/bin/rsync", ["-a", "--delete",
                                              liveProject.path + "/",
                                              sandboxProject.path + "/"])
            let instances = sandboxProject.appendingPathComponent("instances", isDirectory: true)
            let oldDir = instances.appendingPathComponent(result.oldInstanceCode, isDirectory: true)
            let newDir = instances.appendingPathComponent(result.newInstanceCode, isDirectory: true)
            if fm.fileExists(atPath: oldDir.path) {
                try? fm.removeItem(at: newDir)
                try fm.moveItem(at: oldDir, to: newDir)
            }
            for sub in ["open", "digested"] {
                try fm.createDirectory(at: kbites.appendingPathComponent(sub),
                                       withIntermediateDirectories: true)
            }

            // 4. Repo — committed state only. A corrupt half-clone (killed
            //    earlier run) must not wedge every re-run: on any refresh
            //    failure, fall back to a fresh clone.
            func cloneFresh() throws {
                try? fm.removeItem(at: layout.repo)
                try runProcess("/usr/bin/git", ["clone", "--local", "--branch", git.branch,
                                                git.repoRoot, layout.repo.path])
            }
            if fm.fileExists(atPath: layout.repo.appendingPathComponent(".git").path) {
                do {
                    try runProcess("/usr/bin/git", ["-C", layout.repo.path, "fetch", "origin", git.branch])
                    try runProcess("/usr/bin/git", ["-C", layout.repo.path, "reset", "--hard", "FETCH_HEAD"])
                } catch {
                    try cloneFresh()
                }
            } else {
                try cloneFresh()
            }
            let marker = layout.repo.appendingPathComponent(".gmcc_sandbox")
            try """
            # Written by gm sandbox refresh — sourced by detect_repo.sh so any
            # Claude session inside this snapshot auto-sandboxes.
            export GMCC_ROOT="\(layout.runtime.path)"
            export GMCC_CKFS_ROOT="\(layout.ckfs.path)"
            """.write(to: marker, atomically: true, encoding: .utf8)
            let exclude = layout.repo.appendingPathComponent(".git/info/exclude")
            let existing = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
            if !existing.contains(".gmcc_sandbox") {
                try (existing + "\n.gmcc_sandbox\n").write(to: exclude, atomically: true, encoding: .utf8)
            }

            // 5. Binaries + launchers — prod artifacts, same generation as the db.
            for bin in ["gm", "gmcc_daemon"] {
                let src = Paths.bin.appendingPathComponent(bin)
                let dst = layout.runtimeBin.appendingPathComponent(bin)
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: src, to: dst)
            }
            try writeLauncher(
                at: layout.root.appendingPathComponent("launch_gm.sh"),
                layout: layout,
                exec: "exec \"\(layout.runtimeBin.appendingPathComponent("gm").path)\" \"$@\"")
            try writeLauncher(
                at: layout.root.appendingPathComponent("launch_gmvibes.sh"),
                layout: layout,
                exec: """
                APP="${1:-${GMVIBES_APP:-}}"
                if [ -z "$APP" ] || [ ! -d "$APP" ]; then
                    echo "GMVibes.app not found${APP:+ at $APP}." >&2
                    echo "Pass the app path (launch_gmvibes.sh /path/to/GMVibes.app) or export GMVIBES_APP." >&2
                    echo "Build one: cd \(layout.repo.path)/gmvibes && xcodebuild -project GMVibes.xcodeproj -scheme GMVibes -configuration Debug build" >&2
                    exit 1
                fi
                exec "$APP/Contents/MacOS/GMVibes"
                """)

            // 6. Atomic db install. RE-quiesce first: a launcher user or a
            //    session inside the snapshot can autostart a daemon onto the
            //    old db during the long middle of this pipeline.
            quiesceSandboxDaemon(runtime: layout.runtime)
            let liveDb = layout.runtime.appendingPathComponent("gmcc.db")
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(at: URL(fileURLWithPath: liveDb.path + suffix))
            }
            try fm.moveItem(at: stagedDb, to: liveDb)
            try? fm.removeItem(at: layout.staging)

            // 7. Commit record — LAST. Absence or state != complete == partial.
            let sha = (try? capture("/usr/bin/git", ["-C", git.repoRoot, "rev-parse", "HEAD"])) ?? ""
            let meta = Meta(
                generation: (previous?.generation ?? 0) + 1,
                sourceSha: sha.trimmingCharacters(in: .whitespacesAndNewlines),
                backupPath: backup.backupPath,
                oldInstanceCode: result.oldInstanceCode,
                newInstanceCode: result.newInstanceCode,
                createdAt: Store.isoNow(),
                state: "complete")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meta).write(to: layout.meta, options: .atomic)

            if output.json {
                printJSON([
                    "sandbox_root": layout.root.path,
                    "generation": String(meta.generation),
                    "instance_code": result.newInstanceCode,
                    "launch_gm": layout.root.appendingPathComponent("launch_gm.sh").path,
                    "launch_gmvibes": layout.root.appendingPathComponent("launch_gmvibes.sh").path,
                ])
            } else {
                print("[gm] sandbox generation \(meta.generation) ready at \(layout.root.path)")
                print("  instance:  \(result.oldInstanceCode) -> \(result.newInstanceCode)")
                print("  gm:        \(layout.root.path)/launch_gm.sh <args>")
                print("  GMVibes:   \(layout.root.path)/launch_gmvibes.sh [app-path]")
                print("  never run 'gm setup --launchd' in the sandbox — launchd is prod-only.")
            }
        }
    }

    // MARK: - status

    struct SandboxStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Report sandbox generation, daemon liveness, and completeness.")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let layout = Layout(ckfsRoot: CkfsYaml.root.resolvingSymlinksInPath())
            guard let data = try? Data(contentsOf: layout.meta),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data) else {
                print("[gm] no complete sandbox at \(layout.root.path) — snapshot_meta.json missing (partial or never created). Run: gm sandbox refresh")
                throw ExitCode(1)
            }
            if let state = meta.state, state != "complete" {
                print("[gm] sandbox at \(layout.root.path) is PARTIAL — a refresh started after generation \(meta.generation) and did not finish. Run: gm sandbox refresh")
                throw ExitCode(1)
            }
            let pid = sandboxDaemonPid(runtime: layout.runtime)
            if output.json {
                printJSON([
                    "sandbox_root": layout.root.path,
                    "generation": String(meta.generation),
                    "instance_code": meta.newInstanceCode,
                    "source_sha": meta.sourceSha,
                    "created_at": meta.createdAt,
                    "daemon_pid": pid.map(String.init) ?? "",
                ])
            } else {
                print("[gm] sandbox generation \(meta.generation) (created \(meta.createdAt))")
                print("  instance: \(meta.newInstanceCode)  source: \(meta.sourceSha.prefix(8))")
                print("  daemon:   \(pid.map { "running (pid \($0))" } ?? "not running")")
            }
        }
    }

    // MARK: - helpers

    /// The daemon holds an exclusive flock on its pidfile for its lifetime,
    /// so a shared non-blocking probe is the truthful liveness check — the
    /// pid TEXT alone is unsafe (stale file + pid reuse would finger an
    /// innocent same-user process).
    static func sandboxDaemonPid(runtime: URL) -> Int32? {
        let pidfile = runtime.appendingPathComponent("daemon.pid")
        let fd = open(pidfile.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return nil   // lock acquired -> no live daemon holds the file
        }
        guard let text = try? String(contentsOf: pidfile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return pid
    }

    static func quiesceSandboxDaemon(runtime: URL) {
        guard let pid = sandboxDaemonPid(runtime: runtime) else { return }
        kill(pid, SIGTERM)
        for _ in 0..<50 where kill(pid, 0) == 0 {
            usleep(100_000)
        }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: runtime.appendingPathComponent("daemon.sock"))
    }

    static func writeLauncher(at url: URL, layout: Layout, exec: String) throws {
        let script = """
        #!/bin/sh
        # Written by gm sandbox refresh. Finder-launched apps inherit no shell
        # env, so the sandbox is entered by exec-ing binaries with env set.
        export GMCC_ROOT="\(layout.runtime.path)"
        export GMCC_CKFS_ROOT="\(layout.ckfs.path)"
        \(exec)
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @discardableResult
    static func capture(_ launchPath: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tail = stderrText.split(separator: "\n").suffix(5).joined(separator: "\n")
            throw ValidationError(
                "\(launchPath) \(args.joined(separator: " ")) failed (exit \(process.terminationStatus))"
                + (tail.isEmpty ? "" : "\n\(tail)"))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func runProcess(_ launchPath: String, _ args: [String]) throws {
        _ = try capture(launchPath, args)
    }
}

