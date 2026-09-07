import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm diagram — db-persisted canvases over the dope subsystem. Exactly one
/// owner flag picks the tier (chain-non-null ladder; promotion = update).
/// Subtype fields ride a tagged --content JSON object
/// (`{"kind":"drawing_stroke","fields":{...}}`) — the same payload enum
/// GMVibes speaks on the wire; vertices ride inside it. batch-apply is THE
/// interactive write (one transaction / revision bump / DIAGRAM_CHANGE
/// event); the granular element verbs are one-mutation batches over the
/// same daemon body. Dangling dope binding codes are legal and render as
/// ghosts, never errors.
struct Diagram: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "DIAGRAM canvases: init, list, get, element edits, batch apply, screenshot.",
        subcommands: [
            Init.self, List.self, Get.self, Update.self,
            ElementAdd.self, ElementUpdate.self, ElementDelete.self,
            BatchApply.self, Screenshot.self, FromDope.self,
        ]
    )

    // MARK: - Shared option groups

    struct OwnerOptions: ParsableArguments {
        @Option(name: .long, help: "PROJECT-tier owner (db-only tier: no gmcc_diagram_path).")
        var projectUuid: String?
        @Option(name: .long, help: "INSTANCE-tier owner.")
        var instanceUuid: String?
        @Option(name: .long, help: "SESSION-tier owner.")
        var sessionUuid: String?
        @Option(name: .long, help: "PROMPT-tier owner.")
        var promptUuid: String?
    }

    struct ContentOptions: ParsableArguments {
        @Option(name: .long, help: #"Tagged payload JSON: {"kind":"<element_type>","fields":{...}}."#)
        var content: String?
        @Option(name: .long, help: "Path to a file holding the payload JSON (argv ARG_MAX escape).")
        var contentFile: String?

        func decodePayload() throws -> DiagramElementPayload? {
            guard let data = try contentData() else { return nil }
            return try decodeWireJSON(DiagramElementPayload.self, from: data, what: "content")
        }

        private func contentData() throws -> Data? {
            switch (content, contentFile) {
            case (nil, nil):
                return nil
            case (let inline?, nil):
                return Data(inline.utf8)
            case (nil, let path?):
                return try Data(contentsOf: URL(fileURLWithPath: path))
            default:
                throw ValidationError("pass --content or --content-file, not both")
            }
        }
    }

    static func decodeWireJSON<T: Decodable>(_ type: T.Type, from data: Data, what: String) throws -> T {
        do {
            // WireCodec, not a bare JSONDecoder: the snake_case strategy is
            // the wire's casing contract and --content mirrors the wire.
            return try WireCodec.decoder.decode(type, from: data)
        } catch {
            throw ValidationError("\(what) JSON failed to decode: \(error)")
        }
    }

    static func emitNode(_ verb: String, _ response: DiagramNodeResponse, _ output: OutputOptions) {
        if output.json { printJSON(response) } else {
            print("[gm] diagram element \(verb): \(response.uuid) "
                + "(v\(response.version), revision \(response.revision))")
        }
    }

    // MARK: - Diagram row verbs

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create (or return) a diagram. Idempotent per (owner, code); exactly one owner flag picks the tier.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var owner: OwnerOptions
        @Option(name: .long, help: "snake_case diagram code.")
        var code: String
        @Option(name: .long) var name: String
        @Option(name: .long) var description: String?
        @Option(name: .long, help: "Repo path anchor (instance tier and below; refused at PROJECT tier).")
        var gmccDiagramPath: String?

        func run() throws {
            let response = try withClient {
                try $0.diagramInit(DiagramInitRequest(
                    projectUuid: owner.projectUuid, instanceUuid: owner.instanceUuid,
                    sessionUuid: owner.sessionUuid, promptUuid: owner.promptUuid,
                    code: code, name: name, description: description,
                    gmccDiagramPath: gmccDiagramPath))
            }
            if output.json { printJSON(response) } else {
                let d = response.diagram
                print("[gm] diagram \(response.created ? "created" : "exists"): "
                    + "\(d.uuid) (\(d.tier) '\(d.code)', revision \(d.revision))")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enumerate one owner's diagrams at exactly that tier (never a union). Empty is normal; an unknown owner uuid is NOT_FOUND.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var owner: OwnerOptions

        func run() throws {
            let response = try withClient {
                try $0.diagramList(DiagramListRequest(
                    projectUuid: owner.projectUuid, instanceUuid: owner.instanceUuid,
                    sessionUuid: owner.sessionUuid, promptUuid: owner.promptUuid))
            }
            if output.json { printJSON(response) } else {
                print("[gm] \(response.diagrams.count) diagram(s)")
                for d in response.diagrams {
                    print("  \(d.code) \(d.uuid)  \(d.tier)  v\(d.version) revision \(d.revision)  \(d.name)")
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read the full tree + dope binding resolutions. By --diagram-uuid, or one owner flag + --code (no cross-tier fallback). Pair with gm dope get for the bound trees.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long, help: "Direct uuid addressing (exclusive with the owner flags).")
        var diagramUuid: String?
        @OptionGroup var owner: OwnerOptions
        @Option(name: .long) var code: String?

        func run() throws {
            let response = try withClient {
                try $0.diagramGet(DiagramGetRequest(
                    diagramUuid: diagramUuid,
                    projectUuid: owner.projectUuid, instanceUuid: owner.instanceUuid,
                    sessionUuid: owner.sessionUuid, promptUuid: owner.promptUuid,
                    code: code))
            }
            if output.json { printJSON(response) } else {
                let t = response.tree
                print("[gm] diagram '\(t.code)' (\(t.tier), revision \(t.revision), "
                    + "\(response.bindings.count) dope binding(s))")
                func describe(_ node: DiagramElementNode, indent: String) {
                    let type = node.payload.elementType.rawValue
                    print("\(indent)\(node.base.code) [\(type)] '\(node.base.name)' "
                        + "@(\(node.base.centerX), \(node.base.centerY)) z\(node.base.elementZ)")
                    for child in node.children { describe(child, indent: indent + "  ") }
                }
                for element in t.elements { describe(element, indent: "  ") }
                for binding in response.bindings {
                    let via = binding.resolvedVia ?? "ABSENT (ghost)"
                    print("  binding \(binding.dopeScopeCode) → \(via)"
                        + (binding.dopeRevision.map { " (dope revision \($0))" } ?? ""))
                }
            }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update the diagram row: rename/describe, path (set/clear), tier promotion. A one-mutation batch under the hood.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var diagramUuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long, help: "Set gmcc_diagram_path (instance tier and below).")
        var gmccDiagramPath: String?
        @Flag(name: .long, help: "Set gmcc_diagram_path to NULL.")
        var clearGmccDiagramPath = false
        @Option(name: .long, help: "Promotion target tier (PROJECT|INSTANCE|SESSION|PROMPT); pair with --promote-owner-uuid.")
        var promoteTier: String?
        @Option(name: .long, help: "The owner row at the new tier (must resolve to the same project).")
        var promoteOwnerUuid: String?

        func run() throws {
            if gmccDiagramPath != nil, clearGmccDiagramPath {
                throw ValidationError("pass --gmcc-diagram-path or --clear-gmcc-diagram-path, not both")
            }
            var pathPatch: FieldPatch<String>?
            if let path = gmccDiagramPath { pathPatch = .set(path) }
            if clearGmccDiagramPath { pathPatch = .clear }

            var promotion: DiagramPromotion?
            switch (promoteTier, promoteOwnerUuid) {
            case (nil, nil):
                break
            case (let tierRaw?, let ownerUuid?):
                guard let tier = DiagramTier(rawValue: tierRaw.uppercased()) else {
                    throw ValidationError("unknown tier '\(tierRaw)'")
                }
                promotion = DiagramPromotion(tier: tier, ownerUuid: ownerUuid)
            default:
                throw ValidationError("--promote-tier and --promote-owner-uuid come together")
            }

            let update = DiagramRowUpdate(
                expectedVersion: expectedVersion, code: code, name: name,
                description: description, gmccDiagramPath: pathPatch, promotion: promotion)
            let response = try withClient {
                try $0.diagramBatchApply(DiagramBatchApplyRequest(
                    diagramUuid: diagramUuid, mutations: [.diagramUpdate(update)]))
            }
            if output.json { printJSON(response) } else {
                let version = response.results.first?.version ?? 0
                print("[gm] diagram updated: \(response.diagramUuid) "
                    + "(v\(version), revision \(response.revision))")
            }
        }
    }

    // MARK: - Element verbs (one-mutation batches over the daemon's single body)

    struct ElementAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-add",
            abstract: "Add an element. --content picks the type via its kind tag; omit --code/--name for minted defaults (stroke_0007 style).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var diagramUuid: String
        @Option(name: .long, help: "Parent element uuid — required for child types (stroke/shape under a layer, entity under a scope); refused for top-level types.")
        var parentElementUuid: String?
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?
        @Option(name: .long, help: "Position relative to the parent element (diagram space at top level).")
        var centerX: Double?
        @Option(name: .long) var centerY: Double?
        @Option(name: .long, help: "Sibling z-order.")
        var elementZ: Double?
        @Option(name: .long, help: "Composes multiplicatively down the tree; > 0.")
        var scale: Double?
        @OptionGroup var contentOptions: ContentOptions

        func run() throws {
            guard let payload = try contentOptions.decodePayload() else {
                throw ValidationError("element-add requires --content or --content-file")
            }
            let add = DiagramElementAdd(
                parentElementUuid: parentElementUuid, code: code, name: name,
                description: description, sortOrder: sortOrder, centerX: centerX,
                centerY: centerY, elementZ: elementZ, scale: scale, payload: payload)
            let response = try withClient {
                try $0.diagramNodeAdd(DiagramNodeAddRequest(diagramUuid: diagramUuid, add: add))
            }
            Diagram.emitNode("added", response, output)
        }
    }

    struct ElementUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-update",
            abstract: "Update an element (guarded by the element row's version — the aggregate lock). A present --content REPLACES the subtype row and vertex set wholesale.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Option(name: .long) var code: String?
        @Option(name: .long) var name: String?
        @Option(name: .long) var description: String?
        @Option(name: .long) var sortOrder: Int?
        @Option(name: .long) var centerX: Double?
        @Option(name: .long) var centerY: Double?
        @Option(name: .long) var elementZ: Double?
        @Option(name: .long) var scale: Double?
        @Option(name: .long, help: "Reparent under this element (child types only; containment validated).")
        var parentElementUuid: String?
        @OptionGroup var contentOptions: ContentOptions

        func run() throws {
            let update = DiagramElementUpdate(
                elementUuid: uuid, expectedVersion: expectedVersion, code: code,
                name: name, description: description, sortOrder: sortOrder,
                centerX: centerX, centerY: centerY, elementZ: elementZ, scale: scale,
                parentElementUuid: parentElementUuid,
                payload: try contentOptions.decodePayload())
            let response = try withClient {
                try $0.diagramNodeUpdate(DiagramNodeUpdateRequest(update: update))
            }
            Diagram.emitNode("updated", response, output)
        }
    }

    struct ElementDelete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-delete",
            abstract: "Delete an element and its subtree (plain CASCADE — no referrer guards in this family).")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var uuid: String
        @Option(name: .long) var expectedVersion: Int64

        func run() throws {
            let response = try withClient {
                try $0.diagramNodeDelete(DiagramNodeDeleteRequest(
                    delete: DiagramElementDelete(elementUuid: uuid, expectedVersion: expectedVersion)))
            }
            if output.json { printJSON(response) } else {
                print("[gm] diagram element deleted: \(response.deletedUuid) "
                    + "(\(response.cascadedElements) element(s) removed, revision \(response.revision))")
            }
        }
    }

    struct BatchApply: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "batch-apply",
            abstract: "Apply many typed mutations in ONE transaction/revision/event. Strict array order; elementAdd clientRefs are parentable by later mutations; all-or-nothing.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var diagramUuid: String
        @Option(name: .long, help: #"Mutations JSON array: [{"kind":"element_add","fields":{...}}, ...]."#)
        var mutations: String?
        @Option(name: .long, help: "Path to a file holding the mutations JSON (argv ARG_MAX escape).")
        var mutationsFile: String?
        @Option(name: .long, help: "Whole-diagram CAS gate: refuse unless diagram.revision equals this (gesture-end concurrency).")
        var expectedRevision: Int64?

        func run() throws {
            let data: Data
            switch (mutations, mutationsFile) {
            case (let inline?, nil):
                data = Data(inline.utf8)
            case (nil, let path?):
                data = try Data(contentsOf: URL(fileURLWithPath: path))
            default:
                throw ValidationError("pass exactly one of --mutations / --mutations-file")
            }
            let parsed = try Diagram.decodeWireJSON([DiagramMutation].self, from: data,
                                                    what: "mutations")
            let response = try withClient {
                try $0.diagramBatchApply(DiagramBatchApplyRequest(
                    diagramUuid: diagramUuid, expectedRevision: expectedRevision,
                    mutations: parsed))
            }
            if output.json { printJSON(response) } else {
                print("[gm] diagram batch applied: \(response.results.count) mutation(s), "
                    + "revision \(response.revision)")
                for result in response.results {
                    let ref = result.clientRef.map { " (\($0))" } ?? ""
                    print("  [\(result.index)] \(result.kind)\(ref): \(result.uuid ?? "-")"
                        + (result.version.map { " v\($0)" } ?? "")
                        + (result.cascadedElements.map { " (\($0) removed)" } ?? ""))
                }
            }
        }
    }
}
