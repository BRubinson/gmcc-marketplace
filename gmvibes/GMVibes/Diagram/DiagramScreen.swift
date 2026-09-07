import SwiftUI
import GMCCDaemonKit

/// The full-window Doped Viewer (`Route.diagram`): the session's dope tree
/// rendered as an interactive diagram on the kit's slot-rich DiagramUI
/// components. NON-PERSISTED: every write flows through DiagramEditSession →
/// LocalDiagramCommitter → DiagramTreeReducer, zero daemon writes.
///
/// COORDINATE COMPOSITION (the load-bearing decision): pan rides the kit's
/// diagram-space `offset:` parameter (applied INSIDE each Canvas and on each
/// .position — the ffc9bb5-safe path; the `.offset` modifier is BANNED
/// here), zoom rides `.scaleEffect(zoom, anchor: .topLeading)`. That
/// composes to screen = diagram·zoom + viewport.offset — exactly
/// `DiagramViewport.toScreen`, so the salvaged viewport stays the single
/// screen↔diagram truth.
struct DiagramScreen: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramWorkspaceStore.self) private var workspaces
    @Environment(\.colorScheme) private var colorScheme
    let windowID: SessionWindowID
    let scopeCode: String

    @State private var scope: SessionScope
    @State private var viewState = DiagramViewState()
    @State private var sink = DiagramScrollBridge.Sink()
    @State private var dragStartLocation: CGPoint?
    @State private var dragIntent: DragIntent?
    @State private var zoomBase: CGFloat?
    @State private var lastPan: CGSize = .zero
    @State private var hostSize: CGSize = .zero
    @State private var didInitialFit = false

    init(windowID: SessionWindowID, scopeCode: String) {
        self.windowID = windowID
        self.scopeCode = scopeCode
        _scope = State(initialValue: SessionScopeCache.shared.scope(
            for: windowID.sessionUUID.wireString))
    }

    private var workspace: DiagramWorkspace {
        workspaces.workspace(for: .init(sessionUuid: windowID.sessionUUID.wireString,
                                        scopeCode: scopeCode))
    }

    /// Decided ONCE at gesture start (the ported DrawingCanvasView
    /// discipline) — re-deciding per frame lets a card slide out from under
    /// the cursor and flips a move into a pan mid-drag.
    private enum DragIntent {
        case pan
        case move(uuid: String, node: DiagramElementNode, grab: CGPoint)
        case draw(tool: DiagramTool, anchor: CGPoint)
    }

    var body: some View {
        ScreenScaffold(title: "Diagram · \(windowID.sessionName)",
                       subtitle: scopeCode) {
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DiagramToolStrip(workspace: workspace, viewState: viewState,
                                 onCenter: center(on:), onFit: fit,
                                 onOrganize: organize)
            }
        }
        .task(id: daemon.generation) {
            // The diagram reads the SAME loaded dope response the pane shows.
            let store = scope.dope
            let key = DopeStore.Key(promptUuid: nil, code: scopeCode)
            store.beginObserving(DopeStore.Key(promptUuid: nil))
            defer { store.endObserving(DopeStore.Key(promptUuid: nil)) }
            let stream = daemon.hub.stream(for: .dope(store.sessionUuid))
            await store.load(key)
            syncFromDope()
            for await _ in stream {
                try? await Task.sleep(for: .milliseconds(300))
                await store.reloadLive()
                // reloadLive refreshes the store's own resolved keys — in the
                // single-scope case that is Key(code: nil), NOT this screen's
                // explicit-code key. Reload ours too or the diagram never
                // sees another dope write after first load.
                await store.load(key)
                syncFromDope()
            }
        }
        // A rebuild re-mints dope element uuids: drop any selection or drag
        // freeze that now points at a vanished element.
        .onChange(of: workspace.generation) {
            if let selected = viewState.selection.selectedElementUuid,
               workspace.resolved.element(uuid: selected) == nil {
                clearSelection()
            }
            if let draft = viewState.dragDraft,
               workspace.resolved.element(uuid: draft.elementUuid) == nil {
                viewState.dragDraft = nil
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            workspace.reskin(newScheme)   // O(1) — no A* re-run
        }
    }

    private func syncFromDope() {
        let store = scope.dope
        let key = DopeStore.Key(promptUuid: nil, code: scopeCode)
        if case .loaded(let response) = store.phase(key) {
            workspace.load(response, scheme: colorScheme)
            attemptInitialFit()
        }
    }

    /// The first fit needs BOTH the loaded tree and a real host size — either
    /// can arrive first (dope load vs GeometryReader), so both paths call
    /// this and the flag flips only once it actually ran.
    private func attemptInitialFit() {
        guard !didInitialFit, workspace.loaded, hostSize != .zero else { return }
        didInitialFit = true
        fit()
    }

    @ViewBuilder
    private var content: some View {
        if workspace.loaded {
            canvasHost
        } else {
            ProgressView("Loading dope scope…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - The viewport host

    private var canvasHost: some View {
        // Value snapshots read HERE, in the tracked body scope (renderer
        // closures and gesture callbacks are not tracked): the frozen
        // resolved during a drag, the live one otherwise.
        let resolved = viewState.dragDraft?.frozen ?? workspace.resolved
        let viewport = viewState.viewport

        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The screen owns its background (DiagramSceneView paints
                // none) — live appearance, not the baked screenshot color.
                Color(nsColor: .textBackgroundColor).ignoresSafeArea()
                DiagramSceneView(resolved: resolved, offset: sceneOffset(viewport)) {
                    EmptyView()
                } overlay: {
                    DiagramDraftOverlay(dragDraft: viewState.dragDraft,
                                        drawDraft: viewState.drawDraft,
                                        offset: sceneOffset(viewport))
                }
                .environment(\.diagramSelection, effectiveSelection)
                .scaleEffect(viewport.zoom, anchor: .topLeading)
            }
            .contentShape(Rectangle())
            .background { DiagramScrollBridge(sink: sink) }
            .gesture(canvasGesture)
            // simultaneous, not .gesture: a pan in flight must never block a pinch.
            .simultaneousGesture(magnify)
            .onAppear {
                hostSize = proxy.size
                attemptInitialFit()
                sink.onPan = { delta in
                    viewState.viewport.offset.width += delta.width
                    viewState.viewport.offset.height += delta.height
                }
                sink.onZoom = { factor, anchor in
                    viewState.viewport.zoom(
                        to: viewState.viewport.zoom * factor, anchor: anchor)
                }
            }
            .onChange(of: proxy.size) { _, newSize in hostSize = newSize }
        }
        .clipped()
    }

    /// Pan expressed in DIAGRAM space for the kit's offset parameter:
    /// (diagram + offset/zoom)·zoom = diagram·zoom + offset == toScreen.
    private func sceneOffset(_ viewport: DiagramViewport) -> CGSize {
        CGSize(width: viewport.offset.width / viewport.zoom,
               height: viewport.offset.height / viewport.zoom)
    }

    /// The dragged card dims in place while its ghost tracks the cursor.
    private var effectiveSelection: DiagramSelectionState {
        var selection = viewState.selection
        if let draft = viewState.dragDraft {
            selection.dimmedElementUuids.insert(draft.elementUuid)
        }
        return selection
    }

    // MARK: - Gestures (the five ported disciplines)

    private var canvasGesture: some Gesture {
        // minimumDistance MUST be 0: the default (10) silently kills
        // click-to-select.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A different startLocation means a NEW drag: reset whatever a
                // CANCELLED predecessor left behind (its onEnded never ran) —
                // including its staged mutations on the edit session.
                if dragStartLocation != value.startLocation {
                    resetDrafts(discardStaged: true)
                    dragStartLocation = value.startLocation
                }
                // Convert AT CAPTURE: a trackpad pan mid-drag changes the
                // viewport; diagram-space points stay welded to the diagram.
                let p = viewState.viewport.canvasPoint(value.location)
                let intent = dragIntent ?? begin(at: p)
                switch intent {
                case .move(let uuid, let node, let grab):
                    let delta = CGSize(width: p.x - grab.x, height: p.y - grab.y)
                    if viewState.dragDraft == nil {
                        guard let element = workspace.resolved.element(uuid: uuid) else { break }
                        viewState.dragDraft = DiagramViewState.DragDraft(
                            elementUuid: uuid, frozen: workspace.resolved,
                            frame: element.frame)
                    }
                    viewState.dragDraft?.delta = delta
                    // Restage ONE coalesced elementUpdate per sample — the
                    // divisor arithmetic lives in the kit.
                    if let element = viewState.dragDraft.flatMap({
                        $0.frozen.element(uuid: uuid) }) {
                        workspace.editSession.restage(DiagramDrag.moveMutation(
                            node: node, resolved: element, by: delta))
                    }
                case .draw(let tool, let anchor):
                    viewState.drawDraft = DiagramViewState.DrawDraft(
                        tool: tool, anchor: anchor, current: p)
                case .pan:
                    viewState.viewport.offset.width += value.translation.width - lastPan.width
                    viewState.viewport.offset.height += value.translation.height - lastPan.height
                    lastPan = value.translation
                }
            }
            .onEnded { _ in
                switch dragIntent {
                case .move:
                    // Flush + ONE re-resolve (inside the commit callback);
                    // clear the freeze only after the new resolved lands.
                    Task {
                        try? await workspace.editSession.flush()
                        viewState.dragDraft = nil
                    }
                case .draw(let tool, let anchor):
                    if let draft = viewState.drawDraft {
                        commitShape(tool: tool, from: anchor, to: draft.current)
                    }
                case .pan, nil:
                    break
                }
                resetDrafts(discardStaged: false)
            }
    }

    private func resetDrafts(discardStaged: Bool) {
        if discardStaged {
            // Stale staged mutations from a cancelled drag must never ride
            // into the next flush.
            workspace.editSession.discard()
            viewState.dragDraft = nil
        }
        viewState.drawDraft = nil
        dragIntent = nil
        lastPan = .zero
    }

    private func begin(at p: CGPoint) -> DragIntent {
        let intent: DragIntent
        switch viewState.tool {
        case .rect:
            intent = .draw(tool: .rect, anchor: p)
        case .line:
            intent = .draw(tool: .line, anchor: p)
        case .select:
            // Tolerance constant in SCREEN points at any zoom.
            let hit = workspace.resolved.hitTest(
                at: p, edgeTolerance: 6 / viewState.viewport.zoom)
            switch hit {
            case .element(let element):
                switch element.kind {
                case .entityCard, .absentEntity:
                    if let node = workspace.node(uuid: element.uuid) {
                        select(element.uuid)
                        intent = .move(uuid: element.uuid, node: node, grab: p)
                    } else {
                        intent = .pan
                    }
                case .scopeCard, .absentScope, .layer, .stroke, .shape:
                    clearSelection()
                    intent = .pan
                }
            case .edge, nil:
                clearSelection()
                intent = .pan
            }
        }
        dragIntent = intent
        return intent
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // value.magnification is CUMULATIVE from gesture start:
                // multiply the gesture-start baseline, never compound.
                let base: CGFloat
                if let zoomBase {
                    base = zoomBase
                } else {
                    base = viewState.viewport.zoom
                    zoomBase = base
                }
                viewState.viewport.zoom(to: base * value.magnification,
                                        anchor: value.startLocation)
            }
            .onEnded { _ in zoomBase = nil }
    }

    // MARK: - Selection / centering

    private func select(_ uuid: String) {
        viewState.selection = DiagramSelectionState(
            selectedElementUuid: uuid, highlightedElementUuids: [uuid])
    }

    private func clearSelection() {
        viewState.selection = DiagramSelectionState()
    }

    /// Center a diagram-space point (search jump / selection).
    private func center(on point: CGPoint) {
        guard hostSize != .zero else { return }
        withAnimation(.snappy(duration: 0.2)) {
            viewState.viewport.center(on: point, in: hostSize)
        }
    }

    /// Fit the whole content into the host.
    private func fit() {
        let bounds = workspace.resolved.contentBounds.insetBy(dx: -48, dy: -48)
        guard hostSize != .zero, bounds.width > 0, bounds.height > 0 else { return }
        let zoom = min(min(hostSize.width / bounds.width,
                           hostSize.height / bounds.height), 1)
        viewState.viewport.zoom = max(zoom, DiagramViewport.zoomRange.lowerBound)
        viewState.viewport.center(
            on: CGPoint(x: bounds.midX, y: bounds.midY), in: hostSize)
    }

    // MARK: - Draw mode

    /// Commit a rect/line: ONE batch that lazily creates the top-level
    /// drawing_layer (high sibling z) via clientRef + parentClientRef when it
    /// doesn't exist yet — layer and first shape land atomically, exactly
    /// what in-batch parenting exists for.
    private func commitShape(tool: DiagramTool, from anchor: CGPoint, to end: CGPoint) {
        let width = abs(end.x - anchor.x), height = abs(end.y - anchor.y)
        guard width >= 1 || height >= 1 else { return }
        let center = CGPoint(x: (anchor.x + end.x) / 2, y: (anchor.y + end.y) / 2)
        // Vertices are ELEMENT-LOCAL relative to the shape's center.
        let a = DiagramVertex(x: anchor.x - center.x, y: anchor.y - center.y)
        let b = DiagramVertex(x: end.x - center.x, y: end.y - center.y)
        let payload = DrawingShapePayload(
            shapeKind: tool == .rect ? .rectangle : .line,
            strokeColor: "#e67326", strokeWidth: 2, vertices: [a, b])

        let session = workspace.editSession!
        if let layer = workspace.drawingLayer {
            session.stage(.elementAdd(DiagramElementAdd(
                parentElementUuid: layer.identity.uuid,
                centerX: center.x, centerY: center.y,
                payload: .drawingShape(payload))))
        } else {
            session.stage(.elementAdd(DiagramElementAdd(
                clientRef: "drawing_layer",
                elementZ: workspace.maxTopLevelZ + 10,
                payload: .drawingLayer(DrawingLayerPayload()))))
            session.stage(.elementAdd(DiagramElementAdd(
                parentClientRef: "drawing_layer",
                centerX: center.x, centerY: center.y,
                payload: .drawingShape(payload))))
        }
        Task { try? await session.flush() }
    }

    // MARK: - Organize

    private func organize() {
        let mutations = DiagramOrganizer.organize(workspace.resolved,
                                                  tree: workspace.tree)
        guard !mutations.isEmpty else { return }
        let session = workspace.editSession!
        for mutation in mutations { session.stage(mutation) }
        Task { try? await session.flush() }
    }
}

/// The overlay slot's content: the drag ghost (dashed accent rect tracking
/// the cursor — a Canvas stroke, not a re-rendered card) and the in-progress
/// rect/line draft. Draws in DIAGRAM space at the scene's own offset, so it
/// inherits the outer `.scaleEffect` like every other layer.
private struct DiagramDraftOverlay: View {
    let dragDraft: DiagramViewState.DragDraft?
    let drawDraft: DiagramViewState.DrawDraft?
    let offset: CGSize

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: offset.width, y: offset.height)
            if let draft = dragDraft {
                let frame = draft.frame.offsetBy(dx: draft.delta.width,
                                                 dy: draft.delta.height)
                context.stroke(
                    Path(roundedRect: frame, cornerRadius: 6),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            if let draft = drawDraft {
                var path = Path()
                switch draft.tool {
                case .rect:
                    path.addRect(CGRect(
                        x: min(draft.anchor.x, draft.current.x),
                        y: min(draft.anchor.y, draft.current.y),
                        width: abs(draft.current.x - draft.anchor.x),
                        height: abs(draft.current.y - draft.anchor.y)))
                case .line, .select:
                    path.move(to: draft.anchor)
                    path.addLine(to: draft.current)
                }
                // Brand orange (RGBAColor.brandOrange) — matches the #e67326
                // the committed shape payload carries.
                context.stroke(path,
                               with: .color(Color(red: 0.9, green: 0.45, blue: 0.15)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
