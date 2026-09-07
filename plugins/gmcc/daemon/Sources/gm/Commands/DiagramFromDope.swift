import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm diagram from-dope — generate (or regenerate) a domain-model canvas
/// from a dope tree in one verb: dope get → diagram init (idempotent) →
/// diagram get when revision > 0 → DopeCanvasLayout → batch-apply under the
/// diagram-revision CAS (one automatic retry on REVISION_CONFLICT).
/// Replaces scripts/diagram_from_dope.py; the layout math lives in the kit
/// beside the renderer, so generated geometry and rendered frames share one
/// formula.
extension Diagram {
    struct FromDope: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "from-dope",
            abstract: "Generate/regenerate the domain-model canvas from the dope tree in one atomic batch.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session whose dope tree (and diagram, unless --prompt-uuid) is used.")
        var sessionUuid: String
        @Option(name: .long, help: "Prompt mode: scope BOTH the dope fetch and the diagram tier to this prompt.")
        var promptUuid: String?
        @Option(name: .long, help: "Dope scope code (disambiguates when several scopes match).")
        var code: String?
        @Option(name: .long, help: "Diagram code (default: {scope_code}_domain_model).")
        var diagramCode: String?
        @Option(name: .long, help: "Write the mutations JSON here instead of (or in addition to) applying.")
        var mutationsOut: String?
        @Flag(name: .long, help: "Build and print/write the mutations without applying anything.")
        var dryRun = false

        func run() throws {
            try withClient { client in
                let dope = try client.dopeGet(DopeGetRequest(
                    sessionUuid: sessionUuid, promptUuid: promptUuid, code: code))
                let tree = dope.tree
                guard tree.domains.contains(where: { !$0.entities.isEmpty }) else {
                    print("[gm] dope scope '\(tree.body.code)' has no entities — nothing to draw")
                    return
                }

                let resolvedDiagramCode = diagramCode ?? "\(tree.body.code)_domain_model"
                let initResponse = try client.diagramInit(DiagramInitRequest(
                    sessionUuid: promptUuid == nil ? sessionUuid : nil,
                    promptUuid: promptUuid,
                    code: resolvedDiagramCode,
                    name: "\(tree.body.name) Domain Model",
                    description: "Generated from the \(tree.body.code) dope scope by gm diagram from-dope"))
                let diagramUuid = initResponse.diagram.uuid

                func build() throws -> (mutations: [DiagramMutation], revision: Int64) {
                    var existing: [DiagramElementNode] = []
                    var revision = initResponse.diagram.revision
                    if revision > 0 || initResponse.created == false {
                        let current = try client.diagramGet(
                            DiagramGetRequest(diagramUuid: diagramUuid))
                        existing = current.tree.elements
                        revision = current.tree.revision
                    }
                    return (DopeCanvasLayout.mutations(for: tree, replacing: existing), revision)
                }

                var (mutations, revision) = try build()

                if let mutationsOut {
                    // Wire-shaped JSON (snake_case) so the file round-trips
                    // through `gm diagram batch-apply --mutations-file`.
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    try (try encoder.encode(mutations))
                        .write(to: URL(fileURLWithPath: mutationsOut))
                }
                if dryRun {
                    let adds = mutations.filter { $0.kind == "element_add" }.count
                    print("[gm] dry-run: \(mutations.count) mutation(s) "
                        + "(\(mutations.count - adds) deletes, \(adds) adds)"
                        + (mutationsOut.map { " -> \($0)" } ?? ""))
                    return
                }

                let response: DiagramBatchApplyResponse
                do {
                    response = try client.diagramBatchApply(DiagramBatchApplyRequest(
                        diagramUuid: diagramUuid, expectedRevision: revision,
                        mutations: mutations))
                } catch let error as DaemonClientError {
                    // One automatic retry with a re-fetched tree — the manual
                    // loop the old command doc spelled out.
                    guard case .server(let payload) = error,
                          payload.codeRaw == "REVISION_CONFLICT" else { throw error }
                    (mutations, revision) = try build()
                    response = try client.diagramBatchApply(DiagramBatchApplyRequest(
                        diagramUuid: diagramUuid, expectedRevision: revision,
                        mutations: mutations))
                }

                if output.json {
                    printJSON(response)
                } else {
                    let adds = mutations.filter { $0.kind == "element_add" }.count
                    print("[gm] diagram '\(resolvedDiagramCode)' regenerated from dope scope "
                        + "'\(tree.body.code)': \(mutations.count - adds) deletes, \(adds) adds, "
                        + "revision \(response.revision)")
                }
            }
        }
    }
}
