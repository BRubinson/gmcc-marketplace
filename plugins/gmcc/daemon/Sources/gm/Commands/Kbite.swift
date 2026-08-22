import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm kbite list|add|remove|maw-open|digest|get|file-get|search|keyword-tag —
/// the kbite capability set over the daemon. The db is the sole kbite
/// registry (registry mutations are db-only); all ckfs paths are resolved
/// HERE from $GMCC_KBITE_OPEN and passed absolute, so the daemon never needs
/// gmcc environment variables.
struct Kbite: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "KBite registry, maw, digest, and knowledge queries.",
        subcommands: [
            List.self, Add.self, Remove.self, MawOpen.self, Digest.self,
            Get.self, FileGet.self, Search.self, KeywordTag.self,
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

        @Option(name: .long) var limit: Int?

        func run() throws {
            let response = try withClient { client in
                try client.searchKbites(KbiteSearchRequest(
                    query: query,
                    kbiteUuids: kbiteUuids.isEmpty ? nil : kbiteUuids,
                    limit: limit))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.hits.count) hit(s) for \"\(query)\"")
                for hit in response.hits {
                    print("  [\(hit.kbiteCode)] \(hit.resourceName) / \(hit.fileName) (score \(String(format: "%.2f", hit.score)))")
                    print("    file uuid: \(hit.fileUuid)")
                    if !hit.matchedKeywords.isEmpty {
                        print("    keywords: \(hit.matchedKeywords.joined(separator: ", "))")
                    }
                }
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
