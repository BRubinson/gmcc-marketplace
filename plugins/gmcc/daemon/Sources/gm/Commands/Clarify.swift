import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm clarify — the db-native clarification machine (m0025 split: user
/// questions with option/selection children, internal notes, and the care
/// package — the standalone clarified-intent bundle).
/// Summary lifecycle: building → answering → complete (+ complete → answering
/// via reopen). Clarify verbs never move the prompt; `gm prompt set-status`
/// is the single door for prompt transitions — and finalize is a PURE GATE:
/// it never writes prompt content (the prompt triple is human input only).
struct Clarify: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Db-native prompt clarification: open, question-add, note-add, seal, answer, reopen, finalize, get, package-*.",
        subcommands: [
            Open.self, QuestionAdd.self, NoteAdd.self, Seal.self, Answer.self,
            Reopen.self, Finalize.self, Get.self,
            PackageOpen.self, PackageAdd.self, PackageComplete.self, PackageGet.self,
        ]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) the prompt's clarification summary, status building. Idempotent; never transitions the prompt.")

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

    struct QuestionAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "question-add",
            abstract: "Insert a user-facing question (summary must be building). --option is repeatable and ordered; the user answers by selection and/or typed text.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long) var question: String
        @Option(name: .long, help: "Repeatable pre-authored option, in order.")
        var option: [String] = []
        @Option(name: .long, help: "Authoring agent (e.g. clarifier).") var agentName: String?
        @Option(name: .long, help: "Self-reported agent id for dedup/tracking.") var agentId: String?

        func run() throws {
            let response = try withClient {
                try $0.clarifyQuestionAdd(ClarifyQuestionAddRequest(
                    summaryUuid: summaryUuid, question: question,
                    options: option.isEmpty ? nil : option,
                    agentName: agentName, agentId: agentId))
            }
            if output.json { printJSON(response) } else {
                let q = response.question
                print("[gm] question \(q.seq) (\(q.options.count) option(s)): \(q.uuid)")
            }
        }
    }

    struct NoteAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "note-add",
            abstract: "Insert an internal clarification note (any summary state). Weight uses the finding_rating polarity: 0 = critical, 999 = ignore.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long) var body: String?
        @Option(name: .long, help: "Note body from a file (the argv-budget escape hatch).")
        var bodyFile: String?
        @Option(name: .long, help: "The entity that confused (soft ref — any uuid).")
        var confusedEntityUuid: String?
        @Option(name: .long, help: "exploration_finding | briefing | question | other")
        var confusedEntityType: String?
        @Option(name: .long, help: "0-999, 0 = critical (finding_rating polarity).")
        var weight: Int?
        @Option(name: .long, help: "Attach to an answered user question after the fact.")
        var questionUuid: String?
        @Option(name: .long) var agentName: String?
        @Option(name: .long) var agentId: String?

        func run() throws {
            let bodyText = try resolveText(inline: body, file: bodyFile, flag: "body")
            let response = try withClient {
                try $0.clarifyNoteAdd(ClarifyNoteAddRequest(
                    summaryUuid: summaryUuid, body: bodyText,
                    confusedEntityUuid: confusedEntityUuid,
                    confusedEntityType: confusedEntityType,
                    weight: weight, questionUuid: questionUuid,
                    agentName: agentName, agentId: agentId))
            }
            if output.json { printJSON(response) } else {
                let n = response.note
                print("[gm] note \(n.uuid) (weight \(n.weight.map(String.init) ?? "-"))")
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
            abstract: "Answer (or --skip) one question. Summary must be answering; --expected-version targets the QUESTION row. --select is repeatable (multi-select ready) and replaces prior selections; --answer carries typed text; both may coexist.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var questionUuid: String
        @Option(name: .long, help: "The question row version this answer was based on.")
        var expectedVersion: Int64
        @Option(name: .long) var answer: String?
        @Option(name: .long, help: "Answer from a file (the argv-quoting/budget escape hatch).")
        var answerFile: String?
        @Option(name: .long, help: "Repeatable selected option uuid.")
        var select: [String] = []
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
                    questionUuid: questionUuid, expectedVersion: expectedVersion,
                    answerText: answerText,
                    selectedOptionUuids: select.isEmpty ? nil : select,
                    skip: skip))
            }
            if output.json { printJSON(response) } else {
                let q = response.question
                print("[gm] question \(q.seq) → \(q.status) (v\(q.version))")
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
            abstract: "answering → complete — a PURE GATE: requires every question answered or skipped and the care package (where one exists) ready. Writes NOTHING to the prompt row.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.clarifyFinalize(ClarifyFinalizeRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] clarification complete (v\(response.summary.version))")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Summary + ordered questions, weighted notes, and the care package (when one exists) for a prompt.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] clarification \(s.status) (v\(s.version)) — \(response.questions.count) question(s), \(response.notes.count) note(s)")
                for q in response.questions {
                    print("  \(q.seq). (\(q.status)) \(q.question)")
                    for option in q.options {
                        let marker = q.selectedOptionUuids.contains(option.uuid) ? "✓" : " "
                        print("     [\(marker)] \(option.seq). \(option.body)")
                    }
                    if let text = q.answerText { print("      → \(text)") }
                }
                for n in response.notes {
                    print("  note (w\(n.weight.map(String.init) ?? "-")): \(n.body.prefix(160))")
                }
                if let package = response.carePackage {
                    print("  care package: \(package.uuid) (\(package.status), \(package.dopeRefs.count)/\(package.kbiteRefs.count)/\(package.explorationRefs.count) refs)")
                }
            }
        }
    }

    // MARK: - Care package

    struct PackageOpen: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "package-open",
            abstract: "Create (or return) the care package on a clarification summary (multi-agent flows; bot skips it).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String

        func run() throws {
            let response = try withClient {
                try $0.carePackageOpen(CarePackageOpenRequest(summaryUuid: summaryUuid))
            }
            if output.json { printJSON(response) } else {
                let p = response.package
                print("[gm] care package \(response.created ? "created" : "exists"): \(p.uuid) (\(p.status), v\(p.version))")
            }
        }
    }

    struct PackageAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "package-add",
            abstract: "Add one ref while building. Each kind takes its own flags; exploration entries are curated COPIES of ranked findings — never re-explore.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var packageUuid: String
        @Option(name: .long, help: "dope | kbite | exploration") var kind: CarePackageRefKind
        @Option(name: .long) var dopeCode: String?
        @Option(name: .long) var note: String?
        @Option(name: .long) var kbiteFileUuid: String?
        @Option(name: .long) var title: String?
        @Option(name: .long) var body: String?
        @Option(name: .long, help: "Curated body from a file (the argv-budget escape hatch).")
        var bodyFile: String?
        @Option(name: .long) var filePath: String?
        @Option(name: .long) var sourceFindingUuid: String?

        func run() throws {
            var curatedBody = body
            if kind == .exploration {
                curatedBody = try resolveText(inline: body, file: bodyFile, flag: "body")
            }
            let response = try withClient {
                try $0.carePackageRefAdd(CarePackageRefAddRequest(
                    packageUuid: packageUuid, kind: kind,
                    dopeCode: dopeCode, note: note, kbiteFileUuid: kbiteFileUuid,
                    curatedTitle: title, curatedBody: curatedBody,
                    filePath: filePath, sourceFindingUuid: sourceFindingUuid))
            }
            if output.json { printJSON(response) } else {
                let p = response.package
                print("[gm] care package refs: \(p.dopeRefs.count) dope / \(p.kbiteRefs.count) kbite / \(p.explorationRefs.count) exploration")
            }
        }
    }

    struct PackageComplete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "package-complete",
            abstract: "building → ready; carries the clarified intent (its ONLY write path — the intent lives on the package, never on the prompt row).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var packageUuid: String
        @Option(name: .long, help: "The package version this transition was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "The clarified intent blob (backstory+goal+detail, clarified).")
        var intent: String?
        @Option(name: .long, help: "Clarified intent from a file (the argv-budget escape hatch).")
        var intentFile: String?

        func run() throws {
            let intentText = try resolveText(inline: intent, file: intentFile, flag: "intent")
            let response = try withClient {
                try $0.carePackageComplete(CarePackageCompleteRequest(
                    packageUuid: packageUuid, expectedVersion: expectedVersion,
                    clarifiedIntent: intentText))
            }
            if output.json { printJSON(response) } else {
                let p = response.package
                print("[gm] care package ready (v\(p.version), scope rev \(p.dopeScopeRevision.map(String.init) ?? "-"))")
            }
        }
    }

    struct PackageGet: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "package-get",
            abstract: "The care package by prompt — the clarified-intent source downstream agents load.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient {
                try $0.carePackageGet(CarePackageGetRequest(promptUuid: promptUuid))
            }
            if output.json { printJSON(response) } else {
                let p = response.package
                print("[gm] care package \(p.uuid) (\(p.status), v\(p.version))")
                if !p.clarifiedIntent.isEmpty { print(p.clarifiedIntent) }
                for ref in p.dopeRefs { print("  dope: \(ref.dopeCode)\(ref.note.map { " — \($0)" } ?? "")") }
                for ref in p.kbiteRefs { print("  kbite: \(ref.kbiteResourceFileUuid)") }
                for ref in p.explorationRefs { print("  exploration: \(ref.curatedTitle)") }
            }
        }
    }
}
