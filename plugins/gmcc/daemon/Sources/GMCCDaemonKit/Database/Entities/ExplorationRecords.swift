// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `exploration_summary` table. Columns map via convertFromSnakeCase.
struct ExplorationSummaryRecord: BaseRecordFields {
    static let databaseTableName = "exploration_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
    var overview: String
}

/// Read-side mirror of the `exploration_finding` table. Columns map via convertFromSnakeCase.
struct ExplorationFindingRecord: BaseRecordFields {
    static let databaseTableName = "exploration_finding"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var explorationSummaryUuid: String
    var kind: String
    var title: String
    var body: String
    var agentName: String
    var findingRating: Int64?
}

/// Read-side mirror of the `exploration_key_file` table. Columns map via convertFromSnakeCase.
struct ExplorationKeyFileRecord: BaseRecordFields {
    static let databaseTableName = "exploration_key_file"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var explorationSummaryUuid: String
    var filePath: String
}
