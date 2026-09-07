import Foundation
import GRDB

/// Reads and writes `dope_element_provenance` — the merge base.
///
/// Two writers, and they are deliberately the only two:
///   * `stampProvenanceFromFiles` runs after a files -> db sync and records
///     what each element looked like when it arrived, clearing the dirty
///     flag. This IS the base.
///   * `markLocallyModified` runs on a granular dope mutation and sets the
///     dirty flag for the affected dot-path.
///
/// Everything is addressed by dot-path, never uuid: ingest re-mints every
/// child uuid, so uuid-keyed provenance would be erased by the operation it
/// exists to inform.
extension Store {

    /// Load the stored base for one scope.
    func dopeProvenance(_ db: Database, scopeUuid: String) throws -> [String: DopeMerge.Base] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT dot_path, synced_content_hash, locally_modified
              FROM dope_element_provenance WHERE dope_scope_uuid = ?
            """, arguments: [scopeUuid])
        var out = [String: DopeMerge.Base]()
        for row in rows {
            out[row["dot_path"]] = DopeMerge.Base(
                syncedContentHash: row["synced_content_hash"],
                locallyModified: (row["locally_modified"] as Int64) == 1)
        }
        return out
    }

    /// Record the base after a files -> db sync: every element that came from
    /// a file gets its hash stored and its dirty flag cleared.
    ///
    /// Rows for paths no longer present are deleted, so provenance cannot
    /// outlive the tree it describes and resurrect a stale base later.
    func stampProvenanceFromFiles(
        _ db: Database, scopeUuid: String, bundle: DopeDocumentBundle
    ) throws {
        let elements = DopeMerge.elements(of: bundle)
        let now = Store.isoNow()
        let live = Set(elements.map(\.dotPath))

        for element in elements {
            try db.execute(sql: """
                INSERT INTO dope_element_provenance
                    (uuid, version, created_at, updated_at, dope_scope_uuid,
                     dot_path, element_kind, synced_content_hash, locally_modified)
                VALUES (?, 0, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                    element_kind = excluded.element_kind,
                    synced_content_hash = excluded.synced_content_hash,
                    locally_modified = 0,
                    updated_at = excluded.updated_at
                """, arguments: [UUID().uuidString.lowercased(), now, now, scopeUuid,
                                 element.dotPath, element.kind, element.contentHash])
        }

        let stale = try String.fetchAll(db, sql: """
            SELECT dot_path FROM dope_element_provenance WHERE dope_scope_uuid = ?
            """, arguments: [scopeUuid]).filter { !live.contains($0) }
        for path in stale {
            try db.execute(sql: """
                DELETE FROM dope_element_provenance
                 WHERE dope_scope_uuid = ? AND dot_path = ?
                """, arguments: [scopeUuid, path])
        }
    }

    /// Flag one dot-path as edited in this session.
    ///
    /// Upserts rather than requiring a prior row: an element created here has
    /// no base, and "dirty with no base" is a meaningful state the merge
    /// reads as a local addition (or, when the file also has it, as a
    /// conflict it refuses to guess about).
    func markLocallyModified(
        _ db: Database, scopeUuid: String, dotPath: String, kind: String
    ) throws {
        let now = Store.isoNow()
        try db.execute(sql: """
            INSERT INTO dope_element_provenance
                (uuid, version, created_at, updated_at, dope_scope_uuid,
                 dot_path, element_kind, synced_content_hash, locally_modified)
            VALUES (?, 0, ?, ?, ?, ?, ?, NULL, 1)
            ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                locally_modified = 1,
                updated_at = excluded.updated_at
            """, arguments: [UUID().uuidString.lowercased(), now, now, scopeUuid,
                             dotPath, kind])
    }

    /// Resolve a node's dot-path from its uuid, for the level it sits at.
    ///
    /// The merge is addressed by dot-path but the mutation verbs speak in
    /// uuids, so this is the join between them. Returns nil for a node that
    /// has already been deleted — a hard delete cascades, so by the time a
    /// delete is recorded the row may be gone; the caller marks what it can
    /// and a missing mark degrades to "not known to be dirty", which the
    /// merge treats as files-win rather than as a silent data loss.
    func dopeDotPath(_ db: Database, nodeUuid: String, level: DopeLevel) throws -> String? {
        switch level {
        case .scope:
            return nil  // the scope itself is not a merge element
        case .persistence:
            return try String.fetchOne(db, sql: """
                SELECT code FROM dope_persistence WHERE uuid = ?
                """, arguments: [nodeUuid])
        case .entity:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.' || e.code
                  FROM dope_persistence_entity e
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE e.uuid = ?
                """, arguments: [nodeUuid])
        case .property:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.' || e.code || '.' || p.code
                  FROM dope_persistence_entity_property p
                  JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE p.uuid = ?
                """, arguments: [nodeUuid])
        case .enumeration:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.enums.' || n.code
                  FROM dope_persistence_enum n
                  JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                 WHERE n.uuid = ?
                """, arguments: [nodeUuid])
        case .option:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.enums.' || n.code || '.' || o.code
                  FROM dope_persistence_enum_option o
                  JOIN dope_persistence_enum n ON n.uuid = o.dope_persistence_enum_uuid
                  JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                 WHERE o.uuid = ?
                """, arguments: [nodeUuid])
        }
    }

    /// The dot-paths this session has edited, in order.
    func locallyModifiedPaths(_ db: Database, scopeUuid: String) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT dot_path FROM dope_element_provenance
             WHERE dope_scope_uuid = ? AND locally_modified = 1
             ORDER BY dot_path
            """, arguments: [scopeUuid])
    }
}

// MARK: - Merge planning and resolution

extension Store {

    /// The current merge plan for a scope: db tree vs the on-disk tree,
    /// judged against the stored base.
    ///
    /// Read-only and non-blocking by construction — it never ingests, never
    /// writes files, and never mutates provenance. `gm dope sync` calls it to
    /// report rather than to decide, which is what keeps the documented
    /// "boot must never block on a domain model" contract true.
    public func dopeMergePlan(scopeUuid: String) throws -> [DopeMerge.Outcome] {
        let (scope, root) = try dbQueue.read { db -> (DopeScopeRow, String) in
            guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
            }
            try Store.requireRepoWritableScope(scope, verb: "merge")
            return (scope, try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid()))
        }

        let theirs: [DopeMerge.Element]
        do {
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            theirs = DopeMerge.elements(of: try sandbox.readBundle().bundle)
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        return try dbQueue.read { db in
            let tree = try self.fetchDopeTree(db, scope: scope, forProjection: true)
            let ours = DopeMerge.elements(of: DopeProjection.documents(from: tree))
            let base = try self.dopeProvenance(db, scopeUuid: scopeUuid)
            return DopeMerge.plan(ours: ours, theirs: theirs, base: base)
        }
    }

    /// Resolve one conflicting dot-path — or every one of them.
    ///
    /// Resolution is expressed IN the base rather than by rewriting a tree,
    /// which is what makes it a single small write instead of a second merge
    /// engine:
    ///
    ///   take theirs → clear the dirty flag, so the next sync takes the file
    ///                 exactly as an untouched element would;
    ///   take ours   → re-base onto the file's CURRENT hash while staying
    ///                 dirty, so the local edit is kept and the file is no
    ///                 longer considered to have moved.
    ///
    /// Either way the conflict is gone on the next plan, in the direction
    /// that was chosen.
    @discardableResult
    public func dopeResolve(
        scopeUuid: String, dotPath: String?, takeOurs: Bool
    ) throws -> [String] {
        let plan = try dopeMergePlan(scopeUuid: scopeUuid)
        let conflicts = DopeMerge.conflicts(in: plan)

        let targets: [DopeMerge.Outcome]
        if let dotPath {
            guard let match = conflicts.first(where: { $0.dotPath == dotPath }) else {
                throw StoreError.badRequest(
                    detail: conflicts.isEmpty
                        ? "no unresolved dope conflicts in scope \(scopeUuid)"
                        : "'\(dotPath)' is not a conflicting path; conflicts: "
                          + conflicts.map(\.dotPath).joined(separator: ", "))
            }
            targets = [match]
        } else {
            targets = conflicts
        }
        guard !targets.isEmpty else { return [] }

        // The file side's current hashes — what "ours wins" must re-base onto.
        let theirHashes = try dbQueue.read { db -> [String: String] in
            guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
            }
            let root = try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid())
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            var out = [String: String]()
            for element in DopeMerge.elements(of: try sandbox.readBundle().bundle) {
                out[element.dotPath] = element.contentHash
            }
            return out
        }

        try dbQueue.write { db in
            let now = Store.isoNow()
            for target in targets {
                if takeOurs {
                    try db.execute(sql: """
                        UPDATE dope_element_provenance
                           SET synced_content_hash = ?, locally_modified = 1, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """, arguments: [theirHashes[target.dotPath], now,
                                         scopeUuid, target.dotPath])
                } else {
                    try db.execute(sql: """
                        UPDATE dope_element_provenance
                           SET locally_modified = 0, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """, arguments: [now, scopeUuid, target.dotPath])
                }
            }
        }
        return targets.map(\.dotPath)
    }
}
