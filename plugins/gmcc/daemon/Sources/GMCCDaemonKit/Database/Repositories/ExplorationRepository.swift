import Foundation
import GRDB

/// EXPLORE_* data access — the db-native exploration report machine. Runs
/// INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. The shared rank/validation statics stay on Store (they
/// serve Store+Review too).
struct ExplorationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent: returns the existing summary or creates one at `exploring`.
    /// Called ONLY by EXPLORE_OPEN — never by setPromptStatus (explicit-open
    /// only; prompt status has no exploration coupling).
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM exploration_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "exploration_summary", extra: [
            "prompt_uuid": promptUuid,
            "status": ExplorationStatus.exploring.rawValue,
            "overview": "",
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: promptUuid)
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        return ExploreSummaryResponse(summary: summary, created: created)
    }

    /// Key files are a shared deduped set: a duplicate path is an idempotent
    /// upsert-ignore returning the existing row (the prompt_artifact
    /// precedent), never an error.
    func keyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid, at: .exploring, verb: "key-file-add")
        let path = try Store.normalizeRepoRelativePath(
            req.filePath, repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid))
        if let existing = try fetchKeyFiles(
            where: "exploration_summary_uuid = ? AND file_path = ?",
            arguments: [req.summaryUuid, path]
        ).first {
            return ExploreKeyFileAddResponse(keyFile: existing, created: false)
        }
        let uuid = try core.insertBase(db, table: "exploration_key_file", extra: [
            "exploration_summary_uuid": req.summaryUuid,
            "file_path": path,
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "key_file_add", "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchKeyFiles(where: "uuid = ?", arguments: [uuid]).first else {
            throw StoreError.notFound(entity: "exploration_key_file", key: uuid)
        }
        return ExploreKeyFileAddResponse(keyFile: row, created: true)
    }

    func findingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid, at: .exploring, verb: "finding-add")
        let (title, body, agentName) = try Store.validatedFindingText(
            title: req.title, body: req.body, agentName: req.agentName)
        try Store.validateRating(req.rating)
        let uuid = try core.insertBase(db, table: "exploration_finding", extra: [
            "exploration_summary_uuid": req.summaryUuid,
            "kind": req.kind.rawValue,
            "title": title,
            "body": body,
            "agent_name": agentName,
            "finding_rating": req.rating,
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "finding_add", "kind": req.kind.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchFindings(where: "uuid = ?", arguments: [uuid]).first else {
            throw StoreError.notFound(entity: "exploration_finding", key: uuid)
        }
        return ExploreFindingRowResponse(finding: row)
    }

    /// Batch rank — atomic all-or-nothing, deliberately version-less: the team
    /// re-ranker blind-overwrites ratings it never read (the specified
    /// semantic), and the single-writer DatabaseQueue serializes competing
    /// batches; row versions still bump via updateBase so stale holders of a
    /// FINDING version conflict normally elsewhere. Refused once complete —
    /// ranking a sealed set would shift the sub-100 contract; reopen first.
    func rank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .exploring, verb: "rank")
        try findingRank.applyRankBatch(
            table: "exploration_finding", parentColumn: "exploration_summary_uuid",
            summaryUuid: req.summaryUuid, ratings: req.ratings)
        let unranked = try findingRank.unrankedCount(
            table: "exploration_finding", parentColumn: "exploration_summary_uuid",
            summaryUuid: req.summaryUuid)
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "rank", "count": req.ratings.count,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreRankResponse(
            summary: updated, updatedCount: req.ratings.count, unrankedCount: unranked)
    }

    /// exploring → complete. Refuses while any finding is unranked; `overview`
    /// is carried only here (its ONLY write path).
    func complete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .exploring, verb: "complete")
        let unranked = try findingRank.unrankedCount(
            table: "exploration_finding", parentColumn: "exploration_summary_uuid",
            summaryUuid: req.summaryUuid)
        guard unranked == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: summary.status,
                to: ExplorationStatus.complete.rawValue,
                reason: "\(unranked) finding(s) unranked — run gm explore rank first")
        }
        let overview = try Store.validatedOverview(req.overview, entity: "exploration")
        try core.updateBase(
            db, table: "exploration_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.complete.rawValue, "overview": overview])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "complete", "prompt_uuid": summary.promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    /// complete → exploring: the revision edge. Preserves everything —
    /// findings, ratings, key files, overview (nulling would make a mistaken
    /// reopen unrecoverable in an append-only db); the next COMPLETE must
    /// re-carry the overview, so staleness cannot survive a re-seal.
    func reopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        guard summary.explorationStatus == .complete else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: summary.status,
                to: ExplorationStatus.exploring.rawValue,
                reason: "reopen runs from complete — this summary is \(summary.status)")
        }
        try core.updateBase(
            db, table: "exploration_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.exploring.rawValue])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "reopen", "prompt_uuid": summary.promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    func get(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            throw StoreError.summaryAbsent(
                entity: "exploration", promptUuid: req.promptUuid)
        }
        let keyFiles = try fetchKeyFiles(
            where: "exploration_summary_uuid = ?", arguments: [summary.uuid])
        let window = try Store.ratingWindow(full: req.full, min: req.ratingMin, max: req.ratingMax)
        let all = try fetchFindings(
            where: "exploration_summary_uuid = ?", arguments: [summary.uuid])
        var full: [ExplorationFindingRow] = []
        var stubs: [ExplorationFindingStub] = []
        for row in all {
            if Store.ratingInWindow(row.findingRating, window: window) {
                full.append(row)
            } else {
                stubs.append(ExplorationFindingStub(
                    uuid: row.uuid, kind: row.kind, title: row.title,
                    findingRating: row.findingRating, agentName: row.agentName))
            }
        }
        return ExploreGetResponse(
            summary: summary, keyFiles: keyFiles, findings: full, findingStubs: stubs)
    }

    // MARK: - Transition + fetch helpers

    private func requireSummary(
        uuid: String, at required: ExplorationStatus, verb: String
    ) throws -> ExplorationSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        guard summary.explorationStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: summary.status, to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)")
        }
        return summary
    }

    func fetchSummary(uuid: String) throws -> ExplorationSummaryRow? {
        try fetchSummary(where: "uuid = ?", key: uuid)
    }

    func fetchSummary(byPrompt promptUuid: String) throws -> ExplorationSummaryRow? {
        try fetchSummary(where: "prompt_uuid = ?", key: promptUuid)
    }

    private func fetchSummary(
        where condition: String, key: String
    ) throws -> ExplorationSummaryRow? {
        try ExplorationSummaryRecord.fetchAll(
            db, where: condition, arguments: [key]
        ).first?.wireRow()
    }

    private func fetchKeyFiles(
        where condition: String, arguments: StatementArguments
    ) throws -> [ExplorationKeyFileRow] {
        try ExplorationKeyFileRecord.fetchAll(
            db, where: condition, arguments: arguments, orderBy: "file_path"
        ).map { $0.wireRow() }
    }

    /// Explicit ordering: unranked (NULL) rows sort FIRST — the resume
    /// work-queue can't be missed — then by rating ascending, then id.
    private func fetchFindings(
        where condition: String, arguments: StatementArguments
    ) throws -> [ExplorationFindingRow] {
        try ExplorationFindingRecord.fetchAll(
            db, where: condition, arguments: arguments,
            orderBy: "finding_rating IS NOT NULL, finding_rating, id"
        ).map { $0.wireRow() }
    }
}
