import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm clarify — the db-native clarification machine (replaces qualified.md).
/// Summary lifecycle: building → answering → complete (+ complete → answering
/// via reopen). Clarify verbs never move the prompt; `gm prompt set-status`
/// is the single door for prompt transitions.
struct Clarify: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Db-native prompt clarification: open, ask, seal, answer, reopen, finalize, get.",
        subcommands: [Open.self, Ask.self, Seal.self, Answer.self, Reopen.self, Finalize.self, Get.self]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) the prompt's clarification summary, status building. Idempotent; never transitions the prompt. On a pre-m0002 prompt this is the explicit adoption path.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.clarifyOpen(ClarifyOpenRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] clarification \(response.created ? "created" : "exists"): \(s.uuid) (\(s.status), v\(s.version))")
            }
        }
    }

    struct Ask: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Insert a question (summary must be building). Pass --answer/--source bot_inferred to land a confidently-resolved detection pre-answered.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "goal or detail") var category: ClarificationCategory
        @Option(name: .long) var question: String
        @Option(name: .long, help: "Pre-answer the question at insert time.") var answer: String?
        @Option(name: .long, help: "user or bot_inferred (default bot_inferred when --answer is given).")
        var source: AnswerSource?

        func run() throws {
            let response = try withClient {
                try $0.clarifyAsk(ClarifyAskRequest(
                    summaryUuid: summaryUuid, category: category,
                    question: question, answer: answer, answerSource: source))
            }
            if output.json { printJSON(response) } else {
                let c = response.clarification
                print("[gm] clarification \(c.seq) [\(c.category)] \(c.status): \(c.uuid)")
            }
        }
    }

    struct Seal: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "building → answering: lock the question list and open answers.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.clarifySeal(ClarifySealRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] clarification sealed: \(response.summary.status), v\(response.summary.version)")
            }
        }
    }

    struct Answer: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Answer (or --skip) one question. Summary must be answering; --expected-version targets the CLARIFICATION row. Revives a skipped row.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var clarificationUuid: String
        @Option(name: .long, help: "The clarification row version this answer was based on.")
        var expectedVersion: Int64
        @Option(name: .long) var answer: String?
        @Option(name: .long, help: "Answer from a file (the argv-quoting/budget escape hatch).")
        var answerFile: String?
        @Option(name: .long, help: "user (default) or bot_inferred") var source: AnswerSource?
        @Flag(name: .long, help: "Mark the question skipped instead of answered.")
        var skip = false

        func run() throws {
            guard answer == nil || answerFile == nil else {
                throw ValidationError("--answer and --answer-file are mutually exclusive")
            }
            let answerText = try answerFile.map { file -> String in
                guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                    throw ValidationError("cannot read --answer-file: \(file)")
                }
                return content
            } ?? answer
            let response = try withClient {
                try $0.clarifyAnswer(ClarifyAnswerRequest(
                    clarificationUuid: clarificationUuid, expectedVersion: expectedVersion,
                    answer: answerText, answerSource: source, skip: skip))
            }
            if output.json { printJSON(response) } else {
                let c = response.clarification
                print("[gm] clarification \(c.seq) → \(c.status) (v\(c.version))")
            }
        }
    }

    struct Reopen: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "complete → answering: the revision edge (re-finalize afterwards).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.clarifyReopen(ClarifyReopenRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] clarification reopened: \(response.summary.status), v\(response.summary.version)")
            }
        }
    }

    struct Finalize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "answering → complete: requires every non-skipped question answered; writes the refined goal/detail and copies refined_goal into prompt.goal.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "The synthesized goal (acceptance criteria) — becomes prompt.goal.")
        var refinedGoal: String?
        @Option(name: .long, help: "Refined goal from a file (the argv-budget escape hatch).")
        var refinedGoalFile: String?
        @Option(name: .long, help: "The synthesized approach detail (answers integrated).")
        var refinedDetail: String?
        @Option(name: .long, help: "Refined detail from a file (the argv-budget escape hatch).")
        var refinedDetailFile: String?
        @Option(name: .long) var backstoryNote: String?

        func run() throws {
            let goalText = try resolveText(
                inline: refinedGoal, file: refinedGoalFile, flag: "refined-goal")
            let detailText = try resolveText(
                inline: refinedDetail, file: refinedDetailFile, flag: "refined-detail")
            let response = try withClient {
                try $0.clarifyFinalize(ClarifyFinalizeRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion,
                    refinedGoal: goalText, refinedDetail: detailText,
                    backstoryNote: backstoryNote))
            }
            if output.json { printJSON(response) } else {
                print("[gm] clarification complete (v\(response.summary.version)); prompt.goal updated (prompt v\(response.prompt.version))")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Summary + ordered clarification rows for a prompt. NOT_FOUND on a pre-m0002 prompt without one — fall back to gm artifact list (kind qualified).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] clarification \(s.status) (v\(s.version)) — \(response.clarifications.count) question(s)")
                for c in response.clarifications {
                    print("  \(c.seq). [\(c.category)] (\(c.status)) \(c.question)")
                    if let answer = c.answer {
                        print("      → \(answer) (\(c.answerSource ?? "?"))")
                    }
                }
                if !s.refinedGoal.isEmpty { print("  refined_goal: \(s.refinedGoal.prefix(200))…") }
            }
        }
    }
}
