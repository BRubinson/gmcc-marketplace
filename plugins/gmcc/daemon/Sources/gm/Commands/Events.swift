import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm events — query the daemon_event audit log, or --follow the live stream
/// (SUBSCRIBE with optional --since-id replay).
struct Events: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Query the daemon event log, or follow it live.")

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Filter by event kind (e.g. FILE_CHANGE).")
    var kind: String?

    @Option(name: .long, help: "Filter by subject uuid.")
    var subjectUuid: String?

    @Option(name: .long, help: "Only events with id greater than this (replay cursor).")
    var sinceId: Int64?

    @Option(name: .long, help: "ISO-8601 lower bound (inclusive).")
    var sinceTime: String?

    @Option(name: .long, help: "ISO-8601 upper bound (inclusive).")
    var untilTime: String?

    @Option(name: .long, help: "Max rows (default 200).")
    var limit: Int?

    @Flag(name: .long, help: "Stay subscribed and print events as they happen.")
    var follow = false

    func run() throws {
        if follow {
            try followStream()
            return
        }
        let response = try withClient { client in
            try client.listEvents(EventListRequest(
                kind: kind,
                subjectUuid: subjectUuid,
                sinceId: sinceId,
                sinceTime: sinceTime,
                untilTime: untilTime,
                limit: limit
            ))
        }
        if output.json {
            printJSON(response)
        } else {
            print("[gm] \(response.events.count) event(s)")
            for event in response.events {
                printEvent(event)
            }
        }
    }

    private func followStream() throws {
        let subscription = DaemonEventSubscription(sinceId: sinceId, clientName: "gm-events-follow")
        let json = output.json
        let semaphore = DispatchSemaphore(value: 0)
        // Exit-code contract: a DAEMON_STOP immediately before the drop is a
        // clean daemon shutdown (exit 0); anything else maps through the same
        // ladder as request commands.
        final class StreamOutcome: @unchecked Sendable {
            var sawDaemonStopLast = false
            var terminalError: Error?
        }
        let outcome = StreamOutcome()
        let task = Task {
            do {
                for try await event in subscription.events() {
                    outcome.sawDaemonStopLast = event.kind == DaemonEventKind.daemonStop.rawValue
                    if json {
                        // Single-line per event: the stream stays pipeable NDJSON.
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.sortedKeys]
                        if let data = try? encoder.encode(event), let text = String(data: data, encoding: .utf8) {
                            print(text)
                        }
                    } else {
                        Self.printEventLine(event)
                    }
                    // Streaming output must not sit in the block buffer when
                    // stdout is a pipe/file.
                    fflush(stdout)
                }
            } catch {
                outcome.terminalError = error
            }
            semaphore.signal()
        }
        _ = task
        semaphore.wait()
        if let error = outcome.terminalError, !outcome.sawDaemonStopLast {
            if let clientError = error as? DaemonClientError {
                throw gmExitCode(for: clientError)
            }
            FileHandle.standardError.write(Data("[gm] stream ended: \(error)\n".utf8))
            throw ExitCode(1)
        }
    }

    private func printEvent(_ event: EventNotification) {
        Self.printEventLine(event)
    }

    private static func printEventLine(_ event: EventNotification) {
        let subject = event.subjectUuid.map { " \($0.prefix(8))" } ?? ""
        let payload = event.payload.map { " \($0)" } ?? ""
        print("  #\(event.id) \(event.createdAt) \(event.kind)\(subject)\(payload)")
    }
}
