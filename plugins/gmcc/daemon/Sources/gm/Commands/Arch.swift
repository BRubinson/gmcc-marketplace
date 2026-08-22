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
        @Option(name: .long) var body: String

        func run() throws {
            let response = try withClient {
                try $0.archSummarize(ArchSummarizeRequest(
                    summaryUuid: summaryUuid, expectedVersion: expectedVersion, body: body))
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

        func run() throws {
            let response = try withClient {
                try $0.archPersistAdd(ArchPersistAddRequest(
                    summaryUuid: summaryUuid, className: className,
                    filePath: filePath, reasonBrief: reason))
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

        func run() throws {
            let response = try withClient {
                try $0.archFieldAdd(ArchFieldAddRequest(
                    persistenceChangeUuid: persistenceUuid,
                    fieldName: fieldName, dataType: dataType,
                    changeReason: reason, changePurpose: purpose,
                    nullable: nullable, isForeignKey: foreignKey,
                    fkTarget: fkTarget, isIndexed: indexed))
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
        var code: String

        func run() throws {
            let response = try withClient {
                try $0.archGeneralAdd(ArchGeneralAddRequest(
                    summaryUuid: summaryUuid, filePath: filePath, className: className,
                    reasonBrief: reason, changeDepth: depth, changeCode: code))
            }
            if output.json { printJSON(response) } else {
                let c = response.change
                print("[gm] general change \(c.seq): \(c.filePath) [\(c.changeDepth)] (\(c.uuid))")
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
