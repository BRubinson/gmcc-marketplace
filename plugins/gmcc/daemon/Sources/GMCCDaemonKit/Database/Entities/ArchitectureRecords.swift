// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_summary` table. Columns map via convertFromSnakeCase.
struct ArchitectureSummaryRecord: BaseRecordFields {
    static let databaseTableName = "architecture_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var body: String
    var status: String
}

/// Read-side mirror of the `architecture_general_change` table. Columns map via convertFromSnakeCase.
struct ArchitectureGeneralChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_general_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var filePath: String
    var className: String?
    var reasonBrief: String
    var changeDepth: String
    var changeCode: String
}

/// Read-side mirror of the `architecture_persistence_change` table. Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_persistence_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var className: String
    var filePath: String
    var reasonBrief: String
}

/// Read-side mirror of the `architecture_persistence_field_change` table. Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceFieldChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_persistence_field_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var persistenceChangeUuid: String
    var seq: Int64
    var fieldName: String
    var changeReason: String
    var changePurpose: String
    var dataType: String
    var nullable: Bool
    var isForeignKey: Bool
    var fkTarget: String?
    var isIndexed: Bool
}
