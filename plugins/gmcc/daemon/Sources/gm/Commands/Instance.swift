import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm instance list — enumerate instances, optionally scoped to one project.
struct Instance: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse instances.",
        subcommands: [List.self]
    )

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
