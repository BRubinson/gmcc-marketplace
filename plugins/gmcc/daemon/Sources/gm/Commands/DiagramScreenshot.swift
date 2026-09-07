import ArgumentParser
import Foundation
import GMCCDaemonKit
#if canImport(SwiftUI)
import AppKit
import SwiftUI
#endif

extension Diagram {
    /// gm diagram screenshot — headless render in the gm CLIENT process,
    /// never the daemon (ImageRenderer is @MainActor and the daemon's serial
    /// single-writer loop must never host a render pass). Fetches
    /// DIAGRAM_GET + one DOPE_GET per resolved binding over the socket,
    /// resolves, renders, and writes the PNG into the instance repo's
    /// self-gitignored `.gmcc/.screenshots/`. Zero db writes (unless
    /// --artifact records the file against a prompt).
    struct Screenshot: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Render the diagram headlessly to {instance_root}/.gmcc/.screenshots/{code}_r{revision}.png. Client-side; zero db writes.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long, help: "Direct uuid addressing (exclusive with the owner flags).")
        var diagramUuid: String?
        @OptionGroup var owner: OwnerOptions
        @Option(name: .long) var code: String?
        @Option(name: .long, help: "light or dark (deterministic screenshots need an explicit scheme; default light).")
        var scheme: String = "light"
        @Option(name: .long, help: "Pixels per point in the PNG (default 2).")
        var scale: Double = 2
        @Option(name: .long, help: "Override the output file name (without extension).")
        var outName: String?
        @Flag(name: .long, help: "Also record the PNG as a prompt artifact (requires --artifact-prompt-uuid).")
        var artifact = false
        @Option(name: .long, help: "Prompt to attach the artifact row to.")
        var artifactPromptUuid: String?

        func run() throws {
            guard let colorScheme = DiagramRenderEnvironment.ColorScheme(rawValue: scheme) else {
                throw ValidationError("--scheme must be light or dark")
            }
            let (tree, context, instanceRoot) = try withClient { client
                -> (DiagramTree, DiagramDopeContext, String) in
                let get = try client.diagramGet(DiagramGetRequest(
                    diagramUuid: diagramUuid,
                    projectUuid: owner.projectUuid, instanceUuid: owner.instanceUuid,
                    sessionUuid: owner.sessionUuid, promptUuid: owner.promptUuid,
                    code: code))
                let tree = get.tree

                // One DOPE_GET per distinct RESOLVED binding code; unresolved
                // codes simply stay out of the context and render as ghosts.
                var entries: [String: DiagramDopeContext.Entry] = [:]
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
                    }
                }

                // Resolve the instance root for the sandbox: the diagram's
                // own instance FK (INSTANCE tier and below). PROJECT-tier
                // diagrams have no repo anchor — refuse loudly.
                guard let instanceUuid = tree.instanceUuid else {
                    throw ValidationError(
                        "PROJECT-tier diagrams have no instance root to save a screenshot into")
                }
                let instances = try client.listInstances(
                    InstanceListRequest(projectUuid: tree.projectUuid))
                guard let instance = instances.instances.first(where: { $0.uuid == instanceUuid })
                else {
                    throw ValidationError("instance \(instanceUuid) not found for this diagram")
                }
                return (tree, DiagramDopeContext(entries: entries),
                        instance.absoluteFileSystemPath)
            }

            let environment = DiagramRenderEnvironment(
                colorScheme: colorScheme, displayScale: scale)
            let resolved = DiagramResolver.resolve(tree, dope: context,
                                                   environment: environment)

            let pngData = try Self.renderPNG(resolved: resolved)

            let sandbox = try ScreenshotSandbox.resolve(instanceRoot: instanceRoot)
            let name = outName ?? "\(tree.code)_r\(tree.revision)"
            let path = try sandbox.writePNG(pngData, name: name)

            if artifact {
                guard let promptUuid = artifactPromptUuid else {
                    throw ValidationError("--artifact requires --artifact-prompt-uuid")
                }
                _ = try withClient {
                    try $0.addArtifact(ArtifactAddRequest(
                        promptUuid: promptUuid, filePath: path,
                        note: "diagram screenshot \(tree.code) r\(tree.revision)"))
                }
            }

            if output.json {
                struct Result: Codable {
                    let path: String
                    let diagramUuid: String
                    let revision: Int64
                    let width: Double
                    let height: Double
                }
                printJSON(Result(path: path, diagramUuid: tree.identity.uuid,
                                 revision: tree.revision,
                                 width: resolved.contentBounds.width + environment.padding * 2,
                                 height: resolved.contentBounds.height + environment.padding * 2))
            } else {
                print("[gm] diagram screenshot written: \(path) "
                    + "(revision \(tree.revision), \(resolved.topLevel.count) top-level element(s), "
                    + "\(resolved.edges.count) edge(s))")
            }
        }

        /// Headless SwiftUI → PNG on the CLI's main actor. ImageRenderer is
        /// the primary path; failure is a clean error with zero writes.
        static func renderPNG(resolved: ResolvedDiagram) throws -> Data {
            #if canImport(SwiftUI)
            return try MainActor.assumeIsolated {
                let view = DiagramCanvasView(resolved: resolved)
                let renderer = ImageRenderer(content: view)
                renderer.scale = resolved.environment.displayScale
                renderer.proposedSize = ProposedViewSize(
                    width: view.totalSize.width, height: view.totalSize.height)
                guard let cgImage = renderer.cgImage else {
                    throw ScreenshotSandbox.SandboxError(
                        "ImageRenderer produced no image (headless render failed)")
                }
                let rep = NSBitmapImageRep(cgImage: cgImage)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    throw ScreenshotSandbox.SandboxError("PNG encoding failed")
                }
                return png
            }
            #else
            throw ScreenshotSandbox.SandboxError("SwiftUI is unavailable on this platform")
            #endif
        }
    }
}
