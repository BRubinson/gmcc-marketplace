import Foundation
import GRDB

// BRIEFING_* (v21) — the agent-briefing machine: the context package a doper
// agent assembles for a phase, pulled by spawned agents at start.
//
// Modeled on m0022's RESTRAINT, not the report families: a briefing is
// spawn-time plumbing consumed once, so there is no findings machinery, no
// FTS mirror, and a two-state consumption gate (building → ready) instead of
// a status machine. OPEN on an existing (owner, step) pair RESETS the row to
// building — a step's briefing is always its CURRENT briefing, never a pile
// of drafts. Staleness is COMPUTED at every read (stored scope revision vs
// live, dot-paths re-resolved to surface ghosts) and only ever WARNS: the
// fetch-fresh-per-phase guardrail as a computed signal, never a block.

/// Registry-governed vocabularies (the m0021 element_type rule): the columns
/// carry NO db CHECK, so a future step or status is an entry here — never a
/// migration. The role map is what lets `gm briefing stub` resolve an agent
/// type to its step without the hook script knowing anything.
public enum BriefingStepSpec {
    public static let steps: [String] = ["initial", "pre_architecture"]
    public static let statuses: [String] = ["building", "ready"]

    /// agent role (plugin-scoped name with or without the `gmcc:` prefix) →
    /// the step that role consumes. Roles absent here get no briefing line in
    /// their stub — deliberately, not an error.
    public static let roleStepMap: [String: String] = [
        "doper": "initial",
        "code-explorer": "initial",
        "code-architect": "pre_architecture",
    ]

    public static func validateStep(_ raw: String) throws -> String {
        guard steps.contains(raw) else {
            throw StoreError.badRequest(
                detail: "unknown briefing step '\(raw)' — known: \(steps.joined(separator: ", "))")
        }
        return raw
    }

    public static func step(forAgentType agentType: String) -> String? {
        let bare = agentType.hasPrefix("gmcc:")
            ? String(agentType.dropFirst("gmcc:".count))
            : agentType
        return roleStepMap[bare]
    }
}

extension Store {

    // MARK: - Verbs

    /// Reserve (or reset) the briefing row for one (owner, step) pair.
    /// Exactly one owner flag; session_uuid is ALWAYS stored (derived from
    /// the prompt's owner chain when prompt-owned) so the two columns can
    /// never disagree and task-owned rows share the same list key.
    public func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try dbQueue.write { db in
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
                try self.claimActivation(
                    db, sessionUuid: sessionUuid,
                    promptUuid: promptUuid, clientKey: clientKey)
            }

            if let existing = try self.fetchBriefingRow(
                db, ownerPrompt: promptUuid, ownerSession: sessionUuid, step: step
            ) {
                // Reset, never duplicate: content is kept for wholesale
                // replacement at complete (the reopen-preserves precedent).
                try self.updateBase(
                    db, table: "agent_briefing", uuid: existing.uuid,
                    expectedVersion: existing.version,
                    set: ["status": "building"])
                try self.appendEvent(
                    db, kind: .briefingChange, subjectUuid: existing.uuid,
                    payload: Store.jsonPayload([
                        "action": "reset", "step": step,
                        "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
                    ]))
                try self.touchSession(db, uuid: sessionUuid)
                guard let row = try self.fetchBriefing(db, uuid: existing.uuid) else {
                    throw StoreError.notFound(entity: "agent_briefing", key: existing.uuid)
                }
                return BriefingRowResponse(briefing: row, created: false)
            }

            let uuid = try self.insertBase(db, table: "agent_briefing", extra: [
                "session_uuid": sessionUuid,
                "prompt_uuid": promptUuid,
                "briefing_for_step": step,
                "status": "building",
                "body": "",
                "dope_refs": "[]",
                "kbite_refs": "[]",
            ])
            try self.appendEvent(
                db, kind: .briefingChange, subjectUuid: uuid,
                payload: Store.jsonPayload([
                    "action": "open", "step": step,
                    "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
                ]))
            try self.touchSession(db, uuid: sessionUuid)
            guard let row = try self.fetchBriefing(db, uuid: uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: uuid)
            }
            return BriefingRowResponse(briefing: row, created: true)
        }
    }

    /// building → ready. The daemon stamps the staleness evidence ITSELF
    /// (the writing agent cannot mis-stamp) and denormalizes kbite briefs.
    public func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try dbQueue.write { db in
            guard let existing = try self.fetchBriefing(db, uuid: req.briefingUuid) else {
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
            let scope = try self.dopeScopeCandidates(
                db, sessionUuid: existing.sessionUuid, scopeType: .sessionInstance
            ).first

            try self.updateBase(
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
            try self.appendEvent(
                db, kind: .briefingChange, subjectUuid: req.briefingUuid,
                payload: Store.jsonPayload([
                    "action": "complete", "step": existing.briefingForStep,
                    "session_uuid": existing.sessionUuid,
                    "prompt_uuid": existing.promptUuid,
                    "dope_scope_revision": scope?.revision,
                ]))
            try self.touchSession(db, uuid: existing.sessionUuid)
            guard let row = try self.fetchBriefing(db, uuid: req.briefingUuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
            }
            return BriefingRowResponse(briefing: row)
        }
    }

    public func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try dbQueue.read { db in
            let row = try self.resolveBriefingSelector(db, req: req)
            let staleness = try self.computeBriefingStaleness(db, briefing: row)
            return BriefingGetResponse(briefing: row, staleness: staleness)
        }
    }

    public func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try dbQueue.read { db in
            let rows: [AgentBriefingRow]
            if let promptUuid = req.promptUuid {
                guard try Row.fetchOne(
                    db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
                ) != nil else {
                    throw StoreError.notFound(entity: "prompt", key: promptUuid)
                }
                rows = try self.fetchBriefings(
                    db, where: "prompt_uuid = ?", arguments: [promptUuid])
            } else if let sessionUuid = req.sessionUuid {
                guard try Row.fetchOne(
                    db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
                ) != nil else {
                    throw StoreError.notFound(entity: "session", key: sessionUuid)
                }
                rows = try self.fetchBriefings(
                    db, where: "session_uuid = ?", arguments: [sessionUuid])
            } else {
                throw StoreError.badRequest(
                    detail: "briefing list takes --prompt-uuid or --session-uuid")
            }
            return BriefingListResponse(briefings: rows)
        }
    }

    /// The SubagentStart hook's one call. Empty stub + success when nothing
    /// applies — the hook must never wedge a spawn.
    public func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try dbQueue.read { db in
            guard let sessionUuid = req.sessionUuid else {
                return BriefingStubResponse(stub: "")
            }
            guard let session = try self.fetchSessionRow(db, uuid: sessionUuid) else {
                return BriefingStubResponse(stub: "")
            }
            let step = req.agentType.flatMap(BriefingStepSpec.step(forAgentType:))

            var lines: [String] = []
            lines.append("[GMCC BRIEFING STUB]")
            lines.append("session_uuid: \(sessionUuid)")
            if let active = try self.resolveActivePrompt(
                db, sessionUuid: sessionUuid, clientKey: req.clientKey
            ) {
                lines.append("active_prompt_uuid: \(active)")
            }

            // Roles with a mapped step get their briefing line; everyone else
            // still gets the uuid block above.
            if let step {
                let row = try self.resolveActiveBriefing(
                    db, session: session, step: step, clientKey: req.clientKey)
                if let row {
                    let staleness = try self.computeBriefingStaleness(db, briefing: row)
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
    }

    // MARK: - Selector + staleness internals

    private func resolveBriefingSelector(
        _ db: Database, req: BriefingGetRequest
    ) throws -> AgentBriefingRow {
        if let uuid = req.briefingUuid {
            guard let row = try self.fetchBriefing(db, uuid: uuid) else {
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
            let rows = try self.fetchBriefings(
                db,
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
            guard let session = try self.fetchSessionRow(db, uuid: sessionUuid) else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            guard let step = req.step else {
                throw StoreError.badRequest(detail: "session-scoped briefing get requires --step")
            }
            guard let row = try self.resolveActiveBriefing(
                db, session: session, step: step, clientKey: req.clientKey
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
        _ db: Database, session: SessionRow, step: String, clientKey: String?
    ) throws -> AgentBriefingRow? {
        if let active = try self.resolveActivePrompt(
               db, sessionUuid: session.uuid, clientKey: clientKey),
           let row = try self.fetchBriefingRow(
               db, ownerPrompt: active, ownerSession: session.uuid, step: step) {
            return row
        }
        return try self.fetchBriefingRow(
            db, ownerPrompt: nil, ownerSession: session.uuid, step: step)
    }

    private func computeBriefingStaleness(
        _ db: Database, briefing: AgentBriefingRow
    ) throws -> BriefingStaleness {
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
            for path in paths where try !self.dopeDotPathExists(db, scopeUuid: scopeUuid, path: path) {
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
    private func dopeDotPathExists(
        _ db: Database, scopeUuid: String, path: String
    ) throws -> Bool {
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
        _ db: Database, ownerPrompt: String?, ownerSession: String, step: String
    ) throws -> AgentBriefingRow? {
        if let ownerPrompt {
            return try self.fetchBriefings(
                db, where: "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: [ownerPrompt, step]
            ).first
        }
        return try self.fetchBriefings(
            db, where: "session_uuid = ? AND prompt_uuid IS NULL AND briefing_for_step = ?",
            arguments: [ownerSession, step]
        ).first
    }

    func fetchBriefing(_ db: Database, uuid: String) throws -> AgentBriefingRow? {
        try self.fetchBriefings(db, where: "uuid = ?", arguments: [uuid]).first
    }

    private func fetchBriefings(
        _ db: Database, where condition: String, arguments: StatementArguments
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

    // MARK: - JSON helpers (deterministic encodings for TEXT-JSON columns)

    static func encodeJsonArray(_ strings: [String]) throws -> String {
        let data = try JSONEncoder().encode(strings)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func encodeJsonObjectArray(_ objects: [[String: String?]]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(objects)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
