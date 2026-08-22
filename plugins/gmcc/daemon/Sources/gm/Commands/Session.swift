import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm session list|get|update — session enumeration, context, and guarded
/// scalar updates.
struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse, read, and update sessions.",
        subcommands: [List.self, Get.self, Update.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sessions, ordered by code; omit --instance-uuid to list all.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Filter to one instance (NOT_FOUND if the uuid is unknown).")
        var instanceUuid: String?

        func run() throws {
            let response = try withClient { client in
                try client.listSessions(SessionListRequest(instanceUuid: instanceUuid))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.sessions.count) session(s)")
                for s in response.sessions {
                    print("  \(s.code) [\(s.status)] \(s.uuid)  instance \(s.instanceUuid.prefix(8))")
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Session row + prompt stubs + change summaries.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session).")
        var sessionUuid: String?

        func run() throws {
            let response = try withClient { client in
                let uuid = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return try client.getSession(SessionGetRequest(sessionUuid: uuid))
            }
            if output.json {
                printJSON(response)
            } else {
                let s = response.session
                print("[gm] session \(s.code) (\(s.status), v\(s.version))")
                print("  uuid: \(s.uuid)")
                print("  prompts:")
                for stub in response.prompts {
                    print("    \(stub.seq). \(stub.name) [\(stub.status)] \(stub.uuid.prefix(8))")
                }
                let c = response.changeSummary
                print("  changes: \(c.changeCount) across \(c.distinctFiles) file(s), \(c.totalLineSpan) line(s)")
                for pc in response.promptChanges {
                    let label = pc.promptUuid.map { String($0.prefix(8)) } ?? "(unattributed)"
                    print("    \(label): \(pc.summary.changeCount) change(s), \(pc.summary.distinctFiles) file(s)")
                }
            }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Guarded update of session scalars (VERSION_CONFLICT on a stale --expected-version).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session).")
        var sessionUuid: String?

        @Option(name: .long, help: "The session version this update was based on.")
        var expectedVersion: Int64

        @Option(name: .long) var name: String?
        @Option(name: .long) var backstory: String?
        @Option(name: .long) var goal: String?
        @Option(name: .long, help: "active or closed") var status: SessionStatus?

        func run() throws {
            let response = try withClient { client in
                let uuid = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return try client.updateSession(SessionUpdateRequest(
                    sessionUuid: uuid,
                    expectedVersion: expectedVersion,
                    name: name,
                    backstory: backstory,
                    goal: goal,
                    status: status
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] session updated: \(response.code) (\(response.status), v\(response.version))")
            }
        }
    }
}
