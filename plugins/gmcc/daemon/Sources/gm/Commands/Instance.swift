import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm instance list|current-session — enumerate instances; resolve the
/// checked-out session from .git/HEAD.
struct Instance: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse instances.",
        subcommands: [List.self, CurrentSession.self]
    )

    struct CurrentSession: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "current-session",
            abstract: "The session matching the instance's checked-out branch (git-derived; detached ⇒ none).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var instanceUuid: String

        func run() throws {
            let response = try withClient {
                try $0.instanceCurrentSession(InstanceCurrentSessionRequest(instanceUuid: instanceUuid))
            }
            if output.json {
                printJSON(response)
            } else if let session = response.session {
                print("[gm] current session: \(session.code) \(session.uuid)")
            } else {
                print("[gm] no current session (head: \(response.headState), code: \(response.currentSessionCode ?? "-"))")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Instances, ordered by code; omit --project-uuid to list all.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Filter to one project (NOT_FOUND if the uuid is unknown).")
        var projectUuid: String?

        func run() throws {
            let response = try withClient { client in
                try client.listInstances(InstanceListRequest(projectUuid: projectUuid))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.instances.count) instance(s)")
                for i in response.instances {
                    print("  \(i.code) (\(i.name)) \(i.uuid)  project \(i.projectUuid.prefix(8))")
                }
            }
        }
    }
}
