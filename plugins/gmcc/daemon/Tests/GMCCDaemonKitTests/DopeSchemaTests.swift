import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0007 is pure ADD. The assertions here are shaped by the SILENT failure
/// modes, not the loud ones: a column-list UNIQUE over a nullable prompt_uuid
/// would apply cleanly and then constrain nothing for SESSION_BASE rows
/// (SQLite treats NULLs as distinct), and a missing CHECK coupling would let
/// a scalar property carry an enum ref forever. Both must be proven to
/// actually reject.
final class DopeSchemaTests: XCTestCase {

    private func makeMigratedStore() throws -> (Store, String) {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0007-\(UUID().uuidString).db").path
        let store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');

                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');

                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');

                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', ''),
                       (NULL, 'prompt-b', 0, '\(now)', '\(now)', 'sess-1', 2, 'p2', 'two',
                        '', '', '', '', 'draft', '');
                """)
        }
        return (store, dbPath)
    }

    private func insertScope(
        _ db: Database, uuid: String, session: String = "sess-1",
        prompt: String? = nil, code: String
    ) throws {
        let now = Store.isoNow()
        let scopeType = prompt == nil ? "SESSION_BASE" : "PROMPT"
        try db.execute(sql: """
            INSERT INTO dope_scope (uuid, version, created_at, updated_at,
                session_uuid, prompt_uuid, scope_type, code, name)
            VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [uuid, now, now, session, prompt, scopeType, code, code])
    }

    func testM0007TablesExistAndLedgerAdvanced() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.read { db in
            for table in ["dope_scope", "dope_domain", "dope_domain_entity",
                          "dope_domain_enum", "dope_domain_enum_option",
                          "dope_domain_entity_property"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [table]), 1, "missing table \(table)")
            }
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)
            // No FTS mirrors this pass — dope has no search entry point yet.
            XCTAssertEqual(
                try Int.fetchOne(db, sql:
                    "SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'dope%fts'"), 0)
        }
    }

    /// The case a plain column-list UNIQUE silently allows.
    func testPartialUniqueIndexesRejectDuplicateScopeCodes() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            XCTAssertThrowsError(
                try insertScope(db, uuid: "sc-dup", code: "gmcc"),
                "duplicate SESSION_BASE code must be rejected")

            // Same code under two DIFFERENT prompts is legal…
            try insertScope(db, uuid: "sc-p1", prompt: "prompt-a", code: "gmcc")
            try insertScope(db, uuid: "sc-p2", prompt: "prompt-b", code: "gmcc")
            // …but not twice under the same prompt.
            XCTAssertThrowsError(
                try insertScope(db, uuid: "sc-p1-dup", prompt: "prompt-a", code: "gmcc"))
        }
    }

    func testScopeTypePromptCouplingCheck() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            // SESSION_BASE with a prompt_uuid violates the coupling CHECK.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_scope (uuid, version, created_at, updated_at,
                    session_uuid, prompt_uuid, scope_type, code, name)
                VALUES ('sc-bad', 0, ?, ?, 'sess-1', 'prompt-a', 'SESSION_BASE', 'x', 'x')
                """, arguments: [now, now]))
            // PROMPT without a prompt_uuid violates it from the other side.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_scope (uuid, version, created_at, updated_at,
                    session_uuid, prompt_uuid, scope_type, code, name)
                VALUES ('sc-bad2', 0, ?, ?, 'sess-1', NULL, 'PROMPT', 'x', 'x')
                """, arguments: [now, now]))
        }
    }

    private func insertTree(_ db: Database) throws {
        let now = Store.isoNow()
        try db.execute(sql: """
            INSERT INTO dope_domain (uuid, version, created_at, updated_at,
                dope_scope_uuid, code, name)
            VALUES ('dom-1', 0, '\(now)', '\(now)', 'sc-1', 'core', 'Core');

            INSERT INTO dope_domain_entity (uuid, version, created_at, updated_at,
                dope_domain_uuid, code, name)
            VALUES ('ent-1', 0, '\(now)', '\(now)', 'dom-1', 'user', 'User');

            INSERT INTO dope_domain_enum (uuid, version, created_at, updated_at,
                dope_domain_uuid, code, name)
            VALUES ('enum-1', 0, '\(now)', '\(now)', 'dom-1', 'status', 'Status');

            INSERT INTO dope_domain_enum_option (uuid, version, created_at, updated_at,
                dope_domain_enum_uuid, code, name)
            VALUES ('opt-1', 0, '\(now)', '\(now)', 'enum-1', 'active', 'Active');

            INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                dope_domain_entity_uuid, code, name, data_type, nullable)
            VALUES ('prop-id', 0, '\(now)', '\(now)', 'ent-1', 'id', 'Id', 'uuid', 0);

            INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                dope_domain_entity_uuid, code, name, data_type, nullable, dope_domain_enum_uuid)
            VALUES ('prop-status', 0, '\(now)', '\(now)', 'ent-1', 'status', 'Status',
                    'enum', 0, 'enum-1');
            """)
    }

    func testPropertyCheckCoupling() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            let now = Store.isoNow()

            // enum data_type without an enum ref.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable)
                VALUES ('p-bad1', 0, '\(now)', '\(now)', 'ent-1', 'b1', 'B1', 'enum', 1)
                """))
            // scalar data_type carrying an enum ref.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable, dope_domain_enum_uuid)
                VALUES ('p-bad2', 0, '\(now)', '\(now)', 'ent-1', 'b2', 'B2', 'text', 1, 'enum-1')
                """))
            // relationship without a target property.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable)
                VALUES ('p-bad3', 0, '\(now)', '\(now)', 'ent-1', 'b3', 'B3', 'relationship', 1)
                """))
            // auto_increment on a non-long property.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable, auto_increment)
                VALUES ('p-bad4', 0, '\(now)', '\(now)', 'ent-1', 'b4', 'B4', 'text', 1, 1)
                """))
            // A legal relationship targeting an existing property.
            try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable, related_property_uuid)
                VALUES ('prop-rel', 0, '\(now)', '\(now)', 'ent-1', 'owner', 'Owner',
                        'relationship', 1, 'prop-id')
                """)
        }
    }

    func testRestrictRefusesDeletingReferencedEnumAndProperty() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable, related_property_uuid)
                VALUES ('prop-rel', 0, '\(now)', '\(now)', 'ent-1', 'owner', 'Owner',
                        'relationship', 1, 'prop-id')
                """)
            // The enum types prop-status: RESTRICT refuses.
            XCTAssertThrowsError(
                try db.execute(sql: "DELETE FROM dope_domain_enum WHERE uuid = 'enum-1'"))
            // prop-id is targeted by prop-rel: RESTRICT refuses.
            XCTAssertThrowsError(
                try db.execute(sql:
                    "DELETE FROM dope_domain_entity_property WHERE uuid = 'prop-id'"))
        }
    }

    /// The ordered-delete discipline: properties first, then domains
    /// (CASCADE), then the scope. A naive scope delete would hit the
    /// RESTRICT wall through the sideways property refs.
    func testOrderedScopeWipeLeavesNoOrphans() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            try db.execute(sql: """
                DELETE FROM dope_domain_entity_property
                 WHERE dope_domain_entity_uuid IN (
                    SELECT e.uuid FROM dope_domain_entity e
                      JOIN dope_domain d ON d.uuid = e.dope_domain_uuid
                     WHERE d.dope_scope_uuid = 'sc-1');
                DELETE FROM dope_domain WHERE dope_scope_uuid = 'sc-1';
                DELETE FROM dope_scope WHERE uuid = 'sc-1';
                """)
            for table in ["dope_scope", "dope_domain", "dope_domain_entity",
                          "dope_domain_enum", "dope_domain_enum_option",
                          "dope_domain_entity_property"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0,
                    "orphans left in \(table)")
            }
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    // MARK: - m0008 (BASE_COMPOSABLE + base_composable_uuid)

    func testM0008EntityTypeCouplingAndSelfFk() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            let now = Store.isoNow()

            // The widened CHECK accepts BASE_COMPOSABLE…
            try db.execute(sql: """
                INSERT INTO dope_domain_entity (uuid, version, created_at, updated_at,
                    dope_domain_uuid, code, name, entity_type)
                VALUES ('ent-base', 0, '\(now)', '\(now)', 'dom-1', 'base_entity',
                        'Base Entity', 'BASE_COMPOSABLE')
                """)
            // …and still rejects anything else.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity (uuid, version, created_at, updated_at,
                    dope_domain_uuid, code, name, entity_type)
                VALUES ('ent-bad', 0, '\(now)', '\(now)', 'dom-1', 'bad', 'Bad', 'MODULE')
                """))
            // The self-FK survived the rebuild + rename: a dangling target
            // is refused…
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity (uuid, version, created_at, updated_at,
                    dope_domain_uuid, code, name, base_composable_uuid)
                VALUES ('ent-dangling', 0, '\(now)', '\(now)', 'dom-1', 'dang', 'Dang',
                        'no-such-entity')
                """))
            // …and the self-ref CHECK catches the degenerate 1-cycle.
            XCTAssertThrowsError(try db.execute(sql: """
                UPDATE dope_domain_entity SET base_composable_uuid = 'ent-1'
                 WHERE uuid = 'ent-1'
                """))
            // A legal composition.
            try db.execute(sql: """
                UPDATE dope_domain_entity SET base_composable_uuid = 'ent-base'
                 WHERE uuid = 'ent-1'
                """)
        }
    }

    func testM0008PreservesEveryEntityRowAndIndex() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
        }
        try store.dbQueue.read { db in
            // Both indexes exist post-rebuild (a DROP takes them silently).
            for index in ["idx_dope_domain_entity_domain_fk",
                          "idx_dope_entity_base_composable_fk"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?",
                        arguments: [index]), 1, "missing index \(index)")
            }
            // ids stay contiguous rowids and the whole db passes an FK sweep.
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_domain_entity"), 1)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MIN(id) FROM dope_domain_entity"), 1)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    // MARK: - m0009 (base_origin_property_uuid)

    func testM0009ColumnAndIndexExistAndLedgerAdvanced() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.read { db in
            let column = try Row.fetchOne(db, sql: """
                SELECT "notnull" AS nn, dflt_value AS dflt
                FROM pragma_table_info('dope_domain_entity_property')
                WHERE name = 'base_origin_property_uuid'
                """)
            XCTAssertNotNil(column, "column missing")
            XCTAssertEqual(column?["nn"] as Int?, 0, "must be nullable")
            XCTAssertNil(column?["dflt"] as String?, "must have no default")
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_dope_property_base_origin_fk'
                    """), 1)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)
        }
    }

    func testBaseOriginSchemaBehaviour() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            let now = Store.isoNow()
            // data_type-independent at the schema level: a text property may
            // carry a base_origin (no accidental CHECK coupling)…
            try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable,
                    base_origin_property_uuid)
                VALUES ('prop-tagged', 0, '\(now)', '\(now)', 'ent-1', 'note', 'Note',
                        'text', 1, 'prop-id')
                """)
            // …a dangling origin is refused (the FK survived the ADD COLUMN)…
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO dope_domain_entity_property (uuid, version, created_at, updated_at,
                    dope_domain_entity_uuid, code, name, data_type, nullable,
                    base_origin_property_uuid)
                VALUES ('prop-dangling', 0, '\(now)', '\(now)', 'ent-1', 'dang', 'Dang',
                        'text', 1, 'no-such-property')
                """))
            // …and RESTRICT refuses deleting a tagged origin.
            XCTAssertThrowsError(try db.execute(
                sql: "DELETE FROM dope_domain_entity_property WHERE uuid = 'prop-id'"))
        }
    }

    func testBaseRestrictRefusesDeletingComposedEntity() throws {
        let (store, dbPath) = try makeMigratedStore()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        try store.dbQueue.write { db in
            try insertScope(db, uuid: "sc-1", code: "gmcc")
            try insertTree(db)
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO dope_domain_entity (uuid, version, created_at, updated_at,
                    dope_domain_uuid, code, name, entity_type)
                VALUES ('ent-base', 0, '\(now)', '\(now)', 'dom-1', 'base_entity',
                        'Base Entity', 'BASE_COMPOSABLE');
                UPDATE dope_domain_entity SET base_composable_uuid = 'ent-base'
                 WHERE uuid = 'ent-1';
                """)
            XCTAssertThrowsError(
                try db.execute(sql: "DELETE FROM dope_domain_entity WHERE uuid = 'ent-base'"))
        }
    }
}
