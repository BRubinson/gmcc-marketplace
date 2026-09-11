import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm arch — the db-native architecture machine (replaces architecture.md).
/// Summary lifecycle: drafting → proposed → approved (+ proposed → drafting
/// via revise). The body is concept-level only; file changes are normalized
/// persistence/general change rows — persistence rows are always implemented
/// first. `gm arch get` derives implementation state from the file_change
/// path join. Arch verbs never move the prompt.
struct Arch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Db-native architecture: open, summarize, persist-add, field-add, general-add, propose, approve, revise, get.",
        subcommands: [
            Open.self, Summarize.self, PersistAdd.self, FieldAdd.self, GeneralAdd.self,
            OptionAdd.self, Decide.self,
            Propose.self, Approve.self, Revise.self, Get.self,
        ]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) the prompt's architecture summary, status drafting. Idempotent; never transitions the prompt.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.archOpen(ArchOpenRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] architecture \(response.created ? "created" : "exists"): \(s.uuid) (\(s.status), v\(s.version))")
            }
        }
    }

    struct Summarize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the concept-level body (approach, components, data flow, tradeoffs — NO file specifics; those are change rows). Drafting only.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this write was based on.")
        var expectedVersion: Int64
        @Option(name: .long) var body: String?
        @Option(name: .long, help: "Body from a file (the argv-budget escape hatch).")
        var bodyFile: String?

        func run() throws {
            let bodyText = try resolveText(inline: body, file: bodyFile, flag: "body")
            let response = try withClient {
                try $0.archSummarize(ArchSummarizeRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion, body: bodyText))
            }
            if output.json { printJSON(response) } else {
                print("[gm] architecture body set (v\(response.summary.version))")
            }
        }
    }

    struct PersistAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "persist-add",
            abstract: "Add a persistence-layer change (ORM/schema class). Repo-relative --file-path (absolute-inside-instance is normalized; outside rejected). Drafting only.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long) var className: String
        @Option(name: .long, help: "Repo-relative path of the persistence class's file.")
        var filePath: String
        @Option(name: .long, help: "One-line reason for the change.")
        var reason: String
        @Option(name: .long, help: "add|modify|rename|delete (default modify) — negative changes are first-class.")
        var changeKind: String?
        @Option(name: .long, help: "domain.entity dope dot-path CODE (ghost-legal, never a uuid).")
        var dopeRef: String?

        func run() throws {
            let response = try withClient {
                try $0.archPersistAdd(ArchPersistAddRequest(
                    summaryUuid: summaryUuid, className: className,
                    filePath: filePath, reasonBrief: reason,
                    changeKind: changeKind, dopeRef: dopeRef))
            }
            if output.json { printJSON(response) } else {
                let c = response.change
                print("[gm] persistence change \(c.seq): \(c.className) @ \(c.filePath) (\(c.uuid))")
            }
        }
    }

    struct FieldAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "field-add",
            abstract: "Add a field-level row under a persistence change. Drafting only.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var persistenceUuid: String
        @Option(name: .long) var fieldName: String
        @Option(name: .long) var dataType: String
        @Option(name: .long, help: "Why this field changes.") var reason: String
        @Option(name: .long, help: "What the field is for.") var purpose: String
        @Flag(name: .long, inversion: .prefixedNo, help: "Whether the column is nullable.")
        var nullable: Bool
        @Flag(name: .long, help: "Mark as a foreign key (requires --fk-target).")
        var foreignKey = false
        @Option(name: .long, help: "FK target as table.column.") var fkTarget: String?
        @Flag(name: .long, help: "Mark as indexed.") var indexed = false
        @Option(name: .long, help: "add|modify|rename|delete (default add).")
        var changeKind: String?
        @Option(name: .long, help: "Old field name (required with --change-kind rename).")
        var renamedFrom: String?
        @Option(name: .long, help: "domain.entity.property dope dot-path CODE (ghost-legal).")
        var dopePropertyRef: String?

        func run() throws {
            let response = try withClient {
                try $0.archFieldAdd(ArchFieldAddRequest(
                    persistenceChangeUuid: persistenceUuid,
                    fieldName: fieldName, dataType: dataType,
                    changeReason: reason, changePurpose: purpose,
                    nullable: nullable, isForeignKey: foreignKey,
                    fkTarget: fkTarget, isIndexed: indexed,
                    changeKind: changeKind, renamedFrom: renamedFrom,
                    dopePropertyRef: dopePropertyRef))
            }
            if output.json { printJSON(response) } else {
                let f = response.field
                print("[gm] field change \(f.seq): \(f.fieldName) \(f.dataType) (\(f.uuid))")
            }
        }
    }

    struct GeneralAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "general-add",
            abstract: "Add a non-persistence change with change_code at --depth pseudo|draft|actual (2 MB cap). Drafting only.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "Repo-relative path of the target file.")
        var filePath: String
        @Option(name: .long) var className: String?
        @Option(name: .long, help: "One-line reason for the change.")
        var reason: String
        @Option(name: .long, help: "pseudo, draft, or actual — how literal --code is.")
        var depth: ChangeDepth
        @Option(name: .long, help: "The change's code (fidelity per --depth).")
        var code: String?
        @Option(name: .long, help: "The change's code from a file (the argv-quoting/budget escape hatch).")
        var codeFile: String?

        func run() throws {
            let codeText = try resolveText(inline: code, file: codeFile, flag: "code")
            let response = try withClient {
                try $0.archGeneralAdd(ArchGeneralAddRequest(
                    summaryUuid: summaryUuid, filePath: filePath, className: className,
                    reasonBrief: reason, changeDepth: depth, changeCode: codeText))
            }
            if output.json { printJSON(response) } else {
                let c = response.change
                print("[gm] general change \(c.seq): \(c.filePath) [\(c.changeDepth)] (\(c.uuid))")
            }
        }
    }

    struct OptionAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "option-add",
            abstract: "The architect pen (m0025, team flows): write one methodology's proposal as an Option row. One per agent_name; once any option exists, change rows refuse until gm arch decide.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "Methodology persona (aggressive|conservative|pragmatic|alternative).")
        var agentName: String
        @Option(name: .long, help: "Self-reported agent id for dedup/tracking.")
        var agentId: String?
        @Option(name: .long) var body: String?
        @Option(name: .long, help: "Option body from a file (the argv-budget escape hatch).")
        var bodyFile: String?

        func run() throws {
            let bodyText = try resolveText(inline: body, file: bodyFile, flag: "body")
            let response = try withClient {
                try $0.archOptionAdd(ArchOptionAddRequest(
                    summaryUuid: summaryUuid, agentName: agentName,
                    agentId: agentId, body: bodyText))
            }
            if output.json { printJSON(response) } else {
                let o = response.option
                print("[gm] option [\(o.agentName)] \(o.status): \(o.uuid)")
            }
        }
    }

    struct Decide: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Select one option (rejecting siblings) and record the decision rationale on the summary — only then may the selected option expand into change rows. --expected-version targets the OPTION row.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var optionUuid: String
        @Option(name: .long, help: "The option row version this decision was based on.")
        var expectedVersion: Int64
        @Option(name: .long) var rationale: String?
        @Option(name: .long, help: "Rationale from a file (the argv-budget escape hatch).")
        var rationaleFile: String?

        func run() throws {
            let rationaleText = try resolveText(
                inline: rationale, file: rationaleFile, flag: "rationale")
            let response = try withClient {
                try $0.archDecide(ArchDecideRequest(
                    optionUuid: optionUuid, expectedVersion: expectedVersion,
                    rationale: rationaleText))
            }
            if output.json { printJSON(response) } else {
                for o in response.options {
                    print("  [\(o.status)] \(o.agentName): \(o.uuid)")
                }
                print("[gm] decision recorded (summary v\(response.summary.version))")
            }
        }
    }

    struct Propose: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "drafting → proposed: seal the change rows for user review.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.archPropose(ArchProposeRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] architecture proposed (v\(response.summary.version))")
            }
        }
    }

    struct Approve: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "proposed → approved (terminal): unlocks prompt architecting → implementing.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.archApprove(ArchApproveRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] architecture approved (v\(response.summary.version))")
            }
        }
    }

    struct Revise: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "proposed → drafting: reopen for revision after review feedback.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var summaryUuid: String
        @Option(name: .long, help: "The summary version this transition was based on.")
        var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.archRevise(ArchReviseRequest(summaryUuid: summaryUuid, expectedVersion: expectedVersion))
            }
            if output.json { printJSON(response) } else {
                print("[gm] architecture back to drafting (v\(response.summary.version))")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Summary + ordered changes (persistence first) decorated with implementation state from the file_change join, plus unplanned changes and the persistence-first audit. NOT_FOUND on a pre-m0002 prompt — fall back to gm artifact list (kind architecture).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { try $0.archGet(ArchGetRequest(promptUuid: promptUuid)) }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] architecture \(s.status) (v\(s.version))")
                print("  persistence changes:")
                for c in response.persistenceChanges {
                    let impl = c.implementation
                    let state = impl.fileChangeCount > 0
                        ? "touched ×\(impl.fileChangeCount), last \(impl.lastChangedAt ?? "?")"
                        : "untouched"
                    print("    \(c.seq). \(c.className) @ \(c.filePath) — \(state)")
                    for f in c.fields {
                        print("       .\(f.fieldName) \(f.dataType)\(f.nullable ? "?" : "")\(f.isForeignKey ? " FK→\(f.fkTarget ?? "?")" : "")\(f.isIndexed ? " idx" : "")")
                    }
                }
                print("  general changes:")
                for c in response.generalChanges {
                    let impl = c.implementation
                    let state = impl.fileChangeCount > 0
                        ? "touched ×\(impl.fileChangeCount), last \(impl.lastChangedAt ?? "?")"
                        : "untouched"
                    print("    \(c.seq). \(c.filePath) [\(c.changeDepth)] — \(state)")
                }
                if !response.unplannedChanges.isEmpty {
                    print("  unplanned (touched but not in the plan):")
                    for u in response.unplannedChanges {
                        print("    \(u.path) ×\(u.changeCount) (last \(u.lastChangedAt))")
                    }
                }
                if let ordered = response.orderingRespected {
                    print("  persistence-first ordering: \(ordered ? "respected" : "VIOLATED")")
                }
            }
        }
    }
}
