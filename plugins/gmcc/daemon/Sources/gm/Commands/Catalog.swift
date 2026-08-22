import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm catalog search — tokenized OR name/code search across instances +
/// sessions, optionally scoped to one project.
struct Catalog: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search the instance/session catalog.",
        subcommands: [Search.self]
    )

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Match sessions and instances by name/code; an instance match returns all its sessions.")

        @OptionGroup var output: OutputOptions

        @Argument(help: "Whitespace-separated tokens; a row matches if any token is a substring of its name or code.")
        var query: String

        @Option(name: .long, help: "Scope to one project (NOT_FOUND if the uuid is unknown).")
        var projectUuid: String?

        @Option(name: .long, help: "Cap on returned sessions (default 200).")
        var limit: Int?

        func run() throws {
            let response = try withClient { client in
                try client.searchCatalog(
                    CatalogSearchRequest(query: query, projectUuid: projectUuid, limit: limit))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.instances.count) instance(s), \(response.sessions.count) session(s)")
                for i in response.instances {
                    print("  instance \(i.code) (\(i.name)) \(i.uuid)")
                    for s in response.sessions where s.instanceUuid == i.uuid {
                        print("    session \(s.code) (\(s.name)) [\(s.status)] \(s.uuid)")
                    }
                }
            }
        }
    }
}
