import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm kbite list|add|remove|maw-open|digest|get|file-get|search|keyword-tag|
/// export|import|delete — the kbite capability set over the daemon. The db
/// is the sole kbite registry (registry mutations are db-only); all ckfs
/// paths are resolved HERE and passed absolute, so the daemon never needs
/// gmcc environment variables. Bulk bytes never ride the wire: export/import
/// hand the daemon staging paths and do zip/copy work client-side.
struct Kbite: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "KBite registry, maw, digest, knowledge queries, and portable zips.",
        subcommands: [
            List.self, Add.self, Remove.self, MawOpen.self, Digest.self,
            Get.self, FileGet.self, Search.self, KeywordTag.self,
            Export.self, Import.self, Delete.self,
        ]
    )

    /// Shared scope/owner resolution: --owner-uuid wins; otherwise the
    /// context chain supplies the uuid for project/instance/session scope.
    /// Prompt scope has no ambient default — its uuid must be explicit.
    struct ScopeOptions: ParsableArguments {
        @Option(name: .long, help: "Registry scope: project, instance, session, or prompt.")
        var scope: KbiteScope = .session

        @Option(name: .long, help: "Owner uuid (defaults to the current repo/branch context for project/instance/session).")
        var ownerUuid: String?

        func resolveOwner(_ client: DaemonClient) throws -> String {
            if let ownerUuid { return ownerUuid }
            let context = try client.ensureContext(try ContextBuilder.ensureRequest())
            switch scope {
            case .project: return context.projectUuid
            case .instance: return context.instanceUuid
            case .session: return context.sessionUuid
            case .prompt:
                throw ValidationError("--owner-uuid is required for prompt scope")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Registered kbites at a scope, resolved through the inheritance chain.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var scope: ScopeOptions

        @Flag(name: .long, help: "List every kbite row in the db, ignoring scope.")
        var all = false

        func validate() throws {
            if all, scope.ownerUuid != nil {
                throw ValidationError("--all cannot be combined with --owner-uuid")
            }
        }

        func run() throws {
            let response = try withClient { client in
                if all {
                    return try client.listKbites(KbiteListRequest(
                        scope: .session, ownerUuid: "", all: true))
                }
                return try client.listKbites(KbiteListRequest(
                    scope: scope.scope, ownerUuid: try scope.resolveOwner(client)))
            }
            if output.json {
                printJSON(response)
            } else {
                let where_ = all ? "in db" : "at \(scope.scope.rawValue) scope"
                print("[gm] \(response.kbites.count) kbite(s) \(where_)")
                for kbite in response.kbites {
                    print("  \(kbite.code) \(kbite.uuid)")
                }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Explicitly register a kbite at a scope (db-only; never auto-added).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var scope: ScopeOptions

        @Option(name: .long, help: "Kbite code (snake_case, e.g. swift_sqlite).")
        var code: String

        func run() throws {
            let response = try withClient { client in
                try client.addKbite(KbiteAddRequest(
                    scope: scope.scope, ownerUuid: try scope.resolveOwner(client), code: code))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] kbite \(response.code) \(response.added ? "added to" : "already at") \(scope.scope.rawValue) scope")
                print("  uuid: \(response.kbiteUuid)")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a kbite from one scope's registry (db-only).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var scope: ScopeOptions

        @Option(name: .long) var code: String

        func run() throws {
            let response = try withClient { client in
                try client.removeKbite(KbiteRemoveRequest(
                    scope: scope.scope, ownerUuid: try scope.resolveOwner(client), code: code))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] kbite \(code) \(response.removed ? "removed from" : "was not at") \(scope.scope.rawValue) scope")
            }
        }
    }

    struct MawOpen: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "maw-open",
            abstract: "Create the open-maw filesystem skeleton (no db rows).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Kbite name (snake_case).")
        var name: String

        @Option(name: .long, help: "Maw directory (defaults to $GMCC_KBITE_OPEN/{name}).")
        var mawPath: String?

        func run() throws {
            let path = try mawPath ?? KbitePaths.openMaw(name: name).path
            let response = try withClient { client in
                try client.openKbiteMaw(KbiteMawOpenRequest(kbiteName: name, mawPath: path))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] maw open: \(response.mawPath)")
                print("  created dirs:  \(response.createdDirs.isEmpty ? "none (already present)" : response.createdDirs.joined(separator: ", "))")
                print("  created index: \(response.createdIndex)")
            }
        }
    }

    struct Digest: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "One-step import: chewed artifacts → db rows, then delete the chewed files.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Kbite code (snake_case).")
        var code: String

        @Option(name: .long, help: "Open-maw directory (defaults to $GMCC_KBITE_OPEN/{code}).")
        var kbiteOpenPath: String?

        func run() throws {
            let path = try kbiteOpenPath ?? KbitePaths.openMaw(name: code).path
            let response = try withClient { client in
                try client.digestKbite(KbiteDigestRequest(code: code, kbiteOpenPath: path))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] digested \(code): \(response.resourceCount) resource(s), \(response.fileCount) file(s), \(response.keywordCount) keyword(s)")
                print("  kbite uuid: \(response.kbiteUuid)")
                print("  deleted \(response.deletedChewedFiles.count) chewed file(s); raw sources kept")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "One kbite: resources, file stubs (no content), keywords.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var code: String

        func run() throws {
            let response = try withClient { client in
                try client.getKbite(KbiteGetRequest(code: code))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] kbite \(response.kbite.code) \(response.kbite.uuid)")
                print("  keywords: \(response.keywords.isEmpty ? "—" : response.keywords.joined(separator: ", "))")
                for resource in response.resources {
                    let trust = resource.resourceTrust == 0 ? "primary" : "secondary"
                    print("  [\(resource.resourceType)/\(trust)] \(resource.resourceName) (\(resource.files.count) file(s))")
                    for file in resource.files {
                        print("    \(file.hasContent ? "●" : "○") \(file.resourceFileName) \(file.uuid)")
                    }
                }
            }
        }
    }

    struct FileGet: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "file-get",
            abstract: "One resource file with full content (the targeted load).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var fileUuid: String

        func run() throws {
            let response = try withClient { client in
                try client.getKbiteFile(KbiteFileGetRequest(fileUuid: fileUuid))
            }
            if output.json {
                printJSON(response)
            } else {
                let file = response.file
                print("[gm] \(file.resourceFileName) \(file.uuid)")
                if !file.resourceFileSummary.isEmpty {
                    print("  summary: \(file.resourceFileSummary)")
                }
                if let content = file.resourceFileContent {
                    print(content)
                } else {
                    print("  (no inline content — raw file lives on the filesystem)")
                }
            }
        }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Full-text search across kbite files; ranked stubs.")

        @OptionGroup var output: OutputOptions

        @Argument(help: "Query text (all tokens must match).")
        var query: String

        @Option(name: .long, parsing: .upToNextOption,
                help: "Restrict to these kbite uuids (omit to search all).")
        var kbiteUuids: [String] = []

        @Option(name: .long,
                help: "Kbite code to scope to (resolved to its uuid client-side; composes with --kbite-uuids).")
        var code: String?

        @Option(name: .long) var limit: Int?

        func run() throws {
            let response = try withClient { client in
                var uuids = kbiteUuids
                if let code {
                    uuids.append(try client.getKbite(KbiteGetRequest(code: code)).kbite.uuid)
                }
                return try client.searchKbites(KbiteSearchRequest(
                    query: query,
                    kbiteUuids: uuids.isEmpty ? nil : uuids,
                    limit: limit))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.hits.count) hit(s) for \"\(query)\"")
                for hit in response.hits {
                    print("  [\(hit.kbiteCode)] \(hit.resourceName) / \(hit.fileName) (score \(String(format: "%.2f", hit.score)))")
                    print("    file uuid: \(hit.fileUuid)")
                    if !hit.fileSummary.isEmpty {
                        print("    brief: \(hit.fileSummary)")
                    }
                    if !hit.matchedKeywords.isEmpty {
                        print("    keywords: \(hit.matchedKeywords.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    // MARK: - Portable zips (export / import / delete)

    /// gmcc_kbite_{code}_{YYYYMMDD}.zip contents. Single format: MANIFEST +
    /// db_export.json + root/ (identity docs, inert) + digested/ (raw
    /// sources, .git stripped).
    private static let dbExportName = "db_export.json"
    private static let manifestName = "MANIFEST.yaml"
    private static let rootDirName = "root"
    private static let digestedDirName = "digested"

    private static func makeStaging(_ label: String) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("gm_kbite_\(label)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// YYYYMMDD from the daemon's seconds-precision ISO clock.
    private static func dateStamp() -> String {
        String(Store.isoNow().prefix(10)).replacingOccurrences(of: "-", with: "")
    }

    /// Collision-suffixed destination under a directory (the Backup.swift
    /// -N loop).
    private static func unclaimedPath(in dir: URL, base: String, ext: String?) -> URL {
        let fm = FileManager.default
        func candidate(_ suffix: String) -> URL {
            let name = ext.map { "\(base)\(suffix).\($0)" } ?? "\(base)\(suffix)"
            return dir.appendingPathComponent(name)
        }
        var destination = candidate("")
        var attempt = 2
        while fm.fileExists(atPath: destination.path) {
            destination = candidate("-\(attempt)")
            attempt += 1
        }
        return destination
    }

    /// MOVE a tree into {ckfs_root}/_archive/cold_storage/ — the house
    /// archive convention; purge/replace never rm.
    @discardableResult
    private static func moveToColdStorage(_ source: URL, label: String) throws -> URL {
        let cold = try KbitePaths.coldStorage()
        try FileManager.default.createDirectory(at: cold, withIntermediateDirectories: true)
        let destination = unclaimedPath(in: cold, base: label, ext: nil)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    /// The three machine roots that can appear inside kbite text, as
    /// scrub/rehydrate rules. Both kbite trees collapse to ONE placeholder;
    /// rehydrate maps it to the importing machine's digested tree.
    private static func prefixRules(code: String, paths: PathsGetResponse) -> [KbitePrefixRule] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let openTree = URL(fileURLWithPath: paths.kbiteOpenRoot, isDirectory: true)
            .appendingPathComponent(code, isDirectory: true).path
        let digestedTree = URL(fileURLWithPath: paths.kbiteDigestedRoot, isDirectory: true)
            .appendingPathComponent(code, isDirectory: true).path
        return [
            KbitePrefixRule(prefix: openTree, placeholder: KbiteArchive.treePlaceholder),
            KbitePrefixRule(prefix: digestedTree, placeholder: KbiteArchive.treePlaceholder),
            KbitePrefixRule(prefix: home, placeholder: KbiteArchive.homePlaceholder),
        ]
    }

    /// Rules for mapping placeholders back to THIS machine's trees.
    private static func rehydrateRules(code: String, paths: PathsGetResponse) -> [KbitePrefixRule] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let digestedTree = URL(fileURLWithPath: paths.kbiteDigestedRoot, isDirectory: true)
            .appendingPathComponent(code, isDirectory: true).path
        return [
            KbitePrefixRule(prefix: digestedTree, placeholder: KbiteArchive.treePlaceholder),
            KbitePrefixRule(prefix: home, placeholder: KbiteArchive.homePlaceholder),
        ]
    }

    /// Copy root identity docs, scrubbing/rehydrating markdown text in
    /// flight; non-markdown files copy verbatim.
    private static func copyRootDocs(
        from source: URL, to destination: URL,
        transform: (String) -> String
    ) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var copied = 0
        for name in (try? fm.contentsOfDirectory(atPath: source.path))?.sorted() ?? [] {
            let sourceFile = source.appendingPathComponent(name)
            let destFile = destination.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourceFile.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            if name.hasSuffix(".md"), let text = try? String(contentsOf: sourceFile, encoding: .utf8) {
                try transform(text).write(to: destFile, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: destFile)
                try fm.copyItem(at: sourceFile, to: destFile)
            }
            copied += 1
        }
        return copied
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export one kbite to a portable zip (db export + root docs + .git-stripped sources).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Kbite code (snake_case).")
        var code: String

        @Option(name: .long, help: "Directory for the zip (defaults to the current directory).")
        var outputDir: String?

        struct Result: Codable {
            let zipPath: String
            let kbiteUuid: String
            let resourceCount: Int
            let fileCount: Int
            let kbiteKeywordCount: Int
            let fileKeywordCount: Int
            let hasRoot: Bool
            let hasDigested: Bool
        }

        func run() throws {
            let fm = FileManager.default
            let paths = try withClient { try $0.pathsGet() }
            let staging = try Kbite.makeStaging("export")
            defer { try? fm.removeItem(at: staging) }

            // Daemon writes the scrubbed db export into staging (fails fast
            // on an unknown code, before any filesystem work).
            let response = try withClient { client in
                try client.exportKbite(KbiteExportRequest(
                    code: code,
                    dbExportPath: staging.appendingPathComponent(Kbite.dbExportName).path,
                    anonymize: Kbite.prefixRules(code: code, paths: paths)))
            }

            // Root identity docs (scrubbed) — inert content, never parsed on
            // import. KBITE_RELATIONSHIPS.md travels but is not resolved.
            let identity = try KbitePaths.identity(name: code)
            var hasRoot = false
            if fm.fileExists(atPath: identity.path) {
                let rules = Kbite.prefixRules(code: code, paths: paths)
                hasRoot = try Kbite.copyRootDocs(
                    from: identity,
                    to: staging.appendingPathComponent(Kbite.rootDirName, isDirectory: true)
                ) { KbiteArchive.scrub($0, rules: rules) } > 0
            }

            // Digested raw sources, .git stripped during the copy. A missing
            // tree degrades to a db-only export with a warning.
            let digested = try KbitePaths.digested(name: code)
            var hasDigested = false
            if fm.fileExists(atPath: digested.path) {
                try Sandbox.runProcess("/usr/bin/rsync", [
                    "-a", "--exclude=.git",
                    digested.path + "/",
                    staging.appendingPathComponent(Kbite.digestedDirName, isDirectory: true).path + "/",
                ])
                hasDigested = true
            } else if !output.json {
                print("[gm] warning: no digested tree at \(digested.path) — exporting db content only")
            }

            let manifest = """
            format_version: \(KbiteArchive.formatVersion)
            kbite_code: \(code)
            exported_at: \(Store.isoNow())
            wire_version: \(GMCCWireProtocol.version)
            resource_count: \(response.resourceCount)
            file_count: \(response.fileCount)
            kbite_keyword_count: \(response.kbiteKeywordCount)
            file_keyword_count: \(response.fileKeywordCount)
            has_root: \(hasRoot)
            has_digested: \(hasDigested)
            """
            try (manifest + "\n").write(
                to: staging.appendingPathComponent(Kbite.manifestName),
                atomically: true, encoding: .utf8)

            // Courtesy warning before compressing a giant staging tree.
            let duOut = try Sandbox.capture("/usr/bin/du", ["-sk", staging.path])
            let sizeKB = Int(duOut.split(separator: "\t").first ?? "0") ?? 0
            if sizeKB > 1_048_576 {
                FileHandle.standardError.write(
                    "[gm] warning: staging tree is \(sizeKB / 1024) MB — zipping may take a while\n"
                        .data(using: .utf8)!)
            }

            let outDir = URL(
                fileURLWithPath: outputDir ?? fm.currentDirectoryPath, isDirectory: true)
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
            let zipURL = Kbite.unclaimedPath(
                in: outDir, base: "gmcc_kbite_\(code)_\(Kbite.dateStamp())", ext: "zip")
            do {
                try Sandbox.runProcess("/usr/bin/ditto", [
                    "-c", "-k", "--sequesterRsrc", staging.path, zipURL.path,
                ])
            } catch {
                // A failed zip must not leave a partial archive behind.
                try? fm.removeItem(at: zipURL)
                throw error
            }

            let result = Result(
                zipPath: zipURL.path,
                kbiteUuid: response.kbiteUuid,
                resourceCount: response.resourceCount,
                fileCount: response.fileCount,
                kbiteKeywordCount: response.kbiteKeywordCount,
                fileKeywordCount: response.fileKeywordCount,
                hasRoot: hasRoot,
                hasDigested: hasDigested)
            if output.json {
                printJSON(result)
            } else {
                print("[gm] exported \(code): \(result.resourceCount) resource(s), \(result.fileCount) file(s), \(result.kbiteKeywordCount + result.fileKeywordCount) keyword attachment(s)")
                print("  zip: \(result.zipPath)")
                print("  root docs: \(hasRoot ? "included" : "none"); digested sources: \(hasDigested ? "included (.git stripped)" : "none")")
            }
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import a kbite zip: db rows + digested sources + root docs. Never registers.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Path to a gmcc_kbite_*.zip.")
        var zipFile: String

        @Option(name: .long, help: "When the code already exists: skip (default, non-destructive) or overwrite (preserves the kbite uuid and registrations).")
        var onCollision: KbiteImportCollision = .skip

        func run() throws {
            let fm = FileManager.default
            let staging = try Kbite.makeStaging("import")
            defer { try? fm.removeItem(at: staging) }
            try Sandbox.runProcess("/usr/bin/ditto", ["-x", "-k", zipFile, staging.path])

            let exportURL = staging.appendingPathComponent(Kbite.dbExportName)
            guard fm.fileExists(atPath: exportURL.path) else {
                throw ValidationError("no \(Kbite.dbExportName) in \(zipFile) — not a gmcc kbite archive")
            }
            // Decode once client-side for the code (rehydrate rules need it
            // before the daemon call); format gating happens daemon-side too.
            let document = try KbiteArchive.decode(try Data(contentsOf: exportURL))
            let code = document.code
            let paths = try withClient { try $0.pathsGet() }
            let rules = Kbite.rehydrateRules(code: code, paths: paths)

            // Db first, atomically. Filesystem placement only after commit.
            let response = try withClient { client in
                try client.importKbite(KbiteImportRequest(
                    dbExportPath: exportURL.path,
                    onCollision: onCollision,
                    rehydrate: rules))
            }
            if response.skippedExisting {
                if output.json {
                    printJSON(response)
                } else {
                    print("[gm] kbite \(code) already exists — skipped (re-run with --on-collision overwrite to replace it)")
                }
                return
            }

            // Digested sources: archive any existing tree, then move the
            // staged one into place.
            var notes: [String] = []
            let stagedDigested = staging.appendingPathComponent(Kbite.digestedDirName, isDirectory: true)
            if fm.fileExists(atPath: stagedDigested.path) {
                let digested = try KbitePaths.digested(name: code)
                if fm.fileExists(atPath: digested.path) {
                    let archived = try Kbite.moveToColdStorage(
                        digested, label: "gmcc_kbite_\(code)_pre_import_\(Kbite.dateStamp())")
                    notes.append("previous digested tree moved to \(archived.path)")
                }
                try fm.createDirectory(
                    at: digested.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: stagedDigested, to: digested)
                notes.append("digested sources restored to \(digested.path)")
            } else {
                notes.append("archive carried no digested sources (db content only)")
            }

            // Root identity docs, rehydrated to this machine's roots.
            let stagedRoot = staging.appendingPathComponent(Kbite.rootDirName, isDirectory: true)
            if fm.fileExists(atPath: stagedRoot.path) {
                let identity = try KbitePaths.identity(name: code)
                let copied = try Kbite.copyRootDocs(from: stagedRoot, to: identity) {
                    KbiteArchive.rehydrate($0, rules: rules)
                }
                notes.append("\(copied) root doc(s) restored to \(identity.path)")
            }

            if output.json {
                printJSON(response)
            } else {
                print("[gm] imported \(code): \(response.resourceCount) resource(s), \(response.fileCount) file(s), \(response.keywordCount) keyword(s)")
                print("  kbite uuid: \(response.kbiteUuid ?? "—")")
                for note in notes { print("  \(note)") }
                print("  not registered at any scope — run: gm kbite add --code \(code)")
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a kbite's db content (one cascade; registrations drop, events survive).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var code: String

        @Flag(name: .long, help: "Also MOVE the digested source tree to _archive/cold_storage/ (never rm).")
        var purgeFilesystem = false

        func run() throws {
            let response = try withClient { client in
                try client.deleteKbite(KbiteDeleteRequest(code: code))
            }
            var purgeNote: String?
            if purgeFilesystem {
                let digested = try KbitePaths.digested(name: code)
                if FileManager.default.fileExists(atPath: digested.path) {
                    let archived = try Kbite.moveToColdStorage(
                        digested, label: "gmcc_kbite_\(code)_\(Kbite.dateStamp())")
                    purgeNote = "digested tree moved to \(archived.path)"
                } else {
                    purgeNote = "no digested tree at \(digested.path) — nothing to purge"
                }
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] deleted \(code): \(response.deletedResources) resource(s), \(response.deletedFiles) file(s), \(response.deletedRegistrations) registration(s) dropped, \(response.gcKeywordCount) orphan keyword(s) GC'd")
                if let purgeNote { print("  \(purgeNote)") }
            }
        }
    }

    struct KeywordTag: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "keyword-tag",
            abstract: "Attach or detach keywords at kbite or file level.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "kbite or file")
        var level: KeywordTagLevel

        @Option(name: .long, help: "Kbite uuid (level=kbite) or file uuid (level=file).")
        var targetUuid: String

        @Option(name: .long, parsing: .upToNextOption, help: "Keywords (normalized to snake_case).")
        var keywords: [String]

        @Flag(name: .long, help: "Detach instead of attach.")
        var detach = false

        func run() throws {
            let response = try withClient { client in
                try client.tagKbiteKeyword(KbiteKeywordTagRequest(
                    level: level, targetUuid: targetUuid, keywords: keywords, detach: detach))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] keywords: \(response.attached) attached, \(response.detached) detached")
            }
        }
    }
}
