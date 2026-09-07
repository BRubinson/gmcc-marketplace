import Foundation
import GMCCDaemonKit

/// Real-uuid minting for the non-persisted tree. Uuids must be REAL (not a
/// "local-" scheme) so a later daemon replay of the same mutations is
/// accepted verbatim — the whole point of the one-committer-swap contract.
nonisolated struct LiveDiagramMinting: DiagramIdentityMinting {
    func mintUuid() -> String { UUID().uuidString.lowercased() }
    func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// The authoritative in-memory tree: a single-writer actor — the same shape
/// as the daemon it stands in for. All semantics live in the kit's
/// `DiagramTreeReducer` (the parity-tested second implementation of
/// `diagramBatchApply`); this box only serializes access.
actor DiagramTreeBox {
    private(set) var tree: DiagramTree

    init(tree: DiagramTree) {
        self.tree = tree
    }

    func apply(_ mutations: [DiagramMutation], expectedRevision: Int64?) throws -> DiagramTree {
        tree = try DiagramTreeReducer.apply(mutations, to: tree,
                                            expectedRevision: expectedRevision,
                                            minting: LiveDiagramMinting())
        return tree
    }

    /// Wholesale replacement (domain-pill rebuild / dope reload paths).
    func replace(_ newTree: DiagramTree) {
        tree = newTree
    }
}

/// The ~20-line `DiagramCommitting` conformer behind `DiagramEditSession`.
/// Persistence later is ONE swap: a DaemonCommitter wrapping
/// `diagramBatchApply` replaces this type and nothing else changes.
final class LocalDiagramCommitter: DiagramCommitting {
    let box: DiagramTreeBox
    private let onCommit: @MainActor @Sendable (DiagramTree) -> Void

    init(box: DiagramTreeBox, onCommit: @escaping @MainActor @Sendable (DiagramTree) -> Void) {
        self.box = box
        self.onCommit = onCommit
    }

    func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64 {
        let tree = try await box.apply(mutations, expectedRevision: expectedRevision)
        let notify = onCommit
        await MainActor.run { notify(tree) }
        return tree.revision
    }
}
