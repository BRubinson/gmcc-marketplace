// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_persistence` table. Columns map via convertFromSnakeCase.
struct DopePersistenceRecord: BaseRecordFields {
    static let databaseTableName = "dope_persistence"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopeScopeUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var contentRevision: Int64
    var deletedOn: String?
}

/// Read-side mirror of the `dope_persistence_entity` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEntityRecord: BaseRecordFields {
    static let databaseTableName = "dope_persistence_entity"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceUuid: String
    var code: String
    var name: String
    var entityType: String
    var description: String
    var sortOrder: Int64
    var repoRepresentativeFile: String?
    var baseComposableUuid: String?
    var deletedOn: String?
}

/// Read-side mirror of the `dope_persistence_entity_property` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEntityPropertyRecord: BaseRecordFields {
    static let databaseTableName = "dope_persistence_entity_property"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceEntityUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var dataType: String
    var nullable: Int64
    var isUnique: Int64
    var autoIncrement: Int64?
    var textCharLimit: Int64?
    var dopePersistenceEnumUuid: String?
    var relationshipTargetUuid: String?
    var baseOriginPropertyUuid: String?
    var deletedOn: String?
}

/// Read-side mirror of the `dope_persistence_enum` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEnumRecord: BaseRecordFields {
    static let databaseTableName = "dope_persistence_enum"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var repoRepresentativeFile: String?
    var deletedOn: String?
}

/// Read-side mirror of the `dope_persistence_enum_option` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEnumOptionRecord: BaseRecordFields {
    static let databaseTableName = "dope_persistence_enum_option"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceEnumUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var deletedOn: String?
}
