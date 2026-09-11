// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `session` table. Columns map via convertFromSnakeCase.
struct SessionRecord: BaseRecordFields {
    static let databaseTableName = "session"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var status: String
    var ckfsRelativeStoragePath: String
}

/// Read-side mirror of the `session_file` table. Columns map via convertFromSnakeCase.
struct SessionFileRecord: BaseRecordFields {
    static let databaseTableName = "session_file"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var relativePath: String
    var active: Int64
}
