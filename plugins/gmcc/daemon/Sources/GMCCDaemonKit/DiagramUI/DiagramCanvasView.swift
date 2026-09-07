#if canImport(SwiftUI)
import SwiftUI

// The DIAGRAM component library. Lives INSIDE GMCCDaemonKit (not a sibling
// target) because GMVibes' vendor-daemonkit.sh copies exactly this source
// tree and generates a GRDB-only manifest — SwiftUI is an SDK framework, so
// the manifest stays valid and vendoring needs zero extra plumbing.
//
// Every view consumes ResolvedDiagram VALUES built by DiagramResolver — no
// DaemonClient, no db, no daemon dependency at render time (the no-writes
// session story). Rendering is a Canvas + native-views hybrid: real SwiftUI
// views for dope cards, Canvas paths for strokes/shapes/edges. Views make no
// flat-2D-window assumptions — geometry comes from the resolved model, not
// window queries.

/// Root view: draws a resolved diagram in diagram-space coordinates offset
/// so contentBounds' origin lands at the view origin. Only the two
/// parent-level kinds appear at the top (the store's invariant); the switch
/// is exhaustive anyway — the compiler forces every render site to handle
/// every kind, ghosts included (the prompt's critical design pattern).
public struct DiagramCanvasView: View {
    public let resolved: ResolvedDiagram

    public init(resolved: ResolvedDiagram) {
        self.resolved = resolved
    }

    private var offset: CGSize {
        CGSize(width: resolved.environment.padding - resolved.contentBounds.minX,
               height: resolved.environment.padding - resolved.contentBounds.minY)
    }

    public var totalSize: CGSize {
        CGSize(width: resolved.contentBounds.width + resolved.environment.padding * 2,
               height: resolved.contentBounds.height + resolved.environment.padding * 2)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            (resolved.environment.colorScheme == .dark
                ? Color(red: 0.11, green: 0.11, blue: 0.13)
                : Color(red: 0.97, green: 0.97, blue: 0.98))
            // Depth-first painter order; siblings arrive pre-sorted by
            // (elementZ, code) from the resolver.
            ForEach(resolved.topLevel, id: \.uuid) { element in
                ResolvedElementView(element: element, environment: resolved.environment)
            }
            DiagramEdgeCanvas(edges: resolved.edges, environment: resolved.environment)
        }
        .offset(offset)
        .frame(width: totalSize.width, height: totalSize.height, alignment: .topLeading)
        .environment(\.colorScheme, resolved.environment.colorScheme == .dark ? .dark : .light)
    }
}

/// One resolved element + its children. Exhaustive switch #2 (the resolver's
/// kind construction is #1) — both compiler-enforced over the same enum.
public struct ResolvedElementView: View {
    public let element: ResolvedElement
    public let environment: DiagramRenderEnvironment

    public init(element: ResolvedElement, environment: DiagramRenderEnvironment) {
        self.element = element
        self.environment = environment
    }

    public var body: some View {
        Group {
            switch element.kind {
            case .layer(let style):
                DrawingLayerView(element: element, style: style, environment: environment)
            case .stroke(let stroke):
                StrokeView(stroke: stroke)
            case .shape(let shape):
                ShapeView(shape: shape)
            case .scopeCard(let card):
                DopeScopeOutlineView(element: element, card: card, environment: environment)
            case .entityCard(let model):
                DopeEntityCardView(element: element, model: model,
                                   environment: environment, ghostCode: nil)
            case .absentScope(let code):
                DopeScopeOutlineView(element: element, card: nil, environment: environment,
                                     ghostCode: code)
            case .absentEntity(let code):
                DopeEntityCardView(element: element, model: nil,
                                   environment: environment, ghostCode: code)
            }
        }
    }
}

/// An endless, totally transparent grouping surface: renders nothing itself
/// beyond its children (a faint outline when locked/invisible would lie in a
/// screenshot), honoring opacity/visibility.
public struct DrawingLayerView: View {
    public let element: ResolvedElement
    public let style: LayerStyle
    public let environment: DiagramRenderEnvironment

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(element.children, id: \.uuid) { child in
                ResolvedElementView(element: child, environment: environment)
            }
        }
        .opacity(style.visible ? style.opacity : 0)
    }
}

struct StrokeView: View {
    let stroke: ResolvedStroke

    var body: some View {
        Canvas { context, _ in
            guard stroke.points.count >= 2 else { return }
            var path = Path()
            path.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() { path.addLine(to: point) }
            var color = Color(hex: stroke.color)
            if stroke.tool == .highlighter { color = color.opacity(0.4) }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: stroke.lineWidth,
                                              lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

struct ShapeView: View {
    let shape: ResolvedShape

    var body: some View {
        Canvas { context, _ in
            let path = shapePath()
            if let fill = shape.fillColor {
                context.fill(path, with: .color(Color(hex: fill)))
            }
            context.stroke(path, with: .color(Color(hex: shape.strokeColor)),
                           style: StrokeStyle(lineWidth: shape.lineWidth,
                                              lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }

    private func shapePath() -> Path {
        var path = Path()
        let points = shape.points
        switch shape.kind {
        case .rectangle:
            guard points.count >= 2 else { return path }
            let rect = CGRect(x: min(points[0].x, points[1].x),
                              y: min(points[0].y, points[1].y),
                              width: abs(points[1].x - points[0].x),
                              height: abs(points[1].y - points[0].y))
            path.addRoundedRect(in: rect, cornerSize: CGSize(
                width: shape.cornerRadius ?? 0, height: shape.cornerRadius ?? 0))
        case .ellipse:
            guard points.count >= 2 else { return path }
            let rect = CGRect(x: min(points[0].x, points[1].x),
                              y: min(points[0].y, points[1].y),
                              width: abs(points[1].x - points[0].x),
                              height: abs(points[1].y - points[0].y))
            path.addEllipse(in: rect)
        case .line:
            guard points.count >= 2 else { return path }
            path.move(to: points[0])
            path.addLine(to: points[1])
        case .arrow:
            guard points.count >= 2 else { return path }
            let from = points[0], to = points[1]
            path.move(to: from)
            path.addLine(to: to)
            let angle = atan2(to.y - from.y, to.x - from.x)
            let head: CGFloat = max(8, shape.lineWidth * 3)
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x - head * cos(angle - 0.5),
                                     y: to.y - head * sin(angle - 0.5)))
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x - head * cos(angle + 0.5),
                                     y: to.y - head * sin(angle + 0.5)))
        case .polygon:
            guard points.count >= 3 else { return path }
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}

/// The scope container: basic outline + the resolved domain-scope name (or
/// the ghost variant naming the dangling code). Children render inside.
public struct DopeScopeOutlineView: View {
    public let element: ResolvedElement
    public let card: ResolvedScopeCard?
    public let environment: DiagramRenderEnvironment
    public var ghostCode: String?

    public init(element: ResolvedElement, card: ResolvedScopeCard?,
                environment: DiagramRenderEnvironment, ghostCode: String? = nil) {
        self.element = element
        self.card = card
        self.environment = environment
        self.ghostCode = ghostCode
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5,
                                                 dash: card == nil ? [6, 4] : []))
                .foregroundStyle(card == nil ? Color.secondary : Color.accentColor.opacity(0.6))
                .frame(width: element.frame.width, height: element.frame.height)
                .position(x: element.frame.midX, y: element.frame.midY)
            HStack(spacing: 6) {
                Text(card?.scopeName ?? "⌀ \(ghostCode ?? element.code)")
                    .font(.system(size: 13, weight: .semibold))
                if let card {
                    Text(card.dopeScopeCode).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(card.resolvedVia).font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                } else {
                    Text("unresolved").font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
            }
            .position(x: element.frame.midX, y: element.frame.minY - 12)
            ForEach(element.children, id: \.uuid) { child in
                ResolvedElementView(element: child, environment: environment)
            }
        }
    }
}

/// The dbdiagram-style entity card: header tinted by the DOMAIN code's
/// stable hue, entity name + code, property rows name-left/type-right-gray,
/// badge capsules — or the dashed ghost frame naming the dangling code.
public struct DopeEntityCardView: View {
    public let element: ResolvedElement
    public let model: EntityCardModel?
    public let environment: DiagramRenderEnvironment
    public let ghostCode: String?

    public init(element: ResolvedElement, model: EntityCardModel?,
                environment: DiagramRenderEnvironment, ghostCode: String?) {
        self.element = element
        self.model = model
        self.environment = environment
        self.ghostCode = ghostCode
    }

    private var headerColor: Color {
        guard let model else { return .secondary }
        return Color(hue: model.headerHue, saturation: 0.55, brightness: 0.72)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model?.entityName ?? "⌀ missing")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(model?.entityCode ?? ghostCode ?? element.code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .frame(height: environment.cardHeaderHeight - 12)
            .background(model == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(headerColor))

            if let model {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        Text(row.name).font(.system(size: 10, design: .monospaced))
                        ForEach(row.badges, id: \.self) { badge in
                            Text(badge).font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.18)))
                        }
                        Spacer(minLength: 6)
                        Text(row.typeLabel).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: environment.cardRowHeight - 4)
                }
            } else {
                Text("no code-matching entity")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(height: environment.cardRowHeight)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: model == nil ? [4, 3] : []))
            .foregroundStyle(model == nil ? Color.secondary : Color.primary.opacity(0.25)))
        .frame(width: element.frame.width)
        .position(x: element.frame.midX, y: element.frame.midY)
    }
}

/// The FK edge pass, drawn over everything: cubic side-to-side connectors
/// between pre-anchored card border points (straight-curve v1 — no routing
/// engine).
public struct DiagramEdgeCanvas: View {
    public let edges: [ResolvedEdge]
    public let environment: DiagramRenderEnvironment

    public init(edges: [ResolvedEdge], environment: DiagramRenderEnvironment) {
        self.edges = edges
        self.environment = environment
    }

    public var body: some View {
        Canvas { context, _ in
            for edge in edges {
                var path = Path()
                path.move(to: edge.from)
                let dx = max(40, abs(edge.to.x - edge.from.x) / 2)
                let lead = edge.to.x >= edge.from.x ? dx : -dx
                path.addCurve(
                    to: edge.to,
                    control1: CGPoint(x: edge.from.x + lead, y: edge.from.y),
                    control2: CGPoint(x: edge.to.x - lead, y: edge.to.y))
                context.stroke(path, with: .color(.secondary.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.2))
                context.fill(Path(ellipseIn: CGRect(x: edge.to.x - 2.5, y: edge.to.y - 2.5,
                                                    width: 5, height: 5)),
                             with: .color(.secondary))
            }
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    /// #rgb / #rrggbb / #rrggbbaa hex parsing with a graceful gray fallback.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        var rgba: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&rgba) else {
            self = .gray
            return
        }
        let hasAlpha = value.count == 8
        let divisor = 255.0
        if hasAlpha {
            self = Color(red: Double((rgba >> 24) & 0xFF) / divisor,
                         green: Double((rgba >> 16) & 0xFF) / divisor,
                         blue: Double((rgba >> 8) & 0xFF) / divisor,
                         opacity: Double(rgba & 0xFF) / divisor)
        } else {
            self = Color(red: Double((rgba >> 16) & 0xFF) / divisor,
                         green: Double((rgba >> 8) & 0xFF) / divisor,
                         blue: Double(rgba & 0xFF) / divisor)
        }
    }
}
#endif
