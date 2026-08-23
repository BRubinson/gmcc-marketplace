import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm search — FTS5 full-text search over prompt/clarification/architecture
/// text; bm25-ranked stubs with prompt lineage, never full bodies. Top-level
/// (not under a family) because it spans prompt, clarification, and
/// architecture. Scope defaults to the current repo/branch session; --all for
/// the whole db. Does NOT index explore.md / review.md — those stay
/// pointer-only artifacts (gm artifact list).
struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Full-text search over prompt/clarification/architecture text; ranked stubs.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "Query text (all tokens must match).")
    var query: String

    @Flag(name: .long, help: "Search the whole db, ignoring the current-session default.")
    var all = false

    @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session — NOT the whole db; see --all).")
    var sessionUuid: String?

    @Option(name: .long, parsing: .upToNextOption,
            help: "Restrict to these kinds (prompt, clarification, clarification_summary, architecture_summary, architecture_general_change, architecture_persistence_change). Omit for all.")
    var kind: [SearchKind] = []

    @Option(name: .long) var limit: Int?

    func validate() throws {
        if all, sessionUuid != nil {
            throw ValidationError("--all cannot be combined with --session-uuid")
        }
    }

    func run() throws {
        let response = try withClient { client -> SearchResponse in
            let scope: String?
            if all {
                scope = nil
            } else {
                scope = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
            }
            return try client.search(SearchRequest(
                query: query,
                sessionUuid: scope,
                kinds: kind.isEmpty ? nil : kind,
                limit: limit))
        }
        if output.json {
            printJSON(response)
        } else {
            let where_ = all ? " in db" : ""
            print("[gm] \(response.hits.count) hit(s) for \"\(query)\"\(where_)")
            for hit in response.hits {
                print("  [\(hit.kind)] prompt \(hit.promptSeq) \(hit.promptName) [\(hit.promptStatus)] (score \(String(format: "%.2f", hit.score)))")
                print("    \(hit.title)")
                if !hit.excerpt.isEmpty {
                    print("    \(hit.excerpt)")
                }
                print("    prompt uuid: \(hit.promptUuid) · subject uuid: \(hit.subjectUuid)")
            }
        }
    }
}
