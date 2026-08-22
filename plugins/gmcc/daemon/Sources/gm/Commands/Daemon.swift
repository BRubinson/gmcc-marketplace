import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm daemon start|stop|restart|status — daemon lifecycle control.
struct Daemon: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control the gmcc_daemon process.",
        subcommands: [Start.self, Stop.self, Restart.self, DaemonStatus.self]
    )

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start the daemon (no-op if already running).")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let ack = try withClient { client in try client.connect() }
            if output.json {
                printJSON(ack)
            } else {
                print("[gm] daemon running: pid \(ack.daemonPid), protocol v\(ack.protocolVersion)")
            }
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop the running daemon (SHUTDOWN: drain, WAL checkpoint, pidfile removal).")

        @OptionGroup var output: OutputOptions

        func run() throws {
            // No autostart: booting a daemon just to stop it is pointless.
            let client = DaemonClient(autostart: false)
            defer { client.close() }
            do {
                let response = try client.shutdown()
                if output.json {
                    printJSON(response)
                } else {
                    print("[gm] \(response.message)")
                }
            } catch DaemonClientError.unreachable {
                // Only "socket dead" means not running; every other failure
                // (wire, server, mismatch) exits via the documented codes.
                print("[gm] daemon not running")
            } catch let error as DaemonClientError {
                throw gmExitCode(for: error)
            }
        }
    }

    struct Restart: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop the daemon (if running), then start it fresh.")

        @OptionGroup var output: OutputOptions

        func run() throws {
            var stop = Stop()
            stop.output = output
            try stop.run()
            // The stale socket inode lingers until the new daemon unlinks it;
            // give the old process a beat to fully exit.
            usleep(200_000)
            var start = Start()
            start.output = output
            try start.run()
        }
    }

    struct DaemonStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Report whether the daemon is running (never autostarts it).")

        @OptionGroup var output: OutputOptions

        func run() throws {
            // The one command whose job is observation must be able to answer
            // "not running" — no autostart.
            let client = DaemonClient(autostart: false)
            defer { client.close() }
            do {
                let response = try client.ping()
                if output.json {
                    printJSON(response)
                } else {
                    print("[gm] pong from pid \(response.daemonPid) — build \(response.buildSha), up \(response.uptimeSeconds)s")
                }
            } catch DaemonClientError.unreachable {
                print("[gm] daemon not running")
            } catch let error as DaemonClientError {
                throw gmExitCode(for: error)
            }
        }
    }
}
