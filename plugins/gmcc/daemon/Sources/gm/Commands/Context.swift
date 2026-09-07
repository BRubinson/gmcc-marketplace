import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm context ensure|get|env — the identity resolver and env emitter.
/// `ensure` upserts the project → instance → session chain (with create-time
/// kbite seeding), provisions the ckfs artifact home, and reconciles the
/// session dope scope with the repo's on-disk tree; `get` is the read-only
/// resolution; `env` is the sole owner of the SessionStart env contract.
struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Resolve or lazily create the project → instance → session chain.",
        subcommands: [Ensure.self, Get.self, Env.self]
    )

    struct Ensure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Upsert the context chain from the current repo/branch; idempotent.")

        @OptionGroup var output: OutputOptions

        @Flag(name: .long, help: "Skip the dope files → db boot reconciliation.")
        var noDopeSync = false

        func run() throws {
            let git = try GitContext.detect()
            let request = try ContextBuilder.ensureRequest()
            let response = try withClient { client in
                try client.ensureContext(request)
            }

            // The ckfs artifact home (prompts/{seq}_{name}/memory/ scratch
            // space) is a client-side concern — the daemon writes no files.
            // This is the ONLY creator in the system (moved from
            // detect_repo.sh). try? deliberately: a read-only ckfs must not
            // fail ensure.
            let ckfsRoot = (try? withClient { try $0.pathsGet() }.ckfsRoot)
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? GmccEnvironment.fallbackCkfsRoot
            let promptsHome = ckfsRoot
                .appendingPathComponent(request.session.ckfsRelativeStoragePath, isDirectory: true)
                .appendingPathComponent("prompts", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: promptsHome, withIntermediateDirectories: true)

            // Dope boot sync: files → db, never fatal. A SessionStart that
            // fails on a domain model is worse than a session with a stale
            // one — every failure mode is a stderr notice.
            var dopeNotice: String?
            if !noDopeSync {
                let outcome = withClientOutcome { client in
                    DopeBootSync.run(client: client,
                                     sessionUuid: response.sessionUuid,
                                     instanceRoot: git.repoRoot)
                }
                dopeNotice = outcome.flatMap { DopeBootSync.notice(for: $0) }
                if let notice = dopeNotice {
                    FileHandle.standardError.write(Data((notice + "\n").utf8))
                }
            }

            if output.json {
                printJSON(response)
            } else {
                print("[gm] context ensured")
                print("  project uuid:  \(response.projectUuid)\(response.createdProject ? "  (created)" : "")")
                print("  instance uuid: \(response.instanceUuid)\(response.createdInstance ? "  (created)" : "")")
                print("  session uuid:  \(response.sessionUuid)\(response.createdSession ? "  (created)" : "")")
            }
        }

        /// Run a non-throwing body against a fresh client; nil when the
        /// daemon is unreachable (boot sync degrades, never blocks).
        private func withClientOutcome(
            _ body: (DaemonClient) -> DopeBootSync.Outcome
        ) -> DopeBootSync.Outcome? {
            try? withClient { client in body(client) }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read-only resolution of the current gmcc environment (never creates rows).")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let git = try GitContext.detect()
            let request = ContextGetRequest(
                projectCode: git.repoName,
                instanceName: git.instanceCode,
                sessionCode: git.sessionCode
            )
            let response = try withClient { client in
                try client.getContext(request)
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] context for \(git.repoName) @ \(git.branch)")
                print("  project uuid:  \(response.projectUuid ?? "—")")
                print("  instance uuid: \(response.instanceUuid ?? "—")")
                print("  session uuid:  \(response.sessionUuid ?? "—")")
                print("  kbites:        \(response.kbiteCodes.isEmpty ? "—" : response.kbiteCodes.joined(separator: ", "))")
            }
        }
    }

    /// The sole owner of the SessionStart env contract. stdout carries
    /// KEY=VALUE lines (append-safe to $CLAUDE_ENV_FILE), stderr carries
    /// consistency warnings, and the exit code is ALWAYS 0 — a SessionStart
    /// hook that fails hard is worse than a degraded session. Emission is
    /// daemon-free; the db is consulted best-effort for the ckfs root (so the
    /// env/db match invariant holds by construction) and the mismatch check.
    struct Env: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Emit the SessionStart env lines (stdout) + consistency warnings (stderr); always exits 0.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Plugin root to export as GMCC_PLUGIN_ROOT.")
        var pluginRoot: String

        @Flag(name: .long, help: "Skip the env-vs-db consistency check.")
        var noCheck = false

        func run() throws {
            let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
            let paths = try? withClient { try $0.pathsGet() }

            let lines = GmccEnvironment.emit(
                pluginRoot: pluginRoot,
                inheritedPath: inheritedPath,
                dbCkfsRoot: paths?.ckfsRoot)

            var warnings: [String] = []
            if let paths, !noCheck {
                warnings = GmccEnvironment.check(paths).map(\.message)
            } else if paths == nil {
                warnings.append(
                    "[GMB] daemon unavailable — env derived from defaults; run "
                    + "'gm daemon start' (or build_daemon.sh) then restart the session")
            }

            if output.json {
                struct EnvReport: Codable {
                    let lines: [String]
                    let warnings: [String]
                }
                printJSON(EnvReport(lines: lines, warnings: warnings))
            } else {
                for line in lines { print(line) }
                for warning in warnings {
                    FileHandle.standardError.write(Data((warning + "\n").utf8))
                }
            }
        }
    }
}
