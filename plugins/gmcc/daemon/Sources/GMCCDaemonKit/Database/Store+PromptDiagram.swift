import Foundation
import GRDB

// PROMPT_DIAGRAM_QUALIFY / _GET / _LIST — a prompt's standing reading of a
// rendered diagram (m0022). No status machine and no findings: the row IS the
// report, and the newest reading is the only one worth keeping.

extension Store {
    public func promptDiagramQualify(
        _ req: PromptDiagramQualifyRequest
    ) throws -> PromptQualifiedDiagramRow {
        let qualification = req.qualification.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qualification.isEmpty else {
            throw StoreError.badRequest(detail: "qualification is empty")
        }
        guard !req.renderedPath.isEmpty else {
            throw StoreError.badRequest(detail: "rendered_path is empty")
        }
        // Opaque on the wire, but not unexamined: a fingerprint that is not a
        // JSON object cannot be compared against a render sidecar later, and
        // discovering that at read time would make the row silently useless.
        guard let fingerprintData = req.renderFingerprint.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: fingerprintData)) is [String: Any] else {
            throw StoreError.badRequest(
                detail: "render_fingerprint must be a JSON object (the render sidecar's contents)")
        }

        return try dbQueue.write { db in
            try self.requireQualificationTargets(
                db, promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)

            let extra: [String: (any DatabaseValueConvertible)?] = [
                "prompt_uuid": req.promptUuid,
                "diagram_uuid": req.diagramUuid,
                "rendered_path": req.renderedPath,
                "rendered_revision": req.renderedRevision,
                "render_fingerprint": req.renderFingerprint,
                "qualification": qualification,
            ]
            let uuid: String
            // UNIQUE(prompt_uuid, diagram_uuid): re-qualifying REPLACES the
            // reading in place, keeping the row uuid stable so anything
            // pointing at it still points at it.
            if let existing = try String.fetchOne(
                db,
                sql: """
                    SELECT uuid FROM prompt_qualified_diagram
                    WHERE prompt_uuid = ? AND diagram_uuid = ?
                    """,
                arguments: [req.promptUuid, req.diagramUuid]
            ) {
                try db.execute(
                    sql: """
                        UPDATE prompt_qualified_diagram
                        SET rendered_path = ?, rendered_revision = ?,
                            render_fingerprint = ?, qualification = ?,
                            version = version + 1, updated_at = ?
                        WHERE uuid = ?
                        """,
                    arguments: [req.renderedPath, req.renderedRevision,
                                req.renderFingerprint, qualification,
                                Store.isoNow(), existing])
                uuid = existing
            } else {
                uuid = try self.insertBase(
                    db, table: "prompt_qualified_diagram", extra: extra)
            }

            try self.appendEvent(
                db, kind: .promptDiagramQualified, subjectUuid: uuid,
                payload: Store.jsonPayload([
                    "prompt_uuid": req.promptUuid,
                    "diagram_uuid": req.diagramUuid,
                ]))

            guard let row = try self.fetchQualifiedDiagramRow(db, uuid: uuid) else {
                throw StoreError.notFound(entity: "prompt_qualified_diagram", key: uuid)
            }
            return row
        }
    }

    public func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try dbQueue.read { db in
            try self.requireQualificationTargets(
                db, promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)

            let rows = try self.fetchQualifiedDiagramRows(
                db, promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)
            guard let first = rows.first else {
                // The prompt is real and nothing is recorded against it — the
                // caller's next move is to render, read and qualify, not to
                // doubt the uuid. Same discrimination the summary families make.
                throw StoreError.summaryAbsent(
                    entity: "prompt_qualified_diagram", promptUuid: req.promptUuid)
            }
            guard rows.count == 1 else {
                throw StoreError.badRequest(
                    detail: "prompt has \(rows.count) qualified diagrams — "
                          + "name one with a diagram uuid, or list them")
            }
            return first
        }
    }

    public func promptDiagramList(
        _ req: PromptDiagramListRequest
    ) throws -> PromptDiagramListResponse {
        try dbQueue.read { db in
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
            }
            // Empty is a normal answer here (the prompt has attached no
            // diagrams yet), so list never raises where get would.
            return PromptDiagramListResponse(
                qualifications: try self.fetchQualifiedDiagramRows(
                    db, promptUuid: req.promptUuid, diagramUuid: nil))
        }
    }

    // MARK: - Shared helpers

    /// Existence first, in the same transaction as the write. Without it an
    /// unknown uuid surfaces as a raw FK failure, which tells the caller
    /// nothing about WHICH end was wrong.
    private func requireQualificationTargets(
        _ db: Database, promptUuid: String, diagramUuid: String?
    ) throws {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        guard let diagramUuid else { return }
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM diagram WHERE uuid = ?", arguments: [diagramUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "diagram", key: diagramUuid)
        }
    }

    func fetchQualifiedDiagramRow(
        _ db: Database, uuid: String
    ) throws -> PromptQualifiedDiagramRow? {
        try Row.fetchOne(
            db,
            sql: "\(Store.qualifiedDiagramSelect) WHERE uuid = ?",
            arguments: [uuid]
        ).map(Store.qualifiedDiagramRow)
    }

    func fetchQualifiedDiagramRows(
        _ db: Database, promptUuid: String, diagramUuid: String?
    ) throws -> [PromptQualifiedDiagramRow] {
        var sql = "\(Store.qualifiedDiagramSelect) WHERE prompt_uuid = ?"
        var arguments: [any DatabaseValueConvertible] = [promptUuid]
        if let diagramUuid {
            sql += " AND diagram_uuid = ?"
            arguments.append(diagramUuid)
        }
        sql += " ORDER BY created_at, id"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map(Store.qualifiedDiagramRow)
    }

    private static let qualifiedDiagramSelect = """
        SELECT uuid, prompt_uuid, diagram_uuid, rendered_path, rendered_revision,
               render_fingerprint, qualification, version, created_at, updated_at, id
        FROM prompt_qualified_diagram
        """

    private static func qualifiedDiagramRow(_ row: Row) -> PromptQualifiedDiagramRow {
        PromptQualifiedDiagramRow(
            uuid: row["uuid"],
            promptUuid: row["prompt_uuid"],
            diagramUuid: row["diagram_uuid"],
            renderedPath: row["rendered_path"],
            renderedRevision: row["rendered_revision"],
            renderFingerprint: row["render_fingerprint"],
            qualification: row["qualification"],
            version: row["version"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
