import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm review — the db-native review report machine (replaces review.md).
/// Summary lifecycle: reviewing → complete (+ complete → reviewing via
/// reopen). Open is EXPLICIT-only; review verbs never move the prompt.
/// resolve records fix-loop outcomes per finding and is deliberately ungated
/// on summary status (the loop runs after complete).
struct Review: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Db-native review report: open, finding-add, rank, resolve, complete, reopen, get.",
        subcommands: [Open.self, FindingAdd.self, Rank.self, Resolve.self, Complete.self, Reopen.self, Get.self]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) the prompt's review summary, status reviewing. Idempotent; explicit-only (skip-to-done runs simply never open one).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.reviewOpen(ReviewOpenRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] review \(response.created ? "created" : "exists"): \(s.uuid) (\(s.status), v\(s.version))")
            }
        }
    }

    struct FindingAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "finding-add",
            abstract: "Insert a finding (summary must be reviewing). --file-path/--line-start/--line-end locate it; omit for cross-cutting findings.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "correctness_bug, spec_deviation, regression_risk, security, simplification, or other")
        var kind: ReviewFindingKind
        @Option(name: .long) var title: String
        @Option(name: .long) var body: String?
        @Option(name: .long, help: "Finding body from a file (the argv-quoting/budget escape hatch).")
        var bodyFile: String?
        @Option(name: .long, help: "Repo-relative path; omit for cross-cutting findings.")
        var filePath: String?
        @Option(name: .long) var lineStart: Int?
        @Option(name: .long, help: "Requires --line-start.")
        var lineEnd: Int?
        @Option(name: .long, help: "Producing agent/persona (self-reported).")
        var agentName: String
        @Option(name: .long, help: "0 (critical) … 999 (ignore); omit to insert unranked.")
        var rating: Int?

        func run() throws {
            let bodyText = try resolveText(inline: body, file: bodyFile, flag: "body")
            let response = try withClient {
                try $0.reviewFindingAdd(ReviewFindingAddRequest(
                    summaryUuid: summaryUuid, kind: kind, title: title, body: bodyText,
                    filePath: filePath, lineStart: lineStart, lineEnd: lineEnd,
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
            abstract: "Batch-rank findings (summary must be reviewing). Atomic; same contract as gm explore rank.")

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
                try $0.reviewRank(ReviewRankRequest(summaryUuid: summaryUuid, ratings: pairs))
            }
            if output.json { printJSON(response) } else {
                print("[gm] ranked \(response.updatedCount) finding(s); \(response.unrankedCount) still unranked")
            }
        }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record one finding's fix-loop resolution: open → fixed | accepted | wont_fix (lateral corrections allowed, never back to open). Works after complete — that's when the fix loop runs.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var findingUuid: String
        @Option(name: .long, help: "The finding row version this resolution was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "fixed, accepted, or wont_fix")
        var status: ReviewFindingStatus

        func run() throws {
            let response = try withClient {
                try $0.reviewResolve(ReviewResolveRequest(
                    findingUuid: findingUuid, expectedVersion: expectedVersion, status: status))
            }
            if output.json { printJSON(response) } else {
                let f = response.finding
                print("[gm] finding → \(f.status) (v\(f.version))")
            }
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "reviewing → complete: refuses while any finding is unranked; requires --verdict. --overview + --verdict are writable ONLY here, after the ranked findings.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "The narrative report body (primary agent, post-ranking).")
        var overview: String?
        @Option(name: .long, help: "Read the overview from a file instead (large narratives exceed argv limits well before the 2 MB cap).")
        var overviewFile: String?
        @Option(name: .long, help: "approved, approved_with_nits, or changes_requested.")
        var verdict: ReviewVerdict

        func run() throws {
            let body = try resolveOverview(inline: overview, file: overviewFile)
            let response = try withClient {
                try $0.reviewComplete(ReviewCompleteRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion,
                    overview: body, verdict: verdict))
            }
            if output.json { printJSON(response) } else {
                print("[gm] review complete (v\(response.summary.version)) — verdict: \(response.summary.verdict ?? "?")")
            }
        }
    }

    struct Reopen: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "complete → reviewing: the revision edge for re-runs. Everything is preserved; the next complete must re-carry --overview and --verdict.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.reviewReopen(ReviewReopenRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] review reopened: \(response.summary.status), v\(response.summary.version)")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Summary + findings, partitioned at rating 100 (stubs carry resolution status for the fix loop).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String
        @OptionGroup var window: RatingWindowOptions

        func run() throws {
            let (full, min, max) = try window.resolve()
            let response = try withClient {
                try $0.reviewGet(ReviewGetRequest(
                    promptUuid: promptUuid, full: full, ratingMin: min, ratingMax: max))
            }
            if output.json { printJSON(response) } else {
                let s = response.summary
                let verdictText = s.verdict ?? "-"
                print("[gm] review \(s.status) (v\(s.version), verdict \(verdictText)) — \(response.findings.count) full finding(s), \(response.findingStubs.count) stub(s)")
                for f in response.findings {
                    let ratingText = f.findingRating.map(String.init) ?? "unranked"
                    let location = f.filePath.map { path in
                        f.lineStart.map { start in
                            f.lineEnd.map { "\(path):\(start)-\($0)" } ?? "\(path):\(start)"
                        } ?? path
                    } ?? "cross-cutting"
                    print("  [\(ratingText)] [\(f.kind)] (\(f.status)) \(f.title) — \(location) \(f.uuid)")
                }
                for stub in response.findingStubs {
                    let ratingText = stub.findingRating.map(String.init) ?? "unranked"
                    print("  stub [\(ratingText)] [\(stub.kind)] (\(stub.status)) \(stub.title) \(stub.uuid)")
                }
                if !s.overview.isEmpty { previewLine("overview", s.overview) }
            }
        }
    }
}
