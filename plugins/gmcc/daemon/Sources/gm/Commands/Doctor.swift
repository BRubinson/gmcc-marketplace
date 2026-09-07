import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm doctor — machine-readable host-wiring findings. The detection engine
/// behind the gmcc_cleanup_system skill: the skill renders findings and asks;
/// this verb detects. Exit 0 clean, exit 1 when findings exist. Scoped to
/// host wiring — it does not absorb gmcc_cleanup's ckfs/db hygiene walk.
struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Host-wiring findings: env-vs-db roots, PATH shim, retired zshrc block, daemon health, session dope drift.")

    @OptionGroup var output: OutputOptions

    struct Finding: Codable {
        let code: String
        let message: String
        let remedy: String
    }

    func run() throws {
        var findings: [Finding] = []
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser

        // 1. Daemon reachability + env-vs-db root agreement.
        let paths = try? withClient { try $0.pathsGet() }
        if let paths {
            for finding in GmccEnvironment.check(paths) {
                findings.append(Finding(
                    code: finding.code,
                    message: finding.message,
                    remedy: env["GMCC_ROOT"] != nil
                        ? "gm sandbox refresh"
                        : "gm config set --key ckfs_root --value <correct>"))
            }
        } else {
            findings.append(Finding(
                code: "daemon_unreachable",
                message: "the gmcc daemon did not answer on its socket",
                remedy: "gm daemon start (or bash plugins/gmcc/scripts/build_daemon.sh)"))
        }

        // 2. Retired ~/.zshrc gmcc env block.
        let zshrc = home.appendingPathComponent(".zshrc")
        if let text = try? String(contentsOf: zshrc, encoding: .utf8),
           text.contains(">>> gmcc env >>>") {
            findings.append(Finding(
                code: "zshrc_gmcc_block",
                message: "~/.zshrc still carries the retired '#### >>> gmcc env >>>' block — every var in it is dead",
                remedy: "delete the marker-bounded block (/gmcc_cleanup_system offers this)"))
        }

        // 3. Bare-gm resolution / shim health.
        let pathComponents = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let resolvable = pathComponents.contains {
            fm.isExecutableFile(atPath: "\($0)/gm")
        }
        if !resolvable {
            findings.append(Finding(
                code: "gm_not_on_path",
                message: "bare `gm` does not resolve on this PATH",
                remedy: "gm setup --install-path (then add the printed dir to your shell PATH if asked)"))
        }
        for dir in [home.appendingPathComponent(".local/bin"), home.appendingPathComponent("bin")] {
            let shim = dir.appendingPathComponent("gm")
            guard fm.fileExists(atPath: shim.path) else { continue }
            let content = (try? String(contentsOf: shim, encoding: .utf8)) ?? ""
            if content.contains("GMCC gm resolver"),
               content != GmccEnvironment.shimScript {
                findings.append(Finding(
                    code: "gm_shim_stale",
                    message: "\(shim.path) is a GMCC shim but does not match the current resolver rule",
                    remedy: "gm setup --install-path --path-dir \(dir.path)"))
            }
        }

        // 4. Sandbox snapshot completeness (only meaningful under GMCC_ROOT).
        if let root = env["GMCC_ROOT"], !root.isEmpty {
            let meta = URL(fileURLWithPath: root)
                .deletingLastPathComponent()
                .appendingPathComponent("snapshot_meta.json")
            if !fm.fileExists(atPath: meta.path) {
                findings.append(Finding(
                    code: "sandbox_metaless",
                    message: "sandbox runtime \(root) has no snapshot_meta.json — the snapshot is partial",
                    remedy: "re-run gm sandbox refresh from the prod environment"))
            }
        }

        // 5. Session dope drift (best-effort; needs git context + daemon).
        if let git = try? GitContext.detect(), paths != nil {
            let outcome = try? withClient { client -> DopeBootSync.Outcome in
                let sessionUuid = try ContextBuilder.resolveSessionUuid(client)
                // Detection only: read-repo + list, no ingest — reuse the
                // component's decision by running it with a probe that stops
                // before mutating? The component mutates on gaps, so doctor
                // re-derives the cheap comparison instead.
                let main = URL(fileURLWithPath: git.repoRoot)
                    .appendingPathComponent(".gmcc/dope/main.doped.json")
                guard FileManager.default.fileExists(atPath: main.path) else {
                    return .noRepoTree
                }
                let repo = try client.dopeReadRepo(DopeReadRepoRequest(dirPath: git.repoRoot))
                let scopes = try client.dopeList(DopeListRequest(sessionUuid: sessionUuid)).scopes
                guard let scope = scopes.first(where: { $0.code == repo.bundle.main.scope.code })
                else {
                    return .seeded(code: repo.bundle.main.scope.code,
                                   revision: repo.onDiskRevision,
                                   counts: DopeTreeCounts(domains: 0, entities: 0,
                                                          properties: 0, enums: 0, options: 0))
                }
                if repo.onDiskRevision > scope.revision {
                    return .readopted(code: scope.code, from: scope.revision,
                                      to: repo.onDiskRevision,
                                      counts: DopeTreeCounts(domains: 0, entities: 0,
                                                             properties: 0, enums: 0, options: 0))
                }
                if repo.onDiskRevision < scope.revision {
                    return .filesBehind(code: scope.code, dbRevision: scope.revision,
                                        diskVersion: repo.onDiskRevision)
                }
                return .inSync(code: scope.code, revision: scope.revision)
            }
            switch outcome {
            case .seeded(let code, let revision, _):
                findings.append(Finding(
                    code: "dope_scope_unseeded",
                    message: "repo dope tree '\(code)' (version \(revision)) has no scope in this session",
                    remedy: "gm dope sync"))
            case .readopted(let code, let from, let to, _):
                findings.append(Finding(
                    code: "dope_files_ahead",
                    message: "repo dope tree '\(code)' is at version \(to), session scope at revision \(from)",
                    remedy: "gm dope sync"))
            case .filesBehind(let code, let dbRevision, let diskVersion):
                findings.append(Finding(
                    code: "dope_db_ahead",
                    message: "session dope scope '\(code)' (revision \(dbRevision)) is ahead of the repo files (version \(diskVersion)) — unpublished edits",
                    remedy: "gm dope write-repo --scope-uuid <U>"))
            default:
                break
            }
        }

        if output.json {
            struct Report: Codable { let findings: [Finding] }
            printJSON(Report(findings: findings))
        } else if findings.isEmpty {
            print("[gm] doctor: no findings")
        } else {
            print("[gm] doctor: \(findings.count) finding(s)")
            for finding in findings {
                print("  [\(finding.code)] \(finding.message)")
                print("      remedy: \(finding.remedy)")
            }
        }
        if !findings.isEmpty {
            throw ExitCode(1)
        }
    }
}
