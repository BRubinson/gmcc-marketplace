// Shared read-only surface for records carrying the BaseEntity columns.
// Read sugar only — no write path exists on records by design.

import Foundation
import GRDB

protocol BaseRecordFields: Codable, FetchableRecord, Sendable {
    static var databaseTableName: String { get }
    var uuid: String { get }
    var version: Int64 { get }
}

extension BaseRecordFields {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }

    static func fetch(_ db: Database, uuid: String) throws -> Self? {
        try fetchOne(db, sql: "SELECT * FROM \(databaseTableName) WHERE uuid = ?", arguments: [uuid])
    }

    static func require(_ db: Database, uuid: String) throws -> Self {
        guard let row = try fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: databaseTableName, key: uuid)
        }
        return row
    }
}

// Non-base records (junctions/registries without uuid+version) adopt the same
// column strategy through this marker conformance point.
extension FetchableRecord where Self: Codable {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
