import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm dope — DOPED domain modeling (Domain Optimized Project Essence
/// Driver — see DopeVocabulary). Granular db-native verbs take uuids +
/// --expected-version; the
/// whole-tree repo verbs move `.doped.json` files under
/// {instance_root}/.gmcc/dope/ where every reference is a dot-path code.
/// dope_scope.revision is the whole-tree content counter and IS the JSON
/// version field; granular edits bump it by 1 each, ingest requires exactly
/// revision + 1.
struct Dope: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "DOPED domain modeling: init, get, granular node edits, and whole-tree repo JSON I/O.",
        subcommands: [
            Init.self, List.self, Get.self, ScopeUpdate.self,
            PersistenceAdd.self, PersistenceUpdate.self, PersistenceDelete.self,
            EntityAdd.self, EntityUpdate.self, EntityDelete.self,
            PropertyAdd.self, PropertyUpdate.self, PropertyDelete.self,
            EnumAdd.self, EnumUpdate.self, EnumDelete.self,
            OptionAdd.self, OptionUpdate.self, OptionDelete.self,
            ReadRepo.self, WriteRepo.self, Ingest.self, Sync.self,
        ]
    )

    // MARK: - Shared option groups

    struct MutationTarget: ParsableArguments {
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
    }

    struct AddCommonOptions: ParsableArguments {
        @Option(name: .long, help: "Parent node uuid (scope for domain, domain for entity/enum, …).")
        var parentUuid: String
        @Option(name: .long, help: "snake_case code — the greppable reference segment.")
        var code: String
        @Option(name: .long) var name: String
        @Option(name: .long) var description: String?
        @Option(name: .long, help: "Explicit position; omitted appends at the end.")
        var sortOrder: Int?
    }

    struct UpdateCommonOptions: ParsableArguments {
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?
    }

    // MARK: - Shared runners

    static func runAdd(
        _ level: DopeLevel, _ common: AddCommonOptions, _ output: OutputOptions,
        extra: (inout PartialFields) -> Void = { _ in }
    ) throws {
        var partial = PartialFields()
        extra(&partial)
        let fields = DopeNodeFields(
            code: common.code, name: common.name, description: common.description,
            sortOrder: common.sortOrder, entityType: partial.entityType,
            repoRepresentativeFile: partial.repoRepresentativeFile,
            baseComposableUuid: partial.baseComposableUuid,
            dataType: partial.dataType, nullable: partial.nullable,
            isUnique: partial.isUnique, autoIncrement: partial.autoIncrement,
            textCharLimit: partial.textCharLimit, enumUuid: partial.enumUuid,
            relatedPropertyUuid: partial.relatedPropertyUuid,
            baseOriginPropertyUuid: partial.baseOriginPropertyUuid)
        let response = try withClient {
            try $0.dopeNodeAdd(DopeNodeAddRequest(
                level: level, parentUuid: common.parentUuid, fields: fields))
        }
        emitNode("added", response, output)
    }

    static func runUpdate(
        _ level: DopeLevel, _ target: MutationTarget, _ common: UpdateCommonOptions,
        _ output: OutputOptions, extra: (inout PartialFields) -> Void = { _ in }
    ) throws {
        var partial = PartialFields()
        extra(&partial)
        let fields = DopeNodeFields(
            code: common.code, name: common.name, description: common.description,
            sortOrder: common.sortOrder, entityType: partial.entityType,
            repoRepresentativeFile: partial.repoRepresentativeFile,
            baseComposableUuid: partial.baseComposableUuid,
            dataType: partial.dataType, nullable: partial.nullable,
            isUnique: partial.isUnique, autoIncrement: partial.autoIncrement,
            textCharLimit: partial.textCharLimit, enumUuid: partial.enumUuid,
            relatedPropertyUuid: partial.relatedPropertyUuid,
            baseOriginPropertyUuid: partial.baseOriginPropertyUuid,
            clearRepoRepresentativeFile: partial.clearRepoRepresentativeFile,
            clearBaseComposable: partial.clearBaseComposable,
            clearBaseOrigin: partial.clearBaseOrigin,
            clearAutoIncrement: partial.clearAutoIncrement,
            clearTextCharLimit: partial.clearTextCharLimit,
            clearEnum: partial.clearEnum,
            clearRelatedProperty: partial.clearRelatedProperty)
        let response = try withClient {
            try $0.dopeNodeUpdate(DopeNodeUpdateRequest(
                level: level, nodeUuid: target.uuid,
                expectedVersion: target.expectedVersion, fields: fields))
        }
        emitNode("updated", response, output)
    }

    static func runDelete(
        _ level: DopeLevel, _ target: MutationTarget, _ output: OutputOptions,
        soft: Bool = false
    ) throws {
        let response = try withClient {
            try $0.dopeNodeDelete(DopeNodeDeleteRequest(
                level: level, nodeUuid: target.uuid, expectedVersion: target.expectedVersion,
                soft: soft ? true : nil))
        }
        if output.json { printJSON(response) } else if soft {
            print("[gm] dope \(level.rawValue) soft-deleted: \(response.deletedUuid) "
                + "(tombstoned; still returned by reads, revision \(response.revision))")
        } else {
            let c = response.cascaded
            print("[gm] dope \(level.rawValue) deleted: \(response.deletedUuid) "
                + "(cascaded \(c.domains)d/\(c.entities)e/\(c.properties)p/\(c.enums)n/\(c.options)o, "
                + "revision \(response.revision))")
        }
    }

    /// `--soft` on every delete verb. Shared so the five leaves stay identical.
    struct SoftDeleteOption: ParsableArguments {
        @Flag(name: .customLong("soft"),
              help: "Tombstone (set deleted_on) instead of removing; reads still return it.")
        var soft: Bool = false
    }

    private static func emitNode(_ verb: String, _ response: DopeNodeResponse, _ output: OutputOptions) {
        if output.json { printJSON(response) } else {
            print("[gm] dope \(response.level.rawValue) \(verb): \(response.uuid) "
                + "(v\(response.version), revision \(response.revision))")
        }
    }

    /// Level-specific field overlay assembled by each leaf before the shared
    /// runner builds the wire payload.
    struct PartialFields {
        var entityType: DopeEntityType?
        var repoRepresentativeFile: String?
        var baseComposableUuid: String?
        var dataType: DopePropertyDataType?
        var nullable: Bool?
        var isUnique: Bool?
        var autoIncrement: Bool?
        var textCharLimit: Int?
        var enumUuid: String?
        var relatedPropertyUuid: String?
        var baseOriginPropertyUuid: String?
        var clearRepoRepresentativeFile: Bool?
        var clearBaseComposable: Bool?
        var clearBaseOrigin: Bool?
        var clearAutoIncrement: Bool?
        var clearTextCharLimit: Bool?
        var clearEnum: Bool?
        var clearRelatedProperty: Bool?
    }

    // MARK: - Scope

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) a dope scope. Idempotent; PROMPT-typed when --prompt-uuid is present, SESSION_BASE otherwise.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var sessionUuid: String
        @Option(name: .long, help: "Makes this a PROMPT scope (a scratch fork for prompt-context injection).")
        var promptUuid: String?
        @Option(name: .long, help: "snake_case scope code (e.g. gmcc).")
        var code: String
        @Option(name: .long) var name: String
        @Option(name: .long) var description: String?
        @Flag(name: .long, help: "Fork the session's SESSION_BASE tree of the same code into the new PROMPT scope.")
        var cloneFromSessionBase = false

        func run() throws {
            let response = try withClient {
                try $0.dopeInit(DopeInitRequest(
                    sessionUuid: sessionUuid, promptUuid: promptUuid, code: code,
                    name: name, description: description,
                    cloneFromSessionBase: cloneFromSessionBase ? true : nil))
            }
            if output.json { printJSON(response) } else {
                let s = response.scope
                print("[gm] dope scope \(response.created ? "created" : "exists"): "
                    + "\(s.uuid) (\(s.scopeType) '\(s.code)', revision \(s.revision))")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enumerate dope scopes for a picker. Without --prompt-uuid: the session's SESSION_BASE scopes; with it: ONLY that prompt's PROMPT scopes (never a union). Empty is normal; an unknown uuid is NOT_FOUND.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var sessionUuid: String
        @Option(name: .long, help: "Restrict to this prompt's PROMPT scopes instead of the session's SESSION_BASE scopes.")
        var promptUuid: String?

        func run() throws {
            let response = try withClient {
                try $0.dopeList(DopeListRequest(
                    sessionUuid: sessionUuid, promptUuid: promptUuid))
            }
            if output.json { printJSON(response) } else {
                print("[gm] \(response.scopes.count) dope scope(s)")
                for s in response.scopes {
                    print("  \(s.code) \(s.uuid)  \(s.scopeType)  v\(s.version) revision \(s.revision)  \(s.name)")
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read the full tree. With --prompt-uuid the PROMPT scope is preferred and SESSION_BASE is the fallback; --code disambiguates when a session holds several scopes.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var sessionUuid: String
        @Option(name: .long) var promptUuid: String?
        @Option(name: .long) var code: String?

        func run() throws {
            let response = try withClient {
                try $0.dopeGet(DopeGetRequest(
                    sessionUuid: sessionUuid, promptUuid: promptUuid, code: code))
            }
            if output.json { printJSON(response) } else {
                let t = response.tree
                print("[gm] dope scope '\(t.body.code)' (\(t.scopeType), via \(response.resolvedVia), revision \(t.revision))")
                for domain in t.domains {
                    print("  \(domain.body.code): \(domain.entities.count) entities, \(domain.enums.count) enums")
                    for entity in domain.entities {
                        let base = entity.body.baseComposableRef.map { " → base \($0)" } ?? ""
                        print("    \(domain.body.code).\(entity.body.code) [\(entity.body.entityType)]\(base) — \(entity.properties.count) properties")
                    }
                    for en in domain.enums {
                        print("    \(domain.body.code).enums.\(en.body.code) — \(en.options.count) options")
                    }
                }
            }
        }
    }

    struct ScopeUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scope-update",
            abstract: "Update the scope row's code/name/description (guarded by --expected-version; revision untouched semantics-wise, bumped as a content change).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?

        func run() throws {
            let fields = DopeNodeFields(code: code, name: name, description: description)
            let response = try withClient {
                try $0.dopeNodeUpdate(DopeNodeUpdateRequest(
                    level: .scope, nodeUuid: target.uuid,
                    expectedVersion: target.expectedVersion, fields: fields))
            }
            if output.json { printJSON(response) } else {
                print("[gm] dope scope updated: \(response.uuid) (v\(response.version), revision \(response.revision))")
            }
        }
    }

    // MARK: - Persistence (the level formerly spelled "domain")
    //
    // `persistence-*` is the primary spelling; `domain-*` is retained as an
    // ArgumentParser alias so every skill doc, saved prompt, and muscle-memory
    // invocation keeps working after the vocabulary rename. The ON-DISK
    // .doped.json grammar still says "domains" too — see DopeMainDocument.

    struct PersistenceAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "persistence-add",
            abstract: "Add a persistence domain under a scope.",
            aliases: ["domain-add"])
        @OptionGroup var output: OutputOptions
        @OptionGroup var common: AddCommonOptions
        func run() throws { try Dope.runAdd(.persistence, common, output) }
    }

    struct PersistenceUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "persistence-update",
            abstract: "Update a persistence domain (guarded).",
            aliases: ["domain-update"])
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var common: UpdateCommonOptions
        func run() throws { try Dope.runUpdate(.persistence, target, common, output) }
    }

    struct PersistenceDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "persistence-delete",
            abstract: "Delete a persistence domain and its subtree (cross-domain referrers are pre-checked and refused loudly).",
            aliases: ["domain-delete"])
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var softOpt: SoftDeleteOption
        func run() throws { try Dope.runDelete(.persistence, target, output, soft: softOpt.soft) }
    }

    // MARK: - Entity

    struct EntityAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "entity-add", abstract: "Add an entity under a domain ('enums' is a reserved code).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var common: AddCommonOptions
        @Option(name: .long, help: "MODEL (key entity), JUNCTION (complex join table), or BASE_COMPOSABLE (a shared column block other entities compose). Default MODEL.")
        var entityType: DopeEntityType?
        @Option(name: .long, help: "Repo-relative path of the ORM object representing this entity.")
        var repoRepresentativeFile: String?
        @Option(name: .long, help: "Uuid of a BASE_COMPOSABLE entity in the same scope whose properties this entity composes (chaining allowed, cycles refused).")
        var baseComposableUuid: String?
        func run() throws {
            try Dope.runAdd(.entity, common, output) {
                $0.entityType = entityType
                $0.repoRepresentativeFile = repoRepresentativeFile
                $0.baseComposableUuid = baseComposableUuid
            }
        }
    }

    struct EntityUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "entity-update", abstract: "Update an entity (guarded).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var common: UpdateCommonOptions
        @Option(name: .long) var entityType: DopeEntityType?
        @Option(name: .long) var repoRepresentativeFile: String?
        @Flag(name: .long, help: "Set repo_representative_file to NULL.")
        var clearRepoRepresentativeFile = false
        @Option(name: .long, help: "Uuid of a BASE_COMPOSABLE entity in the same scope whose properties this entity composes (chaining allowed, cycles refused).")
        var baseComposableUuid: String?
        @Flag(name: .long, help: "Set base_composable_uuid to NULL.")
        var clearBaseComposable = false
        func run() throws {
            try Dope.runUpdate(.entity, target, common, output) {
                $0.entityType = entityType
                $0.repoRepresentativeFile = repoRepresentativeFile
                if clearRepoRepresentativeFile { $0.clearRepoRepresentativeFile = true }
                $0.baseComposableUuid = baseComposableUuid
                if clearBaseComposable { $0.clearBaseComposable = true }
            }
        }
    }

    struct EntityDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "entity-delete",
            abstract: "Delete an entity and its properties (external relationship referrers refused loudly).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var softOpt: SoftDeleteOption
        func run() throws { try Dope.runDelete(.entity, target, output, soft: softOpt.soft) }
    }

    // MARK: - Property

    struct PropertyAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "property-add",
            abstract: "Add a property. data_type 'enum' requires --enum-uuid; 'relationship' requires --related-property-uuid (one-sided, targets a property).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var common: AddCommonOptions
        @Option(name: .long, help: "enum, relationship, boolean, uuid, int, long, decimal, text, or datetime.")
        var dataType: DopePropertyDataType
        @Flag(inversion: .prefixedNo, help: "Whether the modeled column is nullable (default nullable).")
        var nullable = true
        @Flag(inversion: .prefixedNo, help: "Simple unique constraint on the modeled column.")
        var isUnique = false
        @Flag(inversion: .prefixedNo, help: "For long properties: auto-increment. Omit both flags to leave unset.")
        var autoIncrement: Bool?
        @Option(name: .long, help: "Character limit for text properties.")
        var textCharLimit: Int?
        @Option(name: .long, help: "Enum row uuid (same scope) — required iff --data-type enum.")
        var enumUuid: String?
        @Option(name: .long, help: "Target property uuid (same scope, not itself a relationship) — required iff --data-type relationship.")
        var relatedPropertyUuid: String?
        @Option(name: .long, help: "Base property uuid this one materializes (same scope; its entity must be a BASE_COMPOSABLE this entity composes; same data_type).")
        var baseOriginUuid: String?
        func run() throws {
            try Dope.runAdd(.property, common, output) {
                $0.dataType = dataType
                $0.nullable = nullable
                $0.isUnique = isUnique
                $0.autoIncrement = autoIncrement
                $0.textCharLimit = textCharLimit
                $0.enumUuid = enumUuid
                $0.relatedPropertyUuid = relatedPropertyUuid
                $0.baseOriginPropertyUuid = baseOriginUuid
            }
        }
    }

    struct PropertyUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "property-update",
            abstract: "Update a property (guarded). The final shape must still satisfy the data_type couplings; clear flags set NULL.")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var common: UpdateCommonOptions
        @Option(name: .long) var dataType: DopePropertyDataType?
        @Flag(inversion: .prefixedNo, help: "Omit both flags to leave unchanged.")
        var nullable: Bool?
        @Flag(inversion: .prefixedNo, help: "Omit both flags to leave unchanged.")
        var isUnique: Bool?
        @Flag(inversion: .prefixedNo, help: "Omit both flags to leave unchanged.")
        var autoIncrement: Bool?
        @Option(name: .long) var textCharLimit: Int?
        @Option(name: .long) var enumUuid: String?
        @Option(name: .long) var relatedPropertyUuid: String?
        @Option(name: .long, help: "Base property uuid this one materializes (same scope; its entity must be a BASE_COMPOSABLE this entity composes; same data_type).")
        var baseOriginUuid: String?
        @Flag(name: .long, help: "Set the enum ref to NULL.") var clearEnum = false
        @Flag(name: .long, help: "Set the relationship target to NULL.") var clearRelatedProperty = false
        @Flag(name: .long, help: "Set auto_increment to NULL.") var clearAutoIncrement = false
        @Flag(name: .long, help: "Set text_char_limit to NULL.") var clearTextCharLimit = false
        @Flag(name: .long, help: "Set base_origin_property_uuid to NULL.") var clearBaseOrigin = false
        func run() throws {
            try Dope.runUpdate(.property, target, common, output) {
                $0.dataType = dataType
                $0.nullable = nullable
                $0.isUnique = isUnique
                $0.autoIncrement = autoIncrement
                $0.textCharLimit = textCharLimit
                $0.enumUuid = enumUuid
                $0.relatedPropertyUuid = relatedPropertyUuid
                $0.baseOriginPropertyUuid = baseOriginUuid
                if clearEnum { $0.clearEnum = true }
                if clearRelatedProperty { $0.clearRelatedProperty = true }
                if clearAutoIncrement { $0.clearAutoIncrement = true }
                if clearTextCharLimit { $0.clearTextCharLimit = true }
                if clearBaseOrigin { $0.clearBaseOrigin = true }
            }
        }
    }

    struct PropertyDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "property-delete",
            abstract: "Delete a property (relationship referrers refused loudly).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var softOpt: SoftDeleteOption
        func run() throws { try Dope.runDelete(.property, target, output, soft: softOpt.soft) }
    }

    // MARK: - Enum

    struct EnumAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enum-add", abstract: "Add an enum under a domain (addressed as domain.enums.code).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var common: AddCommonOptions
        @Option(name: .long, help: "Repo-relative path of the enum's source file.")
        var repoRepresentativeFile: String?
        func run() throws {
            try Dope.runAdd(.enumeration, common, output) {
                $0.repoRepresentativeFile = repoRepresentativeFile
            }
        }
    }

    struct EnumUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enum-update", abstract: "Update an enum (guarded).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var common: UpdateCommonOptions
        @Option(name: .long) var repoRepresentativeFile: String?
        @Flag(name: .long, help: "Set repo_representative_file to NULL.")
        var clearRepoRepresentativeFile = false
        func run() throws {
            try Dope.runUpdate(.enumeration, target, common, output) {
                $0.repoRepresentativeFile = repoRepresentativeFile
                if clearRepoRepresentativeFile { $0.clearRepoRepresentativeFile = true }
            }
        }
    }

    struct EnumDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enum-delete",
            abstract: "Delete an enum and its options (typed properties refused loudly).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var softOpt: SoftDeleteOption
        func run() throws { try Dope.runDelete(.enumeration, target, output, soft: softOpt.soft) }
    }

    // MARK: - Option

    struct OptionAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "option-add", abstract: "Add an option under an enum.")
        @OptionGroup var output: OutputOptions
        @OptionGroup var common: AddCommonOptions
        func run() throws { try Dope.runAdd(.option, common, output) }
    }

    struct OptionUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "option-update", abstract: "Update an option (guarded).")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var common: UpdateCommonOptions
        func run() throws { try Dope.runUpdate(.option, target, common, output) }
    }

    struct OptionDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "option-delete", abstract: "Delete an option.")
        @OptionGroup var output: OutputOptions
        @OptionGroup var target: MutationTarget
        @OptionGroup var softOpt: SoftDeleteOption
        func run() throws { try Dope.runDelete(.option, target, output, soft: softOpt.soft) }
    }

    // MARK: - Repo verbs

    struct ReadRepo: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read-repo",
            abstract: "Parse + validate {instance_root}/.gmcc/dope. Never writes; reports on-disk vs db revision drift.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long, help: "Resolve the scope's own instance root (exclusive with --dir-path).")
        var scopeUuid: String?
        @Option(name: .long, help: "Explicit instance root to read (must be a git checkout).")
        var dirPath: String?

        func run() throws {
            let response = try withClient {
                try $0.dopeReadRepo(DopeReadRepoRequest(scopeUuid: scopeUuid, dirPath: dirPath))
            }
            if output.json { printJSON(response) } else {
                print("[gm] dope on-disk revision \(response.onDiskRevision)"
                    + (response.dbRevision.map { ", db revision \($0)" } ?? "")
                    + ((response.drift == true) ? " — DRIFT" : ""))
                print("  domains: \(response.bundle.domainFiles.map(\.body.code).joined(separator: ", "))")
                for warning in response.warnings { print("  warning: \(warning)") }
            }
        }
    }

    struct WriteRepo: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "write-repo",
            abstract: "db → {instance_root}/.gmcc/dope (atomic whole-tree swap). Refuses when the files are AHEAD of the db (ingest first) unless --force.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var scopeUuid: String
        @Flag(name: .long, help: "Overwrite even when the files hold a newer version than the db.")
        var force = false

        func run() throws {
            let response = try withClient {
                try $0.dopeWriteRepo(DopeWriteRepoRequest(
                    scopeUuid: scopeUuid, force: force ? true : nil))
            }
            if output.json { printJSON(response) } else {
                if force { print("[gm] FORCED write over a newer on-disk tree") }
                print("[gm] dope wrote revision \(response.revision) → \(response.dopeRoot)")
                for path in response.filesWritten { print("  wrote \(path)") }
                for path in response.filesPruned { print("  pruned \(path)") }
            }
        }
    }

    struct Ingest: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "files → db, whole-tree overwrite (no smart diff; child uuids change). The on-disk version must be EXACTLY db revision + 1.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var scopeUuid: String
        @Option(name: .long, help: "Explicit instance root to read from; omitted = the scope's own.")
        var dirPath: String?
        @Flag(name: .long, help: """
            Files-are-authoritative (boot-sync only): accept any strictly \
            FORWARD on-disk version, including seeding a virgin scope. \
            DISCARDS db-only revisions in the gap. Never moves backward.
            """)
        var adopt = false

        func run() throws {
            let response = try withClient {
                try $0.dopeIngest(DopeIngestRequest(
                    scopeUuid: scopeUuid, dirPath: dirPath, adopt: adopt ? true : nil))
            }
            if output.json { printJSON(response) } else {
                let c = response.counts
                print("[gm] dope ingested revision \(response.scope.revision): "
                    + "\(c.domains) domains, \(c.entities) entities, \(c.properties) properties, "
                    + "\(c.enums) enums, \(c.options) options")
                if let gap = response.gapCrossed, gap > 0 {
                    print("  adopted across a gap of \(gap) db revision(s)")
                }
            }
        }
    }

    struct Sync: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: """
                Reconcile the session's SESSION_BASE scope with the repo's \
                .gmcc/dope tree (files → db, forward only). Runs automatically \
                at boot via gm context ensure; run manually after a mid-session \
                branch change.
                """)

        @OptionGroup var output: OutputOptions
        @Option(name: .long, help: "Session to sync; omitted = the current repo/branch session.")
        var sessionUuid: String?

        func run() throws {
            let git = try GitContext.detect()
            let outcome: DopeBootSync.Outcome = try withClient { client in
                let uuid = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return DopeBootSync.run(client: client, sessionUuid: uuid,
                                        instanceRoot: git.repoRoot)
            }
            if output.json {
                struct SyncReport: Codable {
                    let outcome: String
                    let notice: String?
                }
                printJSON(SyncReport(outcome: label(outcome),
                                     notice: DopeBootSync.notice(for: outcome)))
            } else if let notice = DopeBootSync.notice(for: outcome) {
                print(notice)
            } else {
                print("[gm] dope sync: \(label(outcome))")
            }
        }

        private func label(_ outcome: DopeBootSync.Outcome) -> String {
            switch outcome {
            case .noRepoTree: return "no_repo_tree"
            case .inSync: return "in_sync"
            case .seeded: return "seeded"
            case .readopted: return "readopted"
            case .filesBehind: return "files_behind"
            case .unreadable: return "unreadable"
            }
        }
    }
}
