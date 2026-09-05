import ArgumentParser
import Foundation
import GMCCDaemonKit

/// Parse one repeatable `--rating <finding-uuid>:<0-999>` pair. Split on the
/// LAST colon so a uuid containing colons (never the case today, but cheap to
/// be right about) still parses; fail fast on malformed input.
func parseRatingPair(_ raw: String) throws -> FindingRating {
    guard let idx = raw.lastIndex(of: ":") else {
        throw ValidationError("--rating expects <finding-uuid>:<0-999>, got '\(raw)'")
    }
    let uuid = String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
    let ratingText = String(raw[raw.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    guard !uuid.isEmpty, let rating = Int(ratingText), (0...999).contains(rating) else {
        throw ValidationError("--rating expects <finding-uuid>:<0-999>, got '\(raw)'")
    }
    return FindingRating(findingUuid: uuid, rating: rating)
}

/// Resolve the complete verbs' overview source: exactly one of --overview /
/// --overview-file. The file path exists because a long overview can exceed
/// the OS argv budget (~1 MB) long before the daemon's 2 MB cap.
func resolveOverview(inline: String?, file: String?) throws -> String {
    switch (inline, file) {
    case (let inline?, nil):
        return inline
    case (nil, let file?):
        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
            throw ValidationError("cannot read --overview-file: \(file)")
        }
        return content
    case (nil, nil):
        throw ValidationError("pass --overview or --overview-file")
    default:
        throw ValidationError("--overview and --overview-file are mutually exclusive")
    }
}

/// Print a bounded preview, appending the ellipsis only when actually
/// truncated.
func previewLine(_ label: String, _ text: String) {
    let limit = 200
    let clipped = text.prefix(limit)
    print("  \(label): \(clipped)\(text.count > limit ? "…" : "")")
}

/// Shared GET window flags: --full | --max-rating N | --rating-range A:B,
/// mutually exclusive (checked client-side for a clean message). The default
/// window is ratings under 100; unranked findings are ALWAYS full rows.
struct RatingWindowOptions: ParsableArguments {
    @Flag(name: .long, help: "Return every finding as a full row (no stub partition).")
    var full = false
    @Option(name: .long, help: "Widen (or narrow) the full-row window to ratings 0...N.")
    var maxRating: Int?
    @Option(name: .long, help: "Full-row window as A:B (inclusive rating bounds).")
    var ratingRange: String?

    func resolve() throws -> (full: Bool, min: Int?, max: Int?) {
        let picked = [full, maxRating != nil, ratingRange != nil].filter { $0 }.count
        guard picked <= 1 else {
            throw ValidationError("--full, --max-rating, and --rating-range are mutually exclusive")
        }
        if let ratingRange {
            let parts = ratingRange.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]),
                  (0...999).contains(low), (0...999).contains(high), low <= high else {
                throw ValidationError("--rating-range expects A:B with 0 <= A <= B <= 999, got '\(ratingRange)'")
            }
            return (false, low, high)
        }
        if let maxRating {
            guard (0...999).contains(maxRating) else {
                throw ValidationError("--max-rating must be 0-999")
            }
            return (false, nil, maxRating)
        }
        return (full, nil, nil)
    }
}

/// gm explore — the db-native exploration report machine (replaces
/// explore.md). Summary lifecycle: exploring → complete (+ complete →
/// exploring via reopen). Open is EXPLICIT-only — prompt transitions never
/// create this summary; explore verbs never move the prompt.
struct Explore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Db-native exploration report: open, key-file-add, finding-add, rank, complete, reopen, get.",
        subcommands: [Open.self, KeyFileAdd.self, FindingAdd.self, Rank.self, Complete.self, Reopen.self, Get.self]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) the prompt's exploration summary, status exploring. Idempotent; explicit-only (exploration runs while the prompt is draft).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.exploreOpen(ExploreOpenRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] exploration \(response.created ? "created" : "exists"): \(s.uuid) (\(s.status), v\(s.version))")
            }
        }
    }

    struct KeyFileAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "key-file-add",
            abstract: "Add one key file (summary must be exploring). Duplicate paths dedupe: the existing row returns, never an error.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "Repo-relative path (absolute-inside-instance is normalized).")
        var filePath: String

        func run() throws {
            let response = try withClient {
                try $0.exploreKeyFileAdd(ExploreKeyFileAddRequest(summaryUuid: summaryUuid, filePath: filePath))
            }
            if output.json { printJSON(response) } else {
                print("[gm] key file \(response.created ? "added" : "exists"): \(response.keyFile.filePath)")
            }
        }
    }

    struct FindingAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "finding-add",
            abstract: "Insert a finding (summary must be exploring). --rating is optional — unranked findings block complete until gm explore rank runs.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "persistence_model, implementation_pattern, existing_functionality, scope_creep_risk, general_relevant_change, or other")
        var kind: ExplorationFindingKind
        @Option(name: .long) var title: String
        @Option(name: .long) var body: String
        @Option(name: .long, help: "Producing agent/persona (self-reported).")
        var agentName: String
        @Option(name: .long, help: "0 (critical) … 999 (ignore); omit to insert unranked.")
        var rating: Int?

        func run() throws {
            let response = try withClient {
                try $0.exploreFindingAdd(ExploreFindingAddRequest(
                    summaryUuid: summaryUuid, kind: kind, title: title, body: body,
                    agentName: agentName, rating: rating))
            }
            if output.json { printJSON(response) } else {
                let f = response.finding
                let ratingText = f.findingRating.map(String.init) ?? "unranked"
                print("[gm] finding [\(f.kind)] (\(ratingText)): \(f.uuid)")
            }
        }
    }

    struct Rank: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Batch-rank findings (summary must be exploring). Atomic: one bad pair rejects the whole batch. Re-running re-ranks (last write wins).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "<finding-uuid>:<0-999>; repeatable.")
        var rating: [String] = []

        func run() throws {
            let pairs = try rating.map(parseRatingPair)
            guard !pairs.isEmpty else {
                throw ValidationError("pass at least one --rating <finding-uuid>:<0-999>")
            }
            let response = try withClient {
                try $0.exploreRank(ExploreRankRequest(summaryUuid: summaryUuid, ratings: pairs))
            }
            if output.json { printJSON(response) } else {
                print("[gm] ranked \(response.updatedCount) finding(s); \(response.unrankedCount) still unranked")
            }
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "exploring → complete: refuses while any finding is unranked. --overview is the report narrative — writable ONLY here, after the ranked findings.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "The narrative report body (primary agent, post-ranking).")
        var overview: String?
        @Option(name: .long, help: "Read the overview from a file instead (large narratives exceed argv limits well before the 2 MB cap).")
        var overviewFile: String?

        func run() throws {
            let body = try resolveOverview(inline: overview, file: overviewFile)
            let response = try withClient {
                try $0.exploreComplete(ExploreCompleteRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion, overview: body))
            }
            if output.json { printJSON(response) } else {
                print("[gm] exploration complete (v\(response.summary.version))")
            }
        }
    }

    struct Reopen: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "complete → exploring: the revision edge for re-runs. Everything is preserved; the next complete must re-carry --overview.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.exploreReopen(ExploreReopenRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] exploration reopened: \(response.summary.status), v\(response.summary.version)")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Summary + key files + findings, partitioned at rating 100: full rows under the window (unranked always full), stubs above.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String
        @OptionGroup var window: RatingWindowOptions

        func run() throws {
            let (full, min, max) = try window.resolve()
            let response = try withClient {
                try $0.exploreGet(ExploreGetRequest(
                    promptUuid: promptUuid, full: full, ratingMin: min, ratingMax: max))
            }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] exploration \(s.status) (v\(s.version)) — \(response.keyFiles.count) key file(s), \(response.findings.count) full finding(s), \(response.findingStubs.count) stub(s)")
                for f in response.findings {
                    let ratingText = f.findingRating.map(String.init) ?? "unranked"
                    print("  [\(ratingText)] [\(f.kind)] \(f.title) (\(f.agentName)) \(f.uuid)")
                }
                for stub in response.findingStubs {
                    let ratingText = stub.findingRating.map(String.init) ?? "unranked"
                    print("  stub [\(ratingText)] [\(stub.kind)] \(stub.title) \(stub.uuid)")
                }
                if !s.overview.isEmpty { previewLine("overview", s.overview) }
            }
        }
    }
}
