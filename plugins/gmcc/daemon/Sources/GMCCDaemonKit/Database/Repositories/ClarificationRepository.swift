import Foundation
import GRDB

/// CLARIFY_* data access — the db-native clarification machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct ClarificationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent: returns the existing summary or creates one at `building`.
    /// Called by CLARIFY_OPEN and by setPromptStatus's draft → clarifying
    /// create-on-enter.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM clarification_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "clarification_summary", extra: [
            "prompt_uuid": promptUuid,
            "status": ClarificationStatus.building.rawValue,
            "backstory_note": "",
            "refined_goal": "",
            "refined_detail": "",
        ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid]))
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: uuid)
        }
        return ClarifySummaryResponse(summary: summary, created: created)
    }

    func ask(_ req: ClarifyAskRequest) throws -> ClarificationRowResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        guard summary.clarificationStatus == .building else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status, to: "ask",
                reason: "questions can be inserted only while building")
        }
        let question = req.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw StoreError.badRequest(detail: "question is empty")
        }
        // Pre-answered insert (the bot_inferred path): an answer
        // requires a source; CHECK guarantees answered ⇒ answer.
        let answer = req.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: String
        var source: String?
        if let answer, !answer.isEmpty {
            status = ClarificationRowStatus.answered.rawValue
            source = (req.answerSource ?? .botInferred).rawValue
        } else {
            status = ClarificationRowStatus.open.rawValue
            source = nil
        }
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM clarification WHERE clarification_summary_uuid = ?",
            arguments: [req.summaryUuid]) ?? 0) + 1
        let uuid = try core.insertBase(db, table: "clarification", extra: [
            "clarification_summary_uuid": req.summaryUuid,
            "seq": seq,
            "category": req.category.rawValue,
            "question": question,
            "answer": (answer?.isEmpty ?? true) ? nil : answer,
            "answer_source": source,
            "status": status,
        ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "ask", "seq": seq, "category": req.category.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "clarification", key: uuid)
        }
        return ClarificationRowResponse(clarification: row)
    }

    /// Pure child-row update: requires the summary at `answering`, never
    /// touches its version. Revives a skipped row; skip=true marks skipped.
    func answer(_ req: ClarifyAnswerRequest) throws -> ClarificationRowResponse {
        guard let row = try fetchRow(uuid: req.clarificationUuid) else {
            throw StoreError.notFound(entity: "clarification", key: req.clarificationUuid)
        }
        guard let summary = try fetchSummary(uuid: row.clarificationSummaryUuid),
              summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: "summary", to: "answer",
                reason: "answers are writable only while the summary is answering (seal first, reopen after complete)")
        }
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if req.skip {
            set["status"] = ClarificationRowStatus.skipped.rawValue
        } else {
            let answer = req.answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !answer.isEmpty else {
                throw StoreError.badRequest(detail: "answer is empty (pass --skip to skip the question)")
            }
            set["answer"] = answer
            set["answer_source"] = (req.answerSource ?? .user).rawValue
            set["status"] = ClarificationRowStatus.answered.rawValue
        }
        try core.updateBase(
            db, table: "clarification", uuid: req.clarificationUuid,
            expectedVersion: req.expectedVersion, set: set)
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: row.clarificationSummaryUuid,
            payload: Store.jsonPayload([
                "action": req.skip ? "skip" : "answer", "clarification_uuid": req.clarificationUuid,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let updated = try fetchRow(uuid: req.clarificationUuid) else {
            throw StoreError.notFound(entity: "clarification", key: req.clarificationUuid)
        }
        return ClarificationRowResponse(clarification: updated)
    }

    /// answering → complete. Every non-skipped question must be answered and
    /// both refined fields non-empty. Copies refined_goal into prompt.goal —
    /// the ONE daemon-synthesized write exempt from CONTENT_LOCKED (human
    /// content edits stay draft-only); it still goes through updateBase with
    /// the prompt's current in-transaction version so the version bumps and
    /// stale holders keep conflicting.
    func finalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        guard summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "finalize runs from answering")
        }
        let openCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM clarification
            WHERE clarification_summary_uuid = ? AND status = 'open'
            """, arguments: [req.summaryUuid]) ?? 0
        guard openCount == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "\(openCount) question(s) still open — answer or skip them")
        }
        let refinedGoal = req.refinedGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let refinedDetail = req.refinedDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refinedGoal.isEmpty, !refinedDetail.isEmpty else {
            throw StoreError.badRequest(detail: "refined_goal and refined_detail must both be non-empty")
        }
        var set: [String: (any DatabaseValueConvertible)?] = [
            "status": ClarificationStatus.complete.rawValue,
            "refined_goal": refinedGoal,
            "refined_detail": refinedDetail,
        ]
        if let note = req.backstoryNote { set["backstory_note"] = note }
        try core.updateBase(
            db, table: "clarification_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion, set: set)

        guard let promptVersion = try Int64.fetchOne(
            db, sql: "SELECT version FROM prompt WHERE uuid = ?", arguments: [summary.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: summary.promptUuid)
        }
        try core.updateBase(
            db, table: "prompt", uuid: summary.promptUuid,
            expectedVersion: promptVersion, set: ["goal": refinedGoal])
        try core.appendEvent(
            db, kind: .updatePrompt, subjectUuid: summary.promptUuid,
            payload: Store.jsonPayload(["fields": ["goal"], "source": "clarify_finalize"]))
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "finalize", "prompt_uuid": summary.promptUuid]))
        try touchSessionForPrompt(promptUuid: summary.promptUuid)

        guard let updatedSummary = try fetchSummary(uuid: req.summaryUuid),
              let prompt = try prompt.fetchRow(uuid: summary.promptUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        return ClarifyFinalizeResponse(summary: updatedSummary, prompt: prompt)
    }

    func get(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            // A6: the prompt EXISTS (guard above) — this absence is a
            // discriminated SUMMARY_ABSENT, not NOT_FOUND: open a summary.
            throw StoreError.summaryAbsent(
                entity: "clarification", promptUuid: req.promptUuid)
        }
        let rows = try fetchRows(summaryUuid: summary.uuid)
        return ClarifyGetResponse(summary: summary, clarifications: rows)
    }

    // MARK: - Shared transition + fetch helpers

    func transition(
        summaryUuid: String,
        expectedVersion: Int64,
        to: ClarificationStatus,
        action: String,
        requireFrom: ClarificationStatus
    ) throws -> ClarifySummaryResponse {
        guard let summary = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: summaryUuid)
        }
        guard let from = summary.clarificationStatus else {
            throw StoreError.corruptState(entity: "clarification_summary", detail: "status '\(summary.status)'")
        }
        guard from == requireFrom, from.allowedNext.contains(to) else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: from.rawValue, to: to.rawValue,
                reason: "\(action) runs from \(requireFrom.rawValue) — this summary is \(from.rawValue)")
        }
        try core.updateBase(
            db, table: "clarification_summary", uuid: summaryUuid,
            expectedVersion: expectedVersion, set: ["status": to.rawValue])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": action, "from": from.rawValue, "to": to.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let updated = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: summaryUuid)
        }
        return ClarifySummaryResponse(summary: updated)
    }

    /// Item 3 helper shared by the clarify/arch mutation paths: prompt-scoped
    /// writes advance session recency without bumping the session version.
    func touchSessionForPrompt(promptUuid: String) throws {
        if let sessionUuid = try String.fetchOne(
            db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    func fetchSummary(uuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(where: "uuid = ?", key: uuid)
    }

    func fetchSummary(byPrompt promptUuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(where: "prompt_uuid = ?", key: promptUuid)
    }

    private func fetchSummary(
        where condition: String, key: String
    ) throws -> ClarificationSummaryRow? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT uuid, version, prompt_uuid, status, backstory_note,
                       refined_goal, refined_detail, created_at, updated_at
                FROM clarification_summary WHERE \(condition)
                """,
            arguments: [key]
        ) else { return nil }
        return ClarificationSummaryRow(
            uuid: row["uuid"],
            version: row["version"],
            promptUuid: row["prompt_uuid"],
            status: row["status"],
            backstoryNote: row["backstory_note"],
            refinedGoal: row["refined_goal"],
            refinedDetail: row["refined_detail"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func fetchRow(uuid: String) throws -> ClarificationRow? {
        try fetchRows(where: "uuid = ?", key: uuid).first
    }

    func fetchRows(summaryUuid: String) throws -> [ClarificationRow] {
        try fetchRows(where: "clarification_summary_uuid = ?", key: summaryUuid)
    }

    private func fetchRows(
        where condition: String, key: String
    ) throws -> [ClarificationRow] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT uuid, version, clarification_summary_uuid, seq, category,
                       question, answer, answer_source, status
                FROM clarification WHERE \(condition) ORDER BY seq
                """,
            arguments: [key]
        ).map { row in
            ClarificationRow(
                uuid: row["uuid"],
                version: row["version"],
                clarificationSummaryUuid: row["clarification_summary_uuid"],
                seq: row["seq"],
                category: row["category"],
                question: row["question"],
                answer: row["answer"],
                answerSource: row["answer_source"],
                status: row["status"]
            )
        }
    }
}
