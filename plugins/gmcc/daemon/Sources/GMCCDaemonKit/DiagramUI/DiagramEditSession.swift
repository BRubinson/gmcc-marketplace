import Foundation

/// The SERVICES half of the component library: GMVibes (or any host)
/// implements `DiagramCommitting` over its vendored DaemonClient and hands
/// it to a `DiagramEditSession`, which accumulates typed mutations during a
/// gesture and flushes them as ONE DIAGRAM_BATCH_APPLY at gesture end
/// (optionally CAS-guarded by the last-seen revision). The library never
/// instantiates a client — components consume values, hosts own transport.
public protocol DiagramCommitting: Sendable {
    /// Apply the mutations atomically; returns the new diagram revision.
    func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64
}

#if canImport(Observation)
import Observation

/// Window-lived staging store for interactive editing: stage mutations
/// per-frame (cheap value appends), flush once at gesture end. Absorbing
/// per-frame updates here — never as daemon round trips — is what keeps the
/// single-writer daemon and the revision counter meaningful.
@Observable
public final class DiagramEditSession {
    public private(set) var staged: [DiagramMutation] = []
    /// The revision the working state was built from; used as the CAS gate
    /// on flush and advanced by every successful commit.
    public private(set) var baseRevision: Int64?
    public private(set) var lastError: String?

    private let committer: any DiagramCommitting

    public init(committer: any DiagramCommitting, baseRevision: Int64? = nil) {
        self.committer = committer
        self.baseRevision = baseRevision
    }

    public func stage(_ mutation: DiagramMutation) {
        staged.append(mutation)
    }

    /// Replace the last staged mutation (per-frame geometry updates collapse
    /// into one mutation per touched element instead of one per frame).
    public func restage(_ mutation: DiagramMutation) {
        if staged.isEmpty {
            staged.append(mutation)
        } else {
            staged[staged.count - 1] = mutation
        }
    }

    public func discard() {
        staged.removeAll()
    }

    /// Gesture-end commit: everything staged, one transaction, one revision.
    @discardableResult
    public func flush(guarded: Bool = true) async throws -> Int64? {
        guard !staged.isEmpty else { return baseRevision }
        let mutations = staged
        do {
            let revision = try await committer.commit(
                mutations, expectedRevision: guarded ? baseRevision : nil)
            staged.removeAll()
            baseRevision = revision
            lastError = nil
            return revision
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }

    /// Re-anchor after an external refresh (e.g. a DIAGRAM_CHANGE event from
    /// another window prompted a refetch).
    public func rebase(revision: Int64) {
        baseRevision = revision
    }
}
#endif
