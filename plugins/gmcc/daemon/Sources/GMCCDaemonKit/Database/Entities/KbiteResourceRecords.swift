// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource` table. Columns map via convertFromSnakeCase.
struct KbiteResourceRecord: BaseRecordFields {
    static let databaseTableName = "kbite_resource"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteUuid: String
    var resourceName: String
    var resourceSummary: String
    var resourceType: String
    var resourceTrust: Int64
}

/// Read-side mirror of the `kbite_resource_file` table. Columns map via convertFromSnakeCase.
struct KbiteResourceFileRecord: BaseRecordFields {
    static let databaseTableName = "kbite_resource_file"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteResourceUuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var resourceFileContent: String?
}

/// Read-side mirror of the `resource_file_keyword_junction` table. Columns map via convertFromSnakeCase.
struct ResourceFileKeywordJunctionRecord: BaseRecordFields {
    static let databaseTableName = "resource_file_keyword_junction"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var fileUuid: String
    var keywordUuid: String
}
