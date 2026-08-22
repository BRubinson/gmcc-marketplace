import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm paths — the daemon's typed root paths (item 6). Runtime paths from the
/// daemon's Paths conventions; ckfs/kbite roots from the db-backed
/// daemon_config (seeded defaults; see `gm config set`). Retires client-side
/// shell-profile scraping.
struct PathsCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paths",
        abstract: "Print the daemon's runtime, ckfs, and kbite root paths.")

    @OptionGroup var output: OutputOptions

    func run() throws {
        let response = try withClient { try $0.pathsGet() }
        if output.json { printJSON(response) } else {
            print("[gm] daemon paths")
            print("  gmcc root:      \(response.gmccRoot)")
            print("  database:       \(response.dbPath)")
            print("  socket:         \(response.socketPath)")
            print("  backups:        \(response.backupsRoot)")
            print("  ckfs root:      \(response.ckfsRoot)")
            print("  kbite root:     \(response.kbiteRoot)")
            print("  kbite open:     \(response.kbiteOpenRoot)")
            print("  kbite digested: \(response.kbiteDigestedRoot)")
        }
    }
}

/// gm config — daemon_config writes. The key space is enum-bound; an unknown
/// key is BAD_REQUEST.
struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Daemon configuration (db-backed; the daemon never reads $GMCC_* env vars).",
        subcommands: [Set.self]
    )

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set one config key (ckfs_root, kbite_root, kbite_open_root, kbite_digested_root).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var key: ConfigKey
        @Option(name: .long) var value: String

        func run() throws {
            let response = try withClient { try $0.configSet(ConfigSetRequest(key: key, value: value)) }
            if output.json { printJSON(response) } else {
                print("[gm] config \(response.key.rawValue) = \(response.value)")
            }
        }
    }
}
