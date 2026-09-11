// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `clarification_summary` table. Columns map via convertFromSnakeCase.
struct ClarificationSummaryRecord: BaseRecordFields {
    static let databaseTableName = "clarification_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
    var backstoryNote: String
    var refinedGoal: String
    var refinedDetail: String
}

/// Read-side mirror of the `clarification` table. Columns map via convertFromSnakeCase.
struct ClarificationRecord: BaseRecordFields {
    static let databaseTableName = "clarification"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var seq: Int64
    var category: String
    var question: String
    var answer: String?
    var answerSource: String?
    var status: String
}

extension ClarificationSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ClarificationSummaryRow {
        ClarificationSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            backstoryNote: backstoryNote,
            refinedGoal: refinedGoal,
            refinedDetail: refinedDetail,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

extension ClarificationRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ClarificationRow {
        ClarificationRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            seq: seq,
            category: category,
            question: question,
            answer: answer,
            answerSource: answerSource,
            status: status)
    }
}
