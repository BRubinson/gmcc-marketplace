import SwiftUI
import Observation
import GMCCDaemonKit

/// Window-lifetime diagram state, keyed by (session uuid, dope scope code) —
/// NOT session alone: DopePane ships a scope picker, so one session
/// legitimately has several dope scopes, and session-only keying would reuse
/// another scope's card positions as ghosts. Held as `@State` on
/// `GMVibesWindow` above the `.id(nav.route)` boundary and injected with
/// `.environment` — the exact seam `DrawingsStore` occupies — so the
/// unsaved, non-persisted diagram survives in-window navigation and dies
/// with the window. Deliberately NOT SessionScopeCache (its grace list would
/// resurrect a closed window's diagram).
@Observable @MainActor
final class DiagramWorkspaceStore {
    struct Key: Hashable {
        let sessionUuid: String
        let scopeCode: String
    }

    /// @ObservationIgnored makes create-or-get legal from a view body (the
    /// DrawingsStore rule): a TRACKED dictionary would register a read
    /// dependency and then write inside the same tracking scope. Each
    /// DiagramWorkspace is the real observable unit.
    @ObservationIgnored private var workspaces: [Key: DiagramWorkspace] = [:]

    /// Create-or-get, side-effect-safe from a view body.
    func workspace(for key: Key) -> DiagramWorkspace {
        if let existing = workspaces[key] { return existing }
        let fresh = DiagramWorkspace(sessionUuid: key.sessionUuid, scopeCode: key.scopeCode)
        workspaces[key] = fresh
        return fresh
    }
}

/// The MODEL half of the diagram screen (the view-state half is
/// `DiagramViewState`). The split is the freeze-during-drag guarantee made
/// structural: `resolved` is a STORED property whose only writers are
/// `applyCommit` / `rebuild` / `reskin` — a drag sample writes only view
/// state, so per-property observation makes a per-sample re-resolve (and the
/// A* pass inside it) impossible rather than merely forbidden.
@Observable @MainActor
final class DiagramWorkspace {
    let sessionUuid: String
    let scopeCode: String

    private(set) var tree: DiagramTree
    private(set) var resolved: ResolvedDiagram
    /// Bumped once per commit — the cheap "content changed" signal.
    private(set) var generation = 0
    private(set) var loaded = false

    /// The single write funnel (kit type, verbatim): stage/restage during a
    /// gesture, one flush at gesture end, through the LocalDiagramCommitter.
    private(set) var editSession: DiagramEditSession!
    private var box: DiagramTreeBox!

    /// The dope tree the diagram is scaffolded from (search runs over this).
    private(set) var dope: DopeGetResponse?
    /// Multi-pill domain filter: empty = all domains shown. Rebuild-the-tree
    /// semantics (the locked user decision) — filtering re-scaffolds and
    /// re-resolves; `codeCenters` carries positions across rebuilds and dope
    /// reloads.
    private(set) var domainFilter: Set<String> = []
    /// entity code -> last known diagram-space center (the carryover map).
    @ObservationIgnored private var codeCenters: [String: CGPoint] = [:]

    private var colorScheme: DiagramRenderEnvironment.ColorScheme = .light

    init(sessionUuid: String, scopeCode: String) {
        self.sessionUuid = sessionUuid
        self.scopeCode = scopeCode
        let empty = Self.emptyTree(sessionUuid: sessionUuid, code: scopeCode)
        self.tree = empty
        self.resolved = DiagramResolver.resolve(empty, dope: DiagramDopeContext())
        let box = DiagramTreeBox(tree: empty)
        self.box = box
        self.editSession = DiagramEditSession(
            committer: LocalDiagramCommitter(box: box) { [weak self] newTree in
                self?.applyCommit(newTree)
            },
            baseRevision: 0)
    }

    private static func emptyTree(sessionUuid: String, code: String) -> DiagramTree {
        let now = ISO8601DateFormatter().string(from: Date())
        return DiagramTree(
            identity: DopeNodeIdentity(uuid: UUID().uuidString.lowercased(), version: 0,
                                       createdAt: now, updatedAt: now),
            tier: "SESSION", projectUuid: "", instanceUuid: nil,
            sessionUuid: sessionUuid, promptUuid: nil,
            code: code, name: code, description: "",
            gmccDiagramPath: nil, revision: 0, elements: [])
    }

    private var environment: DiagramRenderEnvironment {
        DiagramRenderEnvironment(colorScheme: colorScheme)
    }

    private var dopeContext: DiagramDopeContext {
        guard let dope else { return DiagramDopeContext() }
        return DiagramDopeContext(entries: [
            dope.tree.body.code: DiagramDopeContext.Entry(
                tree: dope.tree, resolvedVia: dope.resolvedVia),
        ])
    }

    // MARK: - Scaffold / rebuild

    /// First load (or dope reload): scaffold the transient tree from the
    /// loaded dope response through `DopeCanvasLayout` (the CLI generator's
    /// own layout — heights from the resolver, so the app and the daemon can
    /// never lay out differently) applied via the parity-tested reducer.
    /// Re-entrant safe: an already-loaded workspace keeps its geometry via
    /// the code→center carryover.
    func load(_ response: DopeGetResponse, scheme: ColorScheme) {
        self.dope = response
        self.colorScheme = scheme == .dark ? .dark : .light
        rebuildTree()
        loaded = true
    }

    /// Multi-pill filter change: rebuild the synthetic tree dropping
    /// unselected domains' entities, re-resolve, carry positions over.
    func setDomainFilter(_ domains: Set<String>) {
        guard domains != domainFilter else { return }
        domainFilter = domains
        rebuildTree()
    }

    private func rebuildTree() {
        guard let dope else { return }
        // A rebuild re-mints every dope element's uuid — anything staged
        // against the old tree (a drag mid-flight when a pill toggles or a
        // dope event lands) is poison and must be dropped BEFORE the swap.
        editSession.discard()
        rememberCenters()
        let filtered = filteredDopeTree(dope.tree)
        var mutations = DopeCanvasLayout.mutations(for: filtered)
        // Carryover: a card whose entity code was placed before keeps its
        // center across filters and reloads.
        mutations = mutations.map { mutation in
            guard case .elementAdd(let add) = mutation,
                  case .dopeEntity(let payload) = add.payload,
                  let center = codeCenters[payload.entityCode] else { return mutation }
            return .elementAdd(DiagramElementAdd(
                clientRef: add.clientRef, parentElementUuid: add.parentElementUuid,
                parentClientRef: add.parentClientRef, code: add.code, name: add.name,
                description: add.description, sortOrder: add.sortOrder,
                centerX: center.x, centerY: center.y,
                elementZ: add.elementZ, scale: add.scale, payload: add.payload))
        }
        let fresh = Self.emptyTree(sessionUuid: sessionUuid, code: scopeCode)
        do {
            let scaffolded = try DiagramTreeReducer.apply(
                mutations, to: fresh, expectedRevision: nil, minting: LiveDiagramMinting())
            // The user's drawn layers are NOT dope-derived — re-attach them
            // (identities intact) so pill toggles and dope reloads never
            // delete drawings.
            let preservedLayers = tree.elements.filter { node in
                if case .drawingLayer = node.payload { return true }
                return false
            }
            let newTree = DiagramTree(
                identity: scaffolded.identity, tier: scaffolded.tier,
                projectUuid: scaffolded.projectUuid,
                instanceUuid: scaffolded.instanceUuid,
                sessionUuid: scaffolded.sessionUuid,
                promptUuid: scaffolded.promptUuid,
                code: scaffolded.code, name: scaffolded.name,
                description: scaffolded.description,
                gmccDiagramPath: scaffolded.gmccDiagramPath,
                revision: scaffolded.revision,
                elements: scaffolded.elements + preservedLayers)
            adoptRebuilt(newTree)
        } catch {
            // A scaffold failure leaves the last good tree in place; the
            // reducer is parity-tested, so this is a should-never path.
            assertionFailure("diagram scaffold failed: \(error)")
        }
    }

    /// Drop unselected domains' entities (empty filter = everything).
    private func filteredDopeTree(_ tree: DopeScopeTree) -> DopeScopeTree {
        guard !domainFilter.isEmpty else { return tree }
        let domains = tree.domains.map { domain in
            domainFilter.contains(domain.body.code)
                ? domain
                : DopePersistenceNode(identity: domain.identity, body: domain.body,
                                 entities: [], enums: domain.enums)
        }
        return DopeScopeTree(identity: tree.identity, body: tree.body,
                             sessionUuid: tree.sessionUuid, promptUuid: tree.promptUuid,
                             scopeType: tree.scopeType, revision: tree.revision,
                             domains: domains)
    }

    /// Record every entity card's current authored center by entity code.
    private func rememberCenters() {
        for element in tree.elements {
            guard case .dopeScope = element.payload else { continue }
            for child in element.children {
                if case .dopeEntity(let payload) = child.payload {
                    codeCenters[payload.entityCode] =
                        CGPoint(x: child.base.centerX, y: child.base.centerY)
                }
            }
        }
    }

    // MARK: - Commit / appearance

    /// Commit path: the box ALREADY holds `newTree` (it applied the batch),
    /// so no replace — a detached replace here raced the rebase and produced
    /// spurious revision conflicts.
    private func applyCommit(_ newTree: DiagramTree) {
        finishAdopt(newTree)
    }

    /// Rebuild path: the new tree was built OUTSIDE the box, so the box must
    /// be authoritative BEFORE the session rebases onto the new revision —
    /// strictly ordered inside one task, never detached.
    private func adoptRebuilt(_ newTree: DiagramTree) {
        Task {
            await box.replace(newTree)
            finishAdopt(newTree)
        }
    }

    private func finishAdopt(_ newTree: DiagramTree) {
        tree = newTree
        editSession.rebase(revision: newTree.revision)
        resolved = DiagramResolver.resolve(newTree, dope: dopeContext,
                                           environment: environment)
        generation += 1
        rememberCenters()
    }

    /// O(1) appearance flip — the resolver never reads colorScheme, so a
    /// scheme swap needs no re-resolve (and no A* re-run).
    func reskin(_ scheme: ColorScheme) {
        let target: DiagramRenderEnvironment.ColorScheme = scheme == .dark ? .dark : .light
        guard target != colorScheme else { return }
        colorScheme = target
        resolved = resolved.reskinned(target)
    }

    // MARK: - Lookups

    /// The lazily-created top-level drawing layer, if one exists yet.
    var drawingLayer: DiagramElementNode? {
        tree.elements.first { node in
            if case .drawingLayer = node.payload { return true }
            return false
        }
    }

    func node(uuid: String) -> DiagramElementNode? {
        DiagramTreeReducer.findNode(uuid, in: tree.elements)
    }

    /// The highest top-level elementZ (the new drawing layer must paint
    /// above the scope).
    var maxTopLevelZ: Double {
        tree.elements.map(\.base.elementZ).max() ?? 0
    }
}

/// Diagram tools. `select` is the only tool that can yield a `.move` intent —
/// draw tools structurally disable node drag (the locked decision); trackpad
/// pan keeps flowing through the scroll bridge in every tool.
enum DiagramTool: String, CaseIterable, Identifiable, Hashable {
    case select, rect, line

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .rect: "rectangle"
        case .line: "line.diagonal"
        }
    }
    var help: String {
        switch self {
        case .select: "Click to select, drag to move a card — drag empty space to pan"
        case .rect: "Drag out a rectangle on the drawing layer"
        case .line: "Drag a line on the drawing layer"
        }
    }
}

/// The VIEW-STATE half: everything a gesture sample may touch. Writing here
/// can never re-resolve — `DiagramWorkspace.resolved` is not reachable from
/// these code paths.
@Observable @MainActor
final class DiagramViewState {
    var viewport = DiagramViewport()
    var tool: DiagramTool = .select
    var selection = DiagramSelectionState()
    var searchText = ""

    /// Freeze-during-drag: set at the first `.move` sample, cleared after the
    /// gesture-end flush lands. The scene renders `frozen` while non-nil.
    struct DragDraft {
        let elementUuid: String
        let frozen: ResolvedDiagram
        let frame: CGRect
        var delta: CGSize = .zero
    }
    var dragDraft: DragDraft?

    /// In-progress rect/line draft, diagram space.
    struct DrawDraft {
        let tool: DiagramTool
        let anchor: CGPoint
        var current: CGPoint
    }
    var drawDraft: DrawDraft?
}
