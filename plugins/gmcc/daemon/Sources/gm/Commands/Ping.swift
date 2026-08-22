import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm ping — liveness + build identity (sha/date stamped by build_daemon.sh).
struct Ping: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ping the daemon and report its build version.")

    @OptionGroup var output: OutputOptions

    func run() throws {
        let response = try withClient { client in try client.ping() }
        if output.json {
            printJSON(response)
        } else {
            print("[gm] pong from pid \(response.daemonPid)")
            print("  protocol: v\(response.protocolVersion)")
            print("  build:    \(response.buildSha) (\(response.buildDate))")
            print("  uptime:   \(response.uptimeSeconds)s (started \(response.startedAt))")
        }
    }
}
