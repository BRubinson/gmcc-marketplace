import CoreGraphics
import Foundation

/// Pure, SwiftUI-free hit resolution over the resolved value — the ONLY
/// place a host gesture becomes a target. Every SwiftUI render layer stays
/// non-hit-testing; the host's single top-level DragGesture converts its
/// location to diagram space and asks here (the proven DrawingCanvasView
/// discipline: one gesture, manual hit-testing, no competing recognizers).
///
/// Deliberately outside any `#if canImport(SwiftUI)` guard so the tests run
/// in plain XCTest.
public enum DiagramHit: Sendable {
    case element(ResolvedElement)
    case edge(ResolvedEdge)
}

extension ResolvedDiagram {
    /// Hit test in THREE ordered passes — a documented deviation from strict
    /// reverse paint order, forced by two containment facts: (1) a
    /// legacy-cubic fallback edge crossing a card must not steal the card's
    /// drag (routed edges never enter a card's inflated ring, so for them
    /// paint order and this order agree), and (2) a scope outline's frame is
    /// the union of its children plus inset, so scope-before-edge would
    /// swallow every edge drawn inside the scope.
    ///
    ///   1. Entity cards (present or ghost), reverse paint order — top-level
    ///      reversed, each subtree's children reversed before the parent, so
    ///      the last-painted sibling wins.
    ///   2. Edges, by tolerance band over the routed polyline (or the
    ///      endpoint segment when routing declined).
    ///   3. Scope outlines (present or ghost), reverse paint order.
    ///
    /// `point` is DIAGRAM space; the host divides its screen tolerance by
    /// zoom so the grab radius stays constant in screen points.
    ///
    /// A `.layer` is descended into but NEVER returned (its frame is the
    /// union of its children — returning it would swallow every hit in the
    /// drawing layer's bounding box); strokes/shapes are not hit in v1.
    public func hitTest(at point: CGPoint, edgeTolerance: CGFloat = 6) -> DiagramHit? {
        for element in topLevel.reversed() {
            if let hit = Self.hitElement(element, at: point, cardsOnly: true) {
                return .element(hit)
            }
        }
        for edge in edges.reversed() {
            let points = edge.routed && edge.points.count >= 2
                ? edge.points : [edge.from, edge.to]
            for index in 0..<(points.count - 1) {
                if Self.distance(point, segment: points[index], points[index + 1])
                    <= edgeTolerance {
                    return .edge(edge)
                }
            }
        }
        for element in topLevel.reversed() {
            if let hit = Self.hitElement(element, at: point, cardsOnly: false) {
                return .element(hit)
            }
        }
        return nil
    }

    /// Depth-first lookup by uuid (paint order, first match).
    public func element(uuid: String) -> ResolvedElement? {
        func find(_ element: ResolvedElement) -> ResolvedElement? {
            if element.uuid == uuid { return element }
            for child in element.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        for element in topLevel {
            if let found = find(element) { return found }
        }
        return nil
    }

    private static func hitElement(_ element: ResolvedElement, at point: CGPoint,
                                   cardsOnly: Bool) -> ResolvedElement? {
        // Children first, reversed — the last-painted sibling wins, and an
        // entity card beats its containing scope outline.
        for child in element.children.reversed() {
            if let hit = hitElement(child, at: point, cardsOnly: cardsOnly) { return hit }
        }
        switch element.kind {
        case .layer, .stroke, .shape, .connector:
            return nil
        case .text:
            // A text box is a real bounded target — you click it to edit —
            // but it is drawing content, not a card, so it answers to the
            // same pass strokes and shapes would if they were hittable.
            guard !cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        case .entityCard, .absentEntity:
            guard cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        case .scopeCard, .absentScope:
            guard !cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        }
    }

    /// Point-to-segment distance (the Drawing/Geometry formula, kit-resident
    /// because the module boundary is a hard wall).
    static func distance(_ p: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
        let nearest = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
        return hypot(p.x - nearest.x, p.y - nearest.y)
    }
}
