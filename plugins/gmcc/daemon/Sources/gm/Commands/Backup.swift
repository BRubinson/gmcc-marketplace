import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm backup — SQLite Online Backup into ~/gmcc/backups/.
struct Backup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Back up the db to a timestamped copy under ~/gmcc/backups/.")

    @OptionGroup var output: OutputOptions

    func run() throws {
        let response = try withClient { client in try client.backup() }
        if output.json {
            printJSON(response)
        } else {
            print("[gm] backup written")
            print("  path: \(response.backupPath)")
            print("  size: \(response.sizeBytes) bytes")
        }
    }
}
