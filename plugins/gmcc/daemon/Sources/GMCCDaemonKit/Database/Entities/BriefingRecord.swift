// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `agent_briefing` table. Columns map via convertFromSnakeCase.
struct AgentBriefingRecord: BaseRecordFields {
    static let databaseTableName = "agent_briefing"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String?
    var briefingForStep: String
    var status: String
    var body: String
    var dopeRefs: String
    var kbiteRefs: String
    var dopeScopeUuid: String?
    var dopeScopeRevision: Int64?
}

extension AgentBriefingRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> AgentBriefingRow {
        AgentBriefingRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            briefingForStep: briefingForStep,
            status: status,
            body: body,
            dopeRefs: dopeRefs,
            kbiteRefs: kbiteRefs,
            dopeScopeUuid: dopeScopeUuid,
            dopeScopeRevision: dopeScopeRevision,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}
