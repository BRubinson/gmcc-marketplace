import ArgumentParser
import Foundation
import GMCCDaemonKit
#if canImport(SwiftUI)
import AppKit
import SwiftUI
#endif

/// `gm render` — materialize a diagram as an image an agent can read.
///
/// Replaces `gm diagram screenshot`. Same pipeline (DIAGRAM_GET + one
/// DOPE_GET per resolved binding, resolve, headless ImageRenderer in the gm
/// CLIENT process — never the daemon, whose serial single-writer loop must
/// not host a @MainActor render), and the same optional `--artifact`
/// registration. Two things changed:
///
///  1. WHERE. One mutable file per diagram code under the owner's CKFS
///     storage, at every tier, instead of a per-revision file inside an
///     instance checkout. A bot reads a stable path and never has to guess
///     which of several files is current.
///
///  2. STALENESS. The obvious check — "is the file newer than the diagram" —
///     is provably wrong here, so this compares a full input FINGERPRINT
///     written beside the PNG. See `DiagramRenderFingerprint`: an entity
///     card's contents come from the bound dope tree, and editing a dope
///     property changes the picture without touching `diagram.revision` or
///     its `updated_at`. A timestamp check would report "fresh" and serve a
///     bot yesterday's schema under a current-looking path, silently.
struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a diagram to {ckfs_root}/{owner}/{diagram path}/screenshots/{code}.png and print the path. Re-renders only when stale.")

    @OptionGroup var output: OutputOptions
    @Option(name: .long, help: "Direct uuid addressing (exclusive with the owner flags).")
    var diagramUuid: String?
    @OptionGroup var owner: Diagram.OwnerOptions
    @Option(name: .long) var code: String?
    @Option(name: .long, help: "light or dark (deterministic renders need an explicit scheme; default light).")
    var scheme: String = "light"
    @Option(name: .long, help: "Pixels per point in the PNG (default 2).")
    var scale: Double = 2
    @Flag(name: .long, help: "Re-render even when the fingerprint says the file is current.")
    var force = false
    @Flag(name: .long, help: "Also record the PNG as a prompt artifact (requires --artifact-prompt-uuid).")
    var artifact = false
    @Option(name: .long, help: "Prompt to attach the artifact row to.")
    var artifactPromptUuid: String?

    func run() throws {
        guard let colorScheme = DiagramRenderEnvironment.ColorScheme(rawValue: scheme) else {
            throw ValidationError("--scheme must be light or dark")
        }

        let fetched = try withClient { client -> Fetched in
            let get = try client.diagramGet(DiagramGetRequest(
                diagramUuid: diagramUuid,
                projectUuid: owner.projectUuid, instanceUuid: nil,
                sessionUuid: owner.sessionUuid, promptUuid: owner.promptUuid,
                code: code))
            let tree = get.tree

            // One DOPE_GET per distinct RESOLVED binding code; unresolved
            // codes stay out of the context and render as ghosts.
            var entries: [String: DiagramDopeContext.Entry] = [:]
            var dopeRevisions: [String: Int64] = [:]
            if let sessionUuid = tree.sessionUuid {
                let resolvedCodes = Set(get.bindings
                    .filter { $0.resolvedVia != nil }
                    .map(\.dopeScopeCode))
                for bindingCode in resolvedCodes.sorted() {
                    let dope = try client.dopeGet(DopeGetRequest(
                        sessionUuid: sessionUuid, promptUuid: tree.promptUuid,
                        code: bindingCode))
                    entries[bindingCode] = DiagramDopeContext.Entry(
                        tree: dope.tree, resolvedVia: dope.resolvedVia)
                    // The revision that makes staleness detectable at all.
                    dopeRevisions[bindingCode] = dope.tree.revision
                }
            }

            guard let storagePath = get.ownerStoragePath else {
                throw ValidationError(
                    "the diagram's owner has no ckfs_relative_storage_path — run gm doctor")
            }
            let paths = try client.pathsGet()
            return Fetched(tree: tree, context: DiagramDopeContext(entries: entries),
                           dopeRevisions: dopeRevisions, ownerStoragePath: storagePath,
                           ckfsRoot: paths.ckfsRoot)
        }

        let tree = fetched.tree
        let relativePNG = try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: fetched.ownerStoragePath,
            gmccDiagramPath: tree.gmccDiagramPath, diagramCode: tree.code)
        let relativeFingerprint = try DiagramStorage.fingerprintRelativePath(
            ownerStoragePath: fetched.ownerStoragePath,
            gmccDiagramPath: tree.gmccDiagramPath, diagramCode: tree.code)

        let sandbox = try CkfsRenderSandbox.resolve(ckfsRoot: fetched.ckfsRoot)
        let fingerprint = DiagramRenderFingerprint(
            diagramUuid: tree.identity.uuid, diagramRevision: tree.revision,
            dopeRevisions: fetched.dopeRevisions, scheme: scheme, scale: scale)

        // FRESH PATH: the file exists AND its sidecar matches every input.
        // Nothing is rendered and nothing is written.
        if !force, sandbox.exists(relativePath: relativePNG),
           let existing = sandbox.read(relativePath: relativeFingerprint),
           let decoded = DiagramRenderFingerprint.decoded(existing),
           decoded.matches(fingerprint) {
            let path = try sandbox.url(forRelativePath: relativePNG).path
            try report(path: path, tree: tree, rendered: false,
                       elements: nil, edges: nil)
            return
        }

        let environment = DiagramRenderEnvironment(
            colorScheme: colorScheme, displayScale: scale)
        let resolved = DiagramResolver.resolve(tree, dope: fetched.context,
                                               environment: environment)
        let pngData = try Self.renderPNG(resolved: resolved)

        // PNG first, sidecar second. If the process dies between them the
        // next run sees a missing/stale fingerprint and re-renders — the
        // safe direction. The reverse order could claim a render that never
        // landed.
        let path = try sandbox.write(pngData, toRelativePath: relativePNG)
        try sandbox.write(fingerprint.encoded(), toRelativePath: relativeFingerprint)

        if artifact {
            guard let promptUuid = artifactPromptUuid else {
                throw ValidationError("--artifact requires --artifact-prompt-uuid")
            }
            _ = try withClient {
                try $0.addArtifact(ArtifactAddRequest(
                    promptUuid: promptUuid, filePath: path,
                    note: "diagram render \(tree.code) r\(tree.revision)"))
            }
        }

        try report(path: path, tree: tree, rendered: true,
                   elements: resolved.topLevel.count, edges: resolved.edges.count)
    }

    private struct Fetched {
        let tree: DiagramTree
        let context: DiagramDopeContext
        let dopeRevisions: [String: Int64]
        let ownerStoragePath: String
        let ckfsRoot: String
    }

    /// stdout is the CONTRACT here: the last thing printed is the path an
    /// agent reads, in both modes.
    private func report(path: String, tree: DiagramTree, rendered: Bool,
                        elements: Int?, edges: Int?) throws {
        if output.json {
            struct Result: Codable {
                let path: String
                let diagramUuid: String
                let revision: Int64
                let rendered: Bool
            }
            printJSON(Result(path: path, diagramUuid: tree.identity.uuid,
                             revision: tree.revision, rendered: rendered))
        } else if rendered {
            print("[gm] rendered: \(path) (revision \(tree.revision), "
                + "\(elements ?? 0) top-level element(s), \(edges ?? 0) edge(s))")
        } else {
            print("[gm] current, not re-rendered: \(path) (revision \(tree.revision))")
        }
    }

    /// Headless SwiftUI → PNG on the CLI's main actor.
    static func renderPNG(resolved: ResolvedDiagram) throws -> Data {
        #if canImport(SwiftUI)
        return try MainActor.assumeIsolated {
            let view = DiagramCanvasView(resolved: resolved)
            let renderer = ImageRenderer(content: view)
            renderer.scale = resolved.environment.displayScale
            renderer.proposedSize = ProposedViewSize(
                width: view.totalSize.width, height: view.totalSize.height)
            guard let cgImage = renderer.cgImage else {
                throw CkfsRenderSandbox.SandboxError(
                    "ImageRenderer produced no image (headless render failed)")
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CkfsRenderSandbox.SandboxError("PNG encoding failed")
            }
            return png
        }
        #else
        throw CkfsRenderSandbox.SandboxError("SwiftUI is unavailable on this platform")
        #endif
    }
}
