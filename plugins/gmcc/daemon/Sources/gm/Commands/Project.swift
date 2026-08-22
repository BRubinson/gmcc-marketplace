import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm project list — enumerate every project in the db (the Landing browse
/// entry point).
struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse projects.",
        subcommands: [List.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "All projects, ordered by code.")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let response = try withClient { client in
                try client.listProjects()
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.projects.count) project(s)")
                for p in response.projects {
                    print("  \(p.code) (\(p.name)) \(p.uuid)")
                }
            }
        }
    }
}
