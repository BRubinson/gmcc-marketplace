import Foundation
import GMCCDaemonKit

/// Outcome of one `--wait` poll session over `gm briefing get`.
enum BriefingWaitOutcome {
    case ready(BriefingGetResponse)
    /// Deadline hit; `lastSeen` is the most recent row observed (nil when
    /// every poll came back absent — i.e. `gm briefing open` never ran).
    case timedOut(lastSeen: AgentBriefingRow?)
}

/// The client-side loop behind `gm briefing get --wait`: re-issue the GET
/// until the briefing reads `ready`, sleeping between polls. `fetch` returns
/// nil for a RETRYABLE absence (SUMMARY_ABSENT under a selector form — the
/// doper-opens-it-itself window) and throws everything else immediately.
/// The deadline is WALL-CLOCK so fetch latency spends the budget too — the
/// timeout must fire before the caller's own harness timeout, however slow
/// the daemon answers. Injected sleeper/clock keep it testable without a
/// live daemon or real time.
func awaitBriefingReady(
    timeoutSeconds: Int,
    pollIntervalMicros: UInt32 = 1_000_000,
    sleeper: (UInt32) -> Void = { usleep($0) },
    now: () -> Date = { Date() },
    fetch: () throws -> BriefingGetResponse?
) rethrows -> BriefingWaitOutcome {
    let deadline = now().addingTimeInterval(TimeInterval(timeoutSeconds))
    var lastSeen: AgentBriefingRow?
    while true {
        if let response = try fetch() {
            if response.briefing.status == "ready" { return .ready(response) }
            lastSeen = response.briefing
        }
        if now() >= deadline { return .timedOut(lastSeen: lastSeen) }
        sleeper(pollIntervalMicros)
    }
}
