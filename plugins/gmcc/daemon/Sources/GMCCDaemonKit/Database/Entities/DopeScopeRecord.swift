// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_scope` table. Columns map via convertFromSnakeCase.
struct DopeScopeRecord: BaseRecordFields {
    static let databaseTableName = "dope_scope"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var instanceUuid: String?
    var sessionUuid: String?
    var promptUuid: String?
    var scopeType: String
    var code: String
    var name: String
    var description: String
    var revision: Int64
    var deletedOn: String?
    var promotedFromScopeUuid: String?
    var promotedFromRevision: Int64?
    var promotedFromUpdatedAt: String?
}
