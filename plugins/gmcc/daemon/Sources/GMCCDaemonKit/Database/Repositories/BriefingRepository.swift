import Foundation
import GRDB

/// BRIEFING_* (v21) data access — the agent-briefing machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct BriefingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Verbs

    /// Reserve (or reset) the briefing row for one (owner, step) pair.
    /// Exactly one owner flag; session_uuid is ALWAYS stored (derived from
    /// the prompt's owner chain when prompt-owned) so the two columns can
    /// never disagree and task-owned rows share the same list key.
    func open(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        let step = try BriefingStepSpec.validateStep(req.briefingForStep)
        let sessionUuid: String
        let promptUuid: String?
        switch (req.promptUuid, req.sessionUuid) {
        case (let prompt?, nil):
            guard let owner = try String.fetchOne(
                db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?", arguments: [prompt]
            ) else {
                throw StoreError.notFound(entity: "prompt", key: prompt)
            }
            sessionUuid = owner
            promptUuid = prompt
        case (nil, let session?):
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [session]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: session)
            }
            sessionUuid = session
            promptUuid = nil
        default:
            throw StoreError.badRequest(
                detail: "briefing open takes exactly one owner: --prompt-uuid or --session-uuid")
        }

        // A prompt-owned open also claims the activation for the calling
        // instance (review finding 5f68f01d): briefings are consumed in
        // the draft/architecting phases, long before set-status
        // implementing would claim — and the claim is what makes every
        // downstream agent's zero-uuid pull deterministic.
        if let promptUuid, let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core).claimActivation(
                sessionUuid: sessionUuid,
                promptUuid: promptUuid, clientKey: clientKey)
        }

        if let existing = try fetchBriefingRow(
            ownerPrompt: promptUuid, ownerSession: sessionUuid, step: step
        ) {
            // Reset, never duplicate: content is kept for wholesale
            // replacement at complete (the reopen-preserves precedent).
            try core.updateBase(
                db, table: "agent_briefing", uuid: existing.uuid,
                expectedVersion: existing.version,
                set: ["status": "building"])
            try core.appendEvent(
                db, kind: .briefingChange, subjectUuid: existing.uuid,
                payload: Store.jsonPayload([
                    "action": "reset", "step": step,
                    "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
                ]))
            try core.touchSession(db, uuid: sessionUuid)
            guard let row = try fetchBriefing(uuid: existing.uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: existing.uuid)
            }
            return BriefingRowResponse(briefing: row, created: false)
        }

        let uuid = try core.insertBase(db, table: "agent_briefing", extra: [
            "session_uuid": sessionUuid,
            "prompt_uuid": promptUuid,
            "briefing_for_step": step,
            "status": "building",
            "body": "",
            "dope_refs": "[]",
            "kbite_refs": "[]",
        ])
        try core.appendEvent(
            db, kind: .briefingChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "open", "step": step,
                "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
            ]))
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchBriefing(uuid: uuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: uuid)
        }
        return BriefingRowResponse(briefing: row, created: true)
    }

    /// building → ready. The daemon stamps the staleness evidence ITSELF
    /// (the writing agent cannot mis-stamp) and denormalizes kbite briefs.
    func complete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        guard let existing = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }
        let body = try Store.validatedOverview(req.body, entity: "briefing")

        let dopeRefs = req.dopeRefs ?? []
        let dopeRefsJson = try Store.encodeJsonArray(dopeRefs)

        // {file_uuid, brief} denormalized from the kbite tables at write
        // time: point-in-time by design, ghost-tolerant by design — an
        // unknown file uuid rides along with a null brief (kbites can be
        // re-digested; refs must not break the write).
        var kbiteEntries: [[String: String?]] = []
        for fileUuid in req.kbiteRefs ?? [] {
            let brief = try String.fetchOne(
                db,
                sql: "SELECT resource_file_summary FROM kbite_resource_file WHERE uuid = ?",
                arguments: [fileUuid])
            kbiteEntries.append(["file_uuid": fileUuid, "brief": brief])
        }
        let kbiteRefsJson = try Store.encodeJsonObjectArray(kbiteEntries)

        // Server-side staleness stamp from the session's SESSION_INSTANCE
        // scope. No scope is a legal state (nil stamp, staleness unknown).
        let scope = try dope.dopeScopeCandidates(
            sessionUuid: existing.sessionUuid, scopeType: .sessionInstance
        ).first

        try core.updateBase(
            db, table: "agent_briefing", uuid: req.briefingUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": "ready",
                "body": body,
                "dope_refs": dopeRefsJson,
                "kbite_refs": kbiteRefsJson,
                "dope_scope_uuid": scope?.uuid,
                "dope_scope_revision": scope?.revision,
            ])
        try core.appendEvent(
            db, kind: .briefingChange, subjectUuid: req.briefingUuid,
            payload: Store.jsonPayload([
                "action": "complete", "step": existing.briefingForStep,
                "session_uuid": existing.sessionUuid,
                "prompt_uuid": existing.promptUuid,
                "dope_scope_revision": scope?.revision,
            ]))
        try core.touchSession(db, uuid: existing.sessionUuid)
        guard let row = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }
        return BriefingRowResponse(briefing: row)
    }

    func get(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        let row = try resolveSelector(req: req)
        let staleness = try computeStaleness(briefing: row)
        return BriefingGetResponse(briefing: row, staleness: staleness)
    }

    func list(_ req: BriefingListRequest) throws -> BriefingListResponse {
        let rows: [AgentBriefingRow]
        if let promptUuid = req.promptUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            rows = try fetchBriefings(where: "prompt_uuid = ?", arguments: [promptUuid])
        } else if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            rows = try fetchBriefings(where: "session_uuid = ?", arguments: [sessionUuid])
        } else {
            throw StoreError.badRequest(
                detail: "briefing list takes --prompt-uuid or --session-uuid")
        }
        return BriefingListResponse(briefings: rows)
    }

    /// The SubagentStart hook's one call. Empty stub + success when nothing
    /// applies — the hook must never wedge a spawn.
    func stub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        guard let sessionUuid = req.sessionUuid else {
            return BriefingStubResponse(stub: "")
        }
        let sessions = SessionRepository(db: db, core: core)
        guard let session = try sessions.fetchRow(uuid: sessionUuid) else {
            return BriefingStubResponse(stub: "")
        }
        let step = req.agentType.flatMap(BriefingStepSpec.step(forAgentType:))

        var lines: [String] = []
        lines.append("[GMCC BRIEFING STUB]")
        lines.append("session_uuid: \(sessionUuid)")
        if let active = try sessions.resolveActivePrompt(
            sessionUuid: sessionUuid, clientKey: req.clientKey
        ) {
            lines.append("active_prompt_uuid: \(active)")
        }

        // Roles with a mapped step get their briefing line; everyone else
        // still gets the uuid block above.
        if let step {
            let row = try resolveActiveBriefing(
                session: session, step: step, clientKey: req.clientKey)
            if let row {
                let staleness = try computeStaleness(briefing: row)
                let head = row.body
                    .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                    .first.map(String.init) ?? ""
                lines.append("briefing_uuid: \(row.uuid) (step: \(row.briefingForStep), status: \(row.status))")
                if !head.isEmpty { lines.append("briefing_head: \(head.prefix(200))") }
                if staleness.drifted {
                    lines.append(
                        "WARNING: briefing is STALE — dope scope moved "
                        + "\(staleness.stampedRevision.map(String.init) ?? "?") → "
                        + "\(staleness.currentRevision.map(String.init) ?? "?"); "
                        + "prefer fresh gm dope search for anything load-bearing")
                }
                lines.append("Pull the full briefing FIRST: gm briefing get --briefing-uuid \(row.uuid) --json")
            } else {
                lines.append("briefing: none for step '\(step)' — proceed without; gm dope search / gm kbite search are available")
            }
        }
        return BriefingStubResponse(stub: lines.joined(separator: "\n"))
    }

    // MARK: - Selector + staleness internals

    private func resolveSelector(req: BriefingGetRequest) throws -> AgentBriefingRow {
        if let uuid = req.briefingUuid {
            guard let row = try fetchBriefing(uuid: uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: uuid)
            }
            return row
        }
        if let promptUuid = req.promptUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            let rows = try fetchBriefings(
                where: req.step == nil ? "prompt_uuid = ?" : "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: req.step == nil ? [promptUuid] : [promptUuid, req.step!])
            if rows.isEmpty {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: promptUuid)
            }
            guard rows.count == 1 else {
                throw StoreError.badRequest(
                    detail: "prompt \(promptUuid) has \(rows.count) briefings — pass --step to pick one")
            }
            return rows[0]
        }
        if let sessionUuid = req.sessionUuid {
            guard let session = try SessionRepository(db: db, core: core)
                .fetchRow(uuid: sessionUuid) else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            guard let step = req.step else {
                throw StoreError.badRequest(detail: "session-scoped briefing get requires --step")
            }
            guard let row = try resolveActiveBriefing(
                session: session, step: step, clientKey: req.clientKey
            ) else {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: sessionUuid)
            }
            return row
        }
        throw StoreError.badRequest(
            detail: "briefing get takes --briefing-uuid, --prompt-uuid [--step], or --session-uuid --step")
    }

    /// The ACTIVE resolution, scoped like attribution: the calling instance's
    /// own activation claim → the session's single claim when unambiguous →
    /// the session-owned (task) row. This is what makes a spawned agent's
    /// lookup deterministic — no uuid has to survive a spawn prompt.
    private func resolveActiveBriefing(
        session: SessionRow, step: String, clientKey: String?
    ) throws -> AgentBriefingRow? {
        if let active = try SessionRepository(db: db, core: core).resolveActivePrompt(
               sessionUuid: session.uuid, clientKey: clientKey),
           let row = try fetchBriefingRow(
               ownerPrompt: active, ownerSession: session.uuid, step: step) {
            return row
        }
        return try fetchBriefingRow(
            ownerPrompt: nil, ownerSession: session.uuid, step: step)
    }

    private func computeStaleness(briefing: AgentBriefingRow) throws -> BriefingStaleness {
        var currentRevision: Int64?
        if let scopeUuid = briefing.dopeScopeUuid {
            currentRevision = try Int64.fetchOne(
                db, sql: "SELECT revision FROM dope_scope WHERE uuid = ?", arguments: [scopeUuid])
        }
        let drifted: Bool = {
            guard let stamped = briefing.dopeScopeRevision, let current = currentRevision else {
                return false
            }
            return stamped != current
        }()

        var ghosts: [String] = []
        if let scopeUuid = briefing.dopeScopeUuid,
           let data = briefing.dopeRefs.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            for path in paths where try !dopeDotPathExists(scopeUuid: scopeUuid, path: path) {
                ghosts.append(path)
            }
        }
        return BriefingStaleness(
            stampedRevision: briefing.dopeScopeRevision,
            currentRevision: currentRevision,
            drifted: drifted,
            ghostDotPaths: ghosts)
    }

    /// Dot-path existence check for ghost reporting. Forms accepted:
    /// domain · domain.entity · domain.entity.property ·
    /// domain.enums.enum_code · domain.enums.enum_code.option_code.
    /// Anything unparseable is simply a ghost — never an error.
    private func dopeDotPathExists(scopeUuid: String, path: String) throws -> Bool {
        let segs = path.split(separator: ".").map(String.init)
        guard !segs.isEmpty, segs.count <= 4 else { return false }
        guard let persistenceUuid = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM dope_persistence WHERE dope_scope_uuid = ? AND code = ?",
            arguments: [scopeUuid, segs[0]]
        ) else { return false }
        if segs.count == 1 { return true }

        if segs[1] == "enums" {
            guard segs.count >= 3 else { return false }
            guard let enumUuid = try String.fetchOne(
                db,
                sql: "SELECT uuid FROM dope_persistence_enum WHERE dope_persistence_uuid = ? AND code = ?",
                arguments: [persistenceUuid, segs[2]]
            ) else { return false }
            if segs.count == 3 { return true }
            return try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM dope_persistence_enum_option WHERE dope_persistence_enum_uuid = ? AND code = ?",
                arguments: [enumUuid, segs[3]]
            ) != nil
        }

        guard let entityUuid = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ? AND code = ?",
            arguments: [persistenceUuid, segs[1]]
        ) else { return false }
        if segs.count == 2 { return true }
        guard segs.count == 3 else { return false }
        return try Row.fetchOne(
            db,
            sql: "SELECT 1 FROM dope_persistence_entity_property WHERE dope_persistence_entity_uuid = ? AND code = ?",
            arguments: [entityUuid, segs[2]]
        ) != nil
    }

    // MARK: - Fetch helpers

    private func fetchBriefingRow(
        ownerPrompt: String?, ownerSession: String, step: String
    ) throws -> AgentBriefingRow? {
        if let ownerPrompt {
            return try fetchBriefings(
                where: "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: [ownerPrompt, step]
            ).first
        }
        return try fetchBriefings(
            where: "session_uuid = ? AND prompt_uuid IS NULL AND briefing_for_step = ?",
            arguments: [ownerSession, step]
        ).first
    }

    func fetchBriefing(uuid: String) throws -> AgentBriefingRow? {
        try fetchBriefings(where: "uuid = ?", arguments: [uuid]).first
    }

    private func fetchBriefings(
        where condition: String, arguments: StatementArguments
    ) throws -> [AgentBriefingRow] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT uuid, version, session_uuid, prompt_uuid, briefing_for_step, status,
                       body, dope_refs, kbite_refs, dope_scope_uuid, dope_scope_revision,
                       created_at, updated_at
                FROM agent_briefing
                WHERE \(condition)
                ORDER BY briefing_for_step, created_at
                """,
            arguments: arguments
        ).map { row in
            AgentBriefingRow(
                uuid: row["uuid"],
                version: row["version"],
                sessionUuid: row["session_uuid"],
                promptUuid: row["prompt_uuid"],
                briefingForStep: row["briefing_for_step"],
                status: row["status"],
                body: row["body"],
                dopeRefs: row["dope_refs"],
                kbiteRefs: row["kbite_refs"],
                dopeScopeUuid: row["dope_scope_uuid"],
                dopeScopeRevision: row["dope_scope_revision"],
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }
}
