import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm cog — COGS (Coordination Of General Systems).
///
/// A peer family over dope rather than more `gm dope *-` verbs, matching the
/// precedent that `gm diagram` is a peer family too. Cog rows live inside a
/// dope scope and share its revision counter, tombstone rules and tiers.
struct Cog: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Coordination Of General Systems — the project's primary systems.",
        subcommands: [Add.self, Update.self, Delete.self, Get.self,
                      ElementAdd.self, ElementUpdate.self, ElementDelete.self]
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add", abstract: "Add a cog to a dope scope.")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var scopeUuid: String
        @Option(name: .long) var code: String
        @Option(name: .long) var name: String
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?

        func run() throws {
            let r = try withClient {
                try $0.dopeCogAdd(DopeCogAddRequest(
                    scopeUuid: scopeUuid, code: code, name: name,
                    description: description, sortOrder: sortOrder))
            }
            emit(r, output)
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update", abstract: "Update a cog (guarded).")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?

        func run() throws {
            let r = try withClient {
                try $0.dopeCogUpdate(DopeCogUpdateRequest(
                    uuid: uuid, expectedVersion: expectedVersion, code: code, name: name,
                    description: description, sortOrder: sortOrder))
            }
            emit(r, output)
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete", abstract: "Delete a cog and its elements.")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Flag(name: .customLong("soft"),
              help: "Tombstone instead of removing (masking scopes only).")
        var soft: Bool = false

        func run() throws {
            let r = try withClient {
                try $0.dopeCogDelete(DopeCogDeleteRequest(
                    uuid: uuid, expectedVersion: expectedVersion, soft: soft ? true : nil))
            }
            if output.json { printJSON(r) } else {
                print("[gm] cog \(soft ? "soft-deleted" : "deleted"): \(r.deletedUuid) "
                    + "(\(r.cascadedElements) element(s), revision \(r.revision))")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get", abstract: "Read a scope's cogs and their elements.")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var scopeUuid: String
        @Option(name: .long) var code: String?

        func run() throws {
            let r = try withClient {
                try $0.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid, code: code))
            }
            if output.json { printJSON(r) } else {
                print("[gm] \(r.cogs.count) cog(s)")
                for cog in r.cogs {
                    let dead = cog.deletedOn != nil ? " [tombstoned]" : ""
                    print("  \(cog.code) (\(cog.name))\(dead) — \(cog.elements.count) element(s)")
                    for e in cog.elements {
                        let path = e.primaryPath.map { " → \($0)" } ?? ""
                        let bind = e.dopeScopeCode.map { " [scope \($0)]" } ?? ""
                        print("    \(e.code) [\(e.elementType)]\(path)\(bind)")
                    }
                }
            }
        }
    }

    struct ElementAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-add", abstract: "Add a typed element to a cog.")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var cogUuid: String
        @Option(name: .long, help: "Registry type: Hull or PersistenceOwner.")
        var elementType: String = DopeCogElementType.hull.rawValue
        @Option(name: .long) var code: String
        @Option(name: .long) var name: String
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?
        @Option(name: .long) var parentElementUuid: String?
        @Option(name: .long, help: "Ghost-tolerant dope scope code this element points at.")
        var dopeScopeCode: String?
        @Option(name: .long, help: "Root path of the hull. Required for Hull.")
        var primaryPath: String?
        @Option(name: .long,
                help: "Owned persistence domain CODE. Required for PersistenceOwner.")
        var dopePersistenceCode: String?

        func run() throws {
            let r = try withClient {
                try $0.dopeCogElementAdd(DopeCogElementAddRequest(
                    cogUuid: cogUuid, elementType: elementType, code: code, name: name,
                    description: description, sortOrder: sortOrder,
                    parentElementUuid: parentElementUuid, dopeScopeCode: dopeScopeCode,
                    primaryPath: primaryPath, dopePersistenceCode: dopePersistenceCode))
            }
            emitElement(r, output)
        }
    }

    struct ElementUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-update", abstract: "Update a cog element (guarded).")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?
        @Option(name: .long) var dopeScopeCode: String?
        @Flag(name: .customLong("clear-dope-scope-code")) var clearDopeScopeCode: Bool = false
        @Option(name: .long) var primaryPath: String?

        func run() throws {
            let r = try withClient {
                try $0.dopeCogElementUpdate(DopeCogElementUpdateRequest(
                    uuid: uuid, expectedVersion: expectedVersion, code: code, name: name,
                    description: description, sortOrder: sortOrder,
                    dopeScopeCode: dopeScopeCode,
                    clearDopeScopeCode: clearDopeScopeCode ? true : nil,
                    primaryPath: primaryPath))
            }
            emitElement(r, output)
        }
    }

    struct ElementDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-delete", abstract: "Delete a cog element and its children.")
        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Flag(name: .customLong("soft"),
              help: "Tombstone instead of removing (masking scopes only).")
        var soft: Bool = false

        func run() throws {
            let r = try withClient {
                try $0.dopeCogElementDelete(DopeCogElementDeleteRequest(
                    uuid: uuid, expectedVersion: expectedVersion, soft: soft ? true : nil))
            }
            if output.json { printJSON(r) } else {
                print("[gm] cog element \(soft ? "soft-deleted" : "deleted"): \(r.deletedUuid) "
                    + "(\(r.cascadedElements) child element(s), revision \(r.revision))")
            }
        }
    }
}

private func emit(_ r: DopeCogResponse, _ output: OutputOptions) {
    if output.json { printJSON(r) } else {
        print("[gm] cog \(r.cog.code) (v\(r.cog.version), revision \(r.revision))")
    }
}

private func emitElement(_ r: DopeCogElementResponse, _ output: OutputOptions) {
    if output.json { printJSON(r) } else {
        print("[gm] cog element \(r.element.code) [\(r.element.elementType)] "
            + "(v\(r.element.version), revision \(r.revision))")
    }
}
