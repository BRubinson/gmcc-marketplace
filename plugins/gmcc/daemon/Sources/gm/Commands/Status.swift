import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm status — daemon + db health over the socket (autostarts if dead).
struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report daemon and database health.")

    @OptionGroup var output: OutputOptions

    func run() throws {
        let response = try withClient { client in try client.status() }

        if output.json {
            printJSON(response)
        } else {
            print("[gm] daemon healthy")
            print("  pid:            \(response.daemonPid)")
            print("  protocol:       v\(response.protocolVersion)")
            print("  socket:         \(response.socketPath)")
            print("  started at:     \(response.startedAt) (up \(response.uptimeSeconds)s)")
            print("  database:       \(response.dbPath)")
            print("  schema version: \(response.schemaVersion)")
            print("  table counts:")
            for (table, count) in response.tableCounts.sorted(by: { $0.key < $1.key }) {
                print("    \(table): \(count)")
            }
        }
    }
}
