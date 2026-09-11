// Shared read-only surface for records carrying the BaseEntity columns.
// Read sugar only — no write path exists on records by design.
//
// wireRow() CONVENTION (fixed here so each domain does not invent its own):
//
//   A. Nullary, total: `func wireRow() -> XRow`. The default — 13 of the ~20
//      conversions. Copy ProjectRecord's literally, doc sentence included.
//   B. Parameterized, for the SIX composed wire rows whose extra data comes
//      from another query: SessionRecord.wireRow(activations:),
//      FileChangeRecord.wireRow(ranges:), KbiteResourceRecord.wireRow(files:),
//      ArchitecturePersistenceChangeRecord.wireRow(fields:implementation:),
//      ArchitectureGeneralChangeRecord.wireRow(implementation:),
//      DiagramRecord.wireRow(instanceUuid:). Every injected child is a
//      LABELLED argument with NO default — a default would re-open the
//      silent-omission hole the wire Row init defaults were removed to close.
//   C. Decoder-only: a Record with no 1:1 wire twin (DopeRepository's tree
//      hydration). It earns its keep as the decode step; do NOT invent a
//      wireRow() for it.
//
// `db` never enters Entities/ and enrichment never happens inside a Record:
// records stay flat so RecordSchemaTests can decode them from a synthesized
// PRAGMA row.

import Foundation
import GRDB

/// Opt-in snake_case column mapping. Every read-side decoder in this module
/// declares this conformance explicitly — there is deliberately NO blanket
/// `extension FetchableRecord where Self: Codable` here, so a query struct
/// added inside a repository cannot silently inherit a decoding strategy from
/// a file nobody opened.
protocol SnakeCaseDecoded: Codable, FetchableRecord {
    // no requirements: conformance IS the opt-in
}

extension SnakeCaseDecoded {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}

/// A record mirroring a live table, carrying the BaseEntity columns.
///
/// Note there is no `id` (SQLite rowid) property: the daemon's identity is
/// `uuid` everywhere, records are FetchableRecord-only so a rowid can never be
/// used for a write, and a non-optional `id` would make every Record unable to
/// decode the explicit-column-list SELECTs that omit it. `DaemonEventRecord`
/// is the sole exception — there the rowid IS the wire identity
/// (`EventNotification.id`, the SUBSCRIBE replay cursor).
protocol BaseRecordFields: SnakeCaseDecoded, Sendable {
    static var databaseTableName: String { get }
    var uuid: String { get }
    var version: Int64 { get }
}

extension BaseRecordFields {
    static func fetch(_ db: Database, uuid: String) throws -> Self? {
        try fetchOne(db, sql: "SELECT * FROM \(databaseTableName) WHERE uuid = ?", arguments: [uuid])
    }

    static func require(_ db: Database, uuid: String) throws -> Self {
        guard let row = try fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: databaseTableName, key: uuid)
        }
        return row
    }

    /// `SELECT * FROM <table> [WHERE …] [ORDER BY …]`, so a converted fetch
    /// does not re-type the table name the protocol already owns.
    ///
    /// NOT for `kbite_resource_file`: its stub reads deliberately project
    /// `resource_file_content IS NOT NULL AS has_content` to keep ~115 MB of
    /// content out of the result set. Use KbiteResourceFileStubRecord.
    static func fetchAll(
        _ db: Database,
        where condition: String? = nil,
        arguments: StatementArguments = StatementArguments(),
        orderBy: String? = nil
    ) throws -> [Self] {
        var sql = "SELECT * FROM \(databaseTableName)"
        if let condition { sql += " WHERE \(condition)" }
        if let orderBy { sql += " ORDER BY \(orderBy)" }
        return try fetchAll(db, sql: sql, arguments: arguments)
    }
}
