#if canImport(SwiftUI)
import AppKit
import SwiftUI
import XCTest
@testable import GMCCDaemonKit

/// Headless render regression for the Canvas coordinate contract: strokes at
/// NEGATIVE diagram coordinates (the common case — elements centered at 0,0)
/// must survive into the rendered pixels, and the background must paint the
/// whole frame. The review's rating-0 finding proved a plain `.offset`
/// modifier silently clips Canvas content and drags the background out of
/// frame; this test pins the fix (translate inside each Canvas, positions
/// offset per-view, background un-offset).
final class DiagramRenderSmokeTests: XCTestCase {

    @MainActor
    private func render(_ resolved: ResolvedDiagram) throws -> NSBitmapImageRep {
        let view = DiagramCanvasView(resolved: resolved)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: view.totalSize.width,
                                                 height: view.totalSize.height)
        guard let cgImage = renderer.cgImage else {
            throw XCTSkip("ImageRenderer produced no image in this environment")
        }
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    @MainActor
    func testNegativeCoordinateStrokeAndBackgroundSurviveHeadlessRender() throws {
        // A stroke whose diagram-space geometry is entirely negative.
        let stroke = DiagramElementNode(
            identity: DopeNodeIdentity(uuid: "e-s", version: 0, createdAt: "t", updatedAt: "t"),
            base: DiagramElementBase(code: "s", name: "s", description: "", sortOrder: 0,
                                     centerX: -100, centerY: -100, elementZ: 0, scale: 1),
            payload: .drawingStroke(DrawingStrokePayload(
                strokeColor: "#ff0000", strokeWidth: 12,
                vertices: [DiagramVertex(x: -30, y: 0), DiagramVertex(x: 30, y: 0)])),
            children: [])
        let layer = DiagramElementNode(
            identity: DopeNodeIdentity(uuid: "e-l", version: 0, createdAt: "t", updatedAt: "t"),
            base: DiagramElementBase(code: "l", name: "l", description: "", sortOrder: 0,
                                     centerX: 0, centerY: 0, elementZ: 0, scale: 1),
            payload: .drawingLayer(DrawingLayerPayload()),
            children: [stroke])
        let tree = DiagramTree(
            identity: DopeNodeIdentity(uuid: "d-1", version: 0, createdAt: "t", updatedAt: "t"),
            tier: "SESSION", projectUuid: "p", instanceUuid: "i", sessionUuid: "s",
            promptUuid: nil, code: "main", name: "Main", description: "",
            gmccDiagramPath: nil, revision: 0, elements: [layer])
        let environment = DiagramRenderEnvironment(displayScale: 1, padding: 20)
        let resolved = DiagramResolver.resolve(tree, dope: DiagramDopeContext(),
                                               environment: environment)
        let rep = try render(resolved)

        // The stroke's diagram-space center (-100, -100) maps to view space
        // at (padding - minX - 100, ...). Sample where the horizontal stroke
        // line must be.
        let dx = environment.padding - resolved.contentBounds.minX
        let dy = environment.padding - resolved.contentBounds.minY
        let sampleX = Int(-100 + dx), sampleY = Int(-100 + dy)
        XCTAssertGreaterThan(alpha(rep, sampleX, sampleY), 0.5,
                             "stroke at negative diagram coords was clipped away")
        // The background must cover the far corner AND the origin corner —
        // an offset background leaves one of them transparent.
        XCTAssertGreaterThan(alpha(rep, 1, 1), 0.5, "top-left background band missing")
        XCTAssertGreaterThan(alpha(rep, rep.pixelsWide - 2, rep.pixelsHigh - 2), 0.5,
                             "bottom-right background missing")
    }
}
#endif
