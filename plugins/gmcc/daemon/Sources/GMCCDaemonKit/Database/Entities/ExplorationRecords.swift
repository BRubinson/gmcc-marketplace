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

extension ExplorationSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ExplorationSummaryRow {
        ExplorationSummaryRow(
            uuid: uuid, version: version, promptUuid: promptUuid,
            status: status, overview: overview,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension ExplorationKeyFileRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ExplorationKeyFileRow {
        ExplorationKeyFileRow(
            uuid: uuid, version: version,
            explorationSummaryUuid: explorationSummaryUuid, filePath: filePath)
    }
}

extension ExplorationFindingRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// findingRating narrows Int64 (the column type) to the wire's Int. The
    /// old `row["finding_rating"]` subscript inferred Int straight from the
    /// target type; this makes the conversion explicit and non-truncating.
    func wireRow() -> ExplorationFindingRow {
        ExplorationFindingRow(
            uuid: uuid, version: version,
            explorationSummaryUuid: explorationSummaryUuid,
            kind: kind, title: title, body: body, agentName: agentName,
            findingRating: findingRating.map(Int.init))
    }
}
