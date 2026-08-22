import Foundation
import CoreServices

/// Item 8 — filesystem events for prompt memory/ directories, the daemon's
/// first off-serial-queue lane.
///
/// Shape: ONE FSEventStream rooted at the ckfs root (auto-covers new prompt
/// folders with no registration hook and costs one fd), scheduled on the
/// lane's own serial queue via FSEventStreamSetDispatchQueue (the daemon runs
/// dispatchMain with no run loop). Events are filtered to paths containing
/// /prompts/ … /memory, deduped per flush window, and handed to `deliver` as
/// the prompt's ckfs_relative_storage_path.
///
/// HARD RULES (the lane contract):
///   1. This type holds NO Store and NO Server reference — it structurally
///      cannot write to the db or touch connection state. `deliver` hops onto
///      the server queue and does everything there.
///   2. The stream's 1.0s latency is the debounce — an editor save storm
///      becomes one callback per window.
///   3. Events are EPHEMERAL: no daemon_event row, broadcast-only with id 0
///      (never a replay cursor). A filesystem hint needs no durability.
///
/// Honest limitation: only prompts with a non-empty ckfs_relative_storage_path
/// resolve (post-m0002 prompts; no backfill by decision) — legacy prompts keep
/// the client-side poll.
final class MemoryWatcher {
    private let lane = DispatchQueue(label: "gmcc.daemon.lane", qos: .utility)
    private let ckfsRoot: String
    private let deliver: @Sendable (_ promptStoragePath: String) -> Void
    private var stream: FSEventStreamRef?

    init(ckfsRoot: String, deliver: @escaping @Sendable (String) -> Void) {
        self.ckfsRoot = ckfsRoot
        self.deliver = deliver
    }

    func start() {
        lane.async { self.startOnLane() }
    }

    func stop() {
        lane.async {
            guard let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func startOnLane() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<MemoryWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = Unmanaged<CFArray>.fromOpaque(
                UnsafeRawPointer(eventPaths)).takeUnretainedValue() as? [String] else { return }
            watcher.handle(paths: Array(paths.prefix(count)))
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [ckfsRoot] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency: the debounce window
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            FileHandle.standardError.write(
                Data("[gmcc_daemon] MemoryWatcher: FSEventStreamCreate failed for \(ckfsRoot)\n".utf8))
            return
        }
        FSEventStreamSetDispatchQueue(stream, lane)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    /// Runs on the lane. Reduces raw event paths to the set of distinct
    /// prompt storage paths whose memory/ subtree changed, then delivers each.
    private func handle(paths: [String]) {
        var promptPaths: Set<String> = []
        let rootPrefix = ckfsRoot.hasSuffix("/") ? ckfsRoot : ckfsRoot + "/"
        for path in paths {
            guard path.hasPrefix(rootPrefix) else { continue }
            let relative = String(path.dropFirst(rootPrefix.count))
            // Expect …/prompts/{seq}_{name}/memory[/…] — anchor on the memory
            // segment and keep everything before it as the prompt folder.
            guard let memoryRange = relative.range(of: "/memory") else { continue }
            let promptFolder = String(relative[..<memoryRange.lowerBound])
            guard promptFolder.contains("/prompts/") else { continue }
            // The path must END at the prompt folder boundary: reject
            // lookalikes such as …/memory_bak by requiring the next char (if
            // any) to be a slash.
            let after = relative[memoryRange.upperBound...]
            guard after.isEmpty || after.hasPrefix("/") else { continue }
            promptPaths.insert(promptFolder)
        }
        for promptPath in promptPaths.sorted() {
            deliver(promptPath)
        }
    }
}
