import Foundation
import GRDB

/// ARCH_* data access — the db-native architecture machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct ArchitectureRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent; called by ARCH_OPEN and by setPromptStatus's
    /// clarifying → architecting create-on-enter (suppressed for legacy).
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM architecture_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "architecture_summary", extra: [
            "prompt_uuid": promptUuid,
            "body": "",
            "status": ArchitectureStatus.drafting.rawValue,
        ])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid]))
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: uuid)
        }
        return ArchSummaryResponse(summary: summary, created: created)
    }

    func summarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "summarize")
        try core.updateBase(
            db, table: "architecture_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion, set: ["body": req.body])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "summarize", "prompt_uuid": summary.promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: req.summaryUuid)
        }
        return ArchSummaryResponse(summary: updated)
    }

    func persistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "persist-add")
        let path = try Store.normalizeRepoRelativePath(
            req.filePath, repoRoot: try instanceRoot(promptUuid: summary.promptUuid))
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM architecture_persistence_change WHERE architecture_summary_uuid = ?",
            arguments: [req.summaryUuid]) ?? 0) + 1
        let uuid = try core.insertBase(db, table: "architecture_persistence_change", extra: [
            "architecture_summary_uuid": req.summaryUuid,
            "seq": seq,
            "class_name": req.className,
            "file_path": path,
            "reason_brief": req.reasonBrief,
        ])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "persist_add", "seq": seq, "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ]))
        let touched = try touchedPaths(promptUuid: summary.promptUuid)
        guard let change = try fetchPersistenceChanges(
            summaryUuid: req.summaryUuid, touched: touched
        ).first(where: { $0.uuid == uuid }) else {
            throw StoreError.notFound(entity: "architecture_persistence_change", key: uuid)
        }
        return ArchPersistAddResponse(change: change)
    }

    func fieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        guard let parent = try Row.fetchOne(
            db,
            sql: "SELECT architecture_summary_uuid FROM architecture_persistence_change WHERE uuid = ?",
            arguments: [req.persistenceChangeUuid]
        ) else {
            throw StoreError.notFound(entity: "architecture_persistence_change", key: req.persistenceChangeUuid)
        }
        let summaryUuid: String = parent["architecture_summary_uuid"]
        let summary = try requireSummary(uuid: summaryUuid, at: .drafting, verb: "field-add")
        if req.isForeignKey, (req.fkTarget ?? "").isEmpty {
            throw StoreError.badRequest(detail: "--fk-target is required with --foreign-key")
        }
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM architecture_persistence_field_change WHERE persistence_change_uuid = ?",
            arguments: [req.persistenceChangeUuid]) ?? 0) + 1
        let uuid = try core.insertBase(db, table: "architecture_persistence_field_change", extra: [
            "persistence_change_uuid": req.persistenceChangeUuid,
            "seq": seq,
            "field_name": req.fieldName,
            "change_reason": req.changeReason,
            "change_purpose": req.changePurpose,
            "data_type": req.dataType,
            "nullable": req.nullable ? 1 : 0,
            "is_foreign_key": req.isForeignKey ? 1 : 0,
            "fk_target": req.isForeignKey ? req.fkTarget : nil,
            "is_indexed": req.isIndexed ? 1 : 0,
        ])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": "field_add", "persistence_change_uuid": req.persistenceChangeUuid,
                "field_name": req.fieldName,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let field = try fetchFieldChanges(changeUuid: req.persistenceChangeUuid)
            .first(where: { $0.uuid == uuid }) else {
            throw StoreError.notFound(entity: "architecture_persistence_field_change", key: uuid)
        }
        return ArchFieldAddResponse(field: field)
    }

    func generalAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "general-add")
        guard req.changeCode.utf8.count <= Store.maxChangeCodeBytes else {
            throw StoreError.badRequest(
                detail: "change_code exceeds \(Store.maxChangeCodeBytes / (1024 * 1024)) MB")
        }
        let path = try Store.normalizeRepoRelativePath(
            req.filePath, repoRoot: try instanceRoot(promptUuid: summary.promptUuid))
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM architecture_general_change WHERE architecture_summary_uuid = ?",
            arguments: [req.summaryUuid]) ?? 0) + 1
        let uuid = try core.insertBase(db, table: "architecture_general_change", extra: [
            "architecture_summary_uuid": req.summaryUuid,
            "seq": seq,
            "file_path": path,
            "class_name": req.className,
            "reason_brief": req.reasonBrief,
            "change_depth": req.changeDepth.rawValue,
            "change_code": req.changeCode,
        ])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "general_add", "seq": seq, "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ]))
        let touched = try touchedPaths(promptUuid: summary.promptUuid)
        guard let change = try fetchGeneralChanges(
            summaryUuid: req.summaryUuid, touched: touched
        ).first(where: { $0.uuid == uuid }) else {
            throw StoreError.notFound(entity: "architecture_general_change", key: uuid)
        }
        return ArchGeneralAddResponse(change: change)
    }

    func get(_ req: ArchGetRequest) throws -> ArchGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            // A6: prompt exists — discriminated SUMMARY_ABSENT (gm arch open).
            throw StoreError.summaryAbsent(
                entity: "architecture", promptUuid: req.promptUuid)
        }
        let touched = try touchedPaths(promptUuid: req.promptUuid)
        let persistence = try fetchPersistenceChanges(summaryUuid: summary.uuid, touched: touched)
        let general = try fetchGeneralChanges(summaryUuid: summary.uuid, touched: touched)

        // Scope drift: this prompt's touched paths absent from the plan.
        let plannedPaths = Set(persistence.map(\.filePath) + general.map(\.filePath))
        let unplanned = touched.values
            .filter { !plannedPaths.contains($0.path) }
            .sorted { $0.path < $1.path }

        // Persistence-first audit: every persistence path's first touch
        // must precede every general path's first touch. Vacuously nil
        // when either side is empty or untouched.
        let persistenceFirsts = persistence.compactMap(\.implementation.firstChangedAt)
        let generalFirsts = general.compactMap(\.implementation.firstChangedAt)
        let orderingRespected: Bool?
        if let latestPersistence = persistenceFirsts.max(), let earliestGeneral = generalFirsts.min() {
            orderingRespected = latestPersistence <= earliestGeneral
        } else {
            orderingRespected = nil
        }
        return ArchGetResponse(
            summary: summary,
            persistenceChanges: persistence,
            generalChanges: general,
            unplannedChanges: unplanned,
            orderingRespected: orderingRespected
        )
    }

    // MARK: - Comparison support

    /// One aggregate query (mirrors changeSummary — never per-row): every
    /// distinct path this prompt's file changes touched, with count and
    /// first/last timestamps. Keyed by path for the decoration lookup.
    private func touchedPaths(
        promptUuid: String
    ) throws -> [String: UnplannedChangeRow] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT sf.relative_path AS path,
                   COUNT(DISTINCT fc.uuid) AS change_count,
                   MIN(fc.created_at) AS first_changed_at,
                   MAX(fc.created_at) AS last_changed_at
            FROM file_change fc
            JOIN session_file sf ON sf.uuid = fc.session_file_uuid
            WHERE fc.prompt_uuid = ?
            GROUP BY sf.relative_path
            """, arguments: [promptUuid])
        var byPath: [String: UnplannedChangeRow] = [:]
        for row in rows {
            let entry = UnplannedChangeRow(
                path: row["path"],
                changeCount: row["change_count"],
                firstChangedAt: row["first_changed_at"],
                lastChangedAt: row["last_changed_at"])
            byPath[entry.path] = entry
        }
        return byPath
    }

    private func implementationState(
        for path: String, touched: [String: UnplannedChangeRow]
    ) -> ChangeImplementationState {
        guard let entry = touched[path] else {
            return ChangeImplementationState(fileChangeCount: 0, firstChangedAt: nil, lastChangedAt: nil)
        }
        return ChangeImplementationState(
            fileChangeCount: entry.changeCount,
            firstChangedAt: entry.firstChangedAt,
            lastChangedAt: entry.lastChangedAt)
    }

    /// The arch change-add paths normalize against the instance root reached
    /// via prompt → session → instance (the add payloads carry no context
    /// blocks). Empty when the chain is broken — the normalizer then only
    /// applies its lexical rules.
    func instanceRoot(promptUuid: String) throws -> String {
        try String.fetchOne(db, sql: """
            SELECT i.absolute_file_system_path
            FROM prompt p
            JOIN session s ON s.uuid = p.session_uuid
            JOIN instance i ON i.uuid = s.instance_uuid
            WHERE p.uuid = ?
            """, arguments: [promptUuid]) ?? ""
    }

    // MARK: - Transition + fetch helpers

    private func requireSummary(
        uuid: String, at required: ArchitectureStatus, verb: String
    ) throws -> ArchitectureSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: uuid)
        }
        guard summary.architectureStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "architecture", from: summary.status, to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)")
        }
        return summary
    }

    func transition(
        summaryUuid: String,
        expectedVersion: Int64,
        to: ArchitectureStatus,
        action: String,
        requireFrom: ArchitectureStatus
    ) throws -> ArchSummaryResponse {
        guard let summary = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: summaryUuid)
        }
        guard let from = summary.architectureStatus else {
            throw StoreError.corruptState(entity: "architecture_summary", detail: "status '\(summary.status)'")
        }
        guard from == requireFrom, from.allowedNext.contains(to) else {
            throw StoreError.invalidEntityTransition(
                entity: "architecture", from: from.rawValue, to: to.rawValue,
                reason: "\(action) runs from \(requireFrom.rawValue) — this summary is \(from.rawValue)")
        }
        try core.updateBase(
            db, table: "architecture_summary", uuid: summaryUuid,
            expectedVersion: expectedVersion, set: ["status": to.rawValue])
        try core.appendEvent(
            db, kind: .architectureChange, subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": action, "from": from.rawValue, "to": to.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: summaryUuid)
        }
        return ArchSummaryResponse(summary: updated)
    }

    func fetchSummary(uuid: String) throws -> ArchitectureSummaryRow? {
        try fetchSummary(where: "uuid = ?", key: uuid)
    }

    func fetchSummary(byPrompt promptUuid: String) throws -> ArchitectureSummaryRow? {
        try fetchSummary(where: "prompt_uuid = ?", key: promptUuid)
    }

    private func fetchSummary(
        where condition: String, key: String
    ) throws -> ArchitectureSummaryRow? {
        try ArchitectureSummaryRecord.fetchAll(
            db, where: condition, arguments: [key]
        ).first?.wireRow()
    }

    private func fetchPersistenceChanges(
        summaryUuid: String, touched: [String: UnplannedChangeRow]
    ) throws -> [ArchPersistenceChangeRow] {
        try ArchitecturePersistenceChangeRecord.fetchAll(
            db, where: "architecture_summary_uuid = ?", arguments: [summaryUuid],
            orderBy: "seq"
        ).map { record in
            record.wireRow(
                fields: try fetchFieldChanges(changeUuid: record.uuid),
                implementation: implementationState(for: record.filePath, touched: touched))
        }
    }

    private func fetchFieldChanges(
        changeUuid: String
    ) throws -> [ArchPersistenceFieldChangeRow] {
        try ArchitecturePersistenceFieldChangeRecord.fetchAll(
            db, where: "persistence_change_uuid = ?", arguments: [changeUuid],
            orderBy: "seq"
        ).map { $0.wireRow() }
    }

    private func fetchGeneralChanges(
        summaryUuid: String, touched: [String: UnplannedChangeRow]
    ) throws -> [ArchGeneralChangeRow] {
        try ArchitectureGeneralChangeRecord.fetchAll(
            db, where: "architecture_summary_uuid = ?", arguments: [summaryUuid],
            orderBy: "seq"
        ).map { record in
            record.wireRow(
                implementation: implementationState(for: record.filePath, touched: touched))
        }
    }
}
