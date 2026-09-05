import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm context ensure|get — the identity resolver. `ensure` upserts the
/// project → instance → session chain (with create-time kbite seeding) and
/// returns the uuid triple; `get` is the read-only resolution.
struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Resolve or lazily create the project → instance → session chain.",
        subcommands: [Ensure.self, Get.self]
    )

    struct Ensure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Upsert the context chain from the current repo/branch; idempotent.")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let request = try ContextBuilder.ensureRequest()
            let response = try withClient { client in
                try client.ensureContext(request)
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
}
