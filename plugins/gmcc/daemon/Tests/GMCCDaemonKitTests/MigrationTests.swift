import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0002 is the first migration that cannot be fixed by wiping the db. The
/// fixture shape is derived from the SILENT failure mode, not the loud one:
/// a wrong rebuild body (FK pragma inside the transaction) aborts loudly on a
/// db that has a NO-ACTION referrer of prompt (file_change.prompt_uuid) but
/// CASCADE-deletes every prompt_artifact row and COMMITS on a db without one.
/// The fixture therefore must contain, at minimum: a prompt_artifact (CASCADE),
/// a prompt_active_kbite (CASCADE), and a file_change with non-null
/// prompt_uuid (NO ACTION) — and assert all three counts survive.
final class MigrationTests: XCTestCase {

    private func makeV1Fixture() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: "m0001_baseSchema")
        try queue.write { db in
            let now = "2026-08-01T00:00:00Z"
            func base(_ uuid: String, id: Int64? = nil) -> String {
                let idSql = id.map { String($0) } ?? "NULL"
                return "\(idSql), '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');

                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo', 'projects/repo/instances/repo_1');

                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');

                -- Three prompts across every legacy status; explicit ids 1..3
                -- so the uuid→id pairwise-identity assertion is meaningful.
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (1, 'prompt-a', 3, '\(now)', '\(now)', 'sess-1', 1, 'p1', 'one',
                        '', '', '', '', 'clarified', ''),
                       (2, 'prompt-b', 0, '\(now)', '\(now)', 'sess-1', 2, 'p2', 'two',
                        '', '', '', '', 'draft', ''),
                       (3, 'prompt-c', 1, '\(now)', '\(now)', 'sess-1', 3, 'p3', 'three',
                        '', '', '', '', 'clarifying', '');

                INSERT INTO prompt_artifact (id, uuid, version, created_at, updated_at,
                    prompt_uuid, file_path, kind, note)
                VALUES (\(base("art-1")), 'prompt-a', '/m/qualified.md', 'qualified', NULL),
                       (NULL, 'art-2', 0, '\(now)', '\(now)', 'prompt-a', '/m/architecture.md', 'architecture', NULL);

                INSERT INTO kbite (id, uuid, version, created_at, updated_at, code)
                VALUES (\(base("kb-1")), 'swift');

                INSERT INTO prompt_active_kbite (id, uuid, version, created_at, updated_at,
                    prompt_uuid, kbite_uuid)
                VALUES (\(base("pak-1")), 'prompt-a', 'kb-1');

                INSERT INTO session_file (id, uuid, version, created_at, updated_at,
                    session_uuid, relative_path, active)
                VALUES (\(base("sf-1")), 'sess-1', 'Sources/App.swift', 1);

                INSERT INTO file_change (id, uuid, version, created_at, updated_at,
                    session_file_uuid, session_uuid, prompt_uuid, change_kind)
                VALUES (\(base("fc-1")), 'sf-1', 'sess-1', 'prompt-a', 'edit');
                """)
        }
        return queue
    }

    func testM0002PreservesDataAndMapsStatuses() throws {
        let queue = try makeV1Fixture()
        let idsBefore = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT uuid, id FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["id"] as Int64) }
        }

        try Migrations.migrator.migrate(queue)

        try queue.read { db in
            // Row counts: the CASCADE children and the NO-ACTION referrer all survive.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_active_kbite"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_change"), 1)

            // Status mapping: clarified → done; draft/clarifying untouched.
            let statuses = try Row.fetchAll(db, sql: "SELECT uuid, status, version FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["status"] as String, $0["version"] as Int64) }
            XCTAssertEqual(statuses[0].0, "prompt-a"); XCTAssertEqual(statuses[0].1, "done")
            XCTAssertEqual(statuses[1].0, "prompt-b"); XCTAssertEqual(statuses[1].1, "draft")
            XCTAssertEqual(statuses[2].0, "prompt-c"); XCTAssertEqual(statuses[2].1, "clarifying")
            // Versions copied verbatim (rebuild is not a write).
            XCTAssertEqual(statuses[0].2, 3)

            // uuid→id PAIRS preserved (counts/sums are invariant under the
            // permutation an id-less copy produces — verified failure mode).
            let idsAfter = try Row.fetchAll(db, sql: "SELECT uuid, id FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["id"] as Int64) }
            XCTAssertEqual(idsBefore.map { "\($0.0):\($0.1)" }, idsAfter.map { "\($0.0):\($0.1)" })

            // Child FK clauses still reference prompt, not a rebuild artifact.
            for child in ["prompt_artifact", "prompt_active_kbite", "file_change"] {
                let sql = try String.fetchOne(
                    db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [child]) ?? ""
                XCTAssertTrue(sql.contains("REFERENCES prompt(uuid)") || sql.contains("REFERENCES prompt (uuid)"),
                              "\(child) FK clause lost the prompt reference: \(sql)")
                XCTAssertFalse(sql.contains("prompt_new"), "\(child) references the rebuild table")
            }

            // Index + UNIQUEs regenerated.
            let indexNames = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'prompt'")
            XCTAssertTrue(indexNames.contains("idx_prompt_session_uuid"))
            let promptSql = try String.fetchOne(
                db, sql: "SELECT sql FROM sqlite_master WHERE name = 'prompt'") ?? ""
            XCTAssertTrue(promptSql.contains("UNIQUE(session_uuid, code)"))
            XCTAssertTrue(promptSql.contains("UNIQUE(session_uuid, seq)"))
            XCTAssertTrue(promptSql.contains("'architecting'"))

            // sqlite_sequence stays monotonic (max id was 3 before and after).
            let seqValue = try Int.fetchOne(
                db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'prompt'")
            XCTAssertEqual(seqValue, 3)

            // New tables exist and daemon_config is seeded.
            for table in ["clarification_summary", "clarification", "architecture_summary",
                          "architecture_persistence_change", "architecture_persistence_field_change",
                          "architecture_general_change", "daemon_config"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [table]), 1, "missing table \(table)")
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daemon_config"), 4)

            // Ledger + FK health. The full migrator runs every registered
            // migration, so the ledger tracks currentSchemaVersion — and the
            // m0002 row itself must exist (it is the legacy epoch).
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 2"), 1)
            let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            XCTAssertTrue(violations.isEmpty, "foreign_key_check reported \(violations.count) violations")
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    func testM0002AgainstLiveDbCopy() throws {
        // Point GMCC_TEST_LIVE_DB_COPY at a COPY of ~/gmcc/gmcc.db (never the
        // live file) to prove the migration against real accumulated data.
        guard let path = ProcessInfo.processInfo.environment["GMCC_TEST_LIVE_DB_COPY"] else {
            throw XCTSkip("GMCC_TEST_LIVE_DB_COPY not set")
        }
        let store = try Store(path: path)
        let before: (prompts: Int, artifacts: Int, clarified: Int, uuidIds: [String]) =
            try store.dbQueue.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'clarified'") ?? -1,
                 try String.fetchAll(db, sql: "SELECT uuid || ':' || id FROM prompt ORDER BY uuid"))
            }

        try store.migrate()

        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt"), before.prompts)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact"), before.artifacts)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'done'"),
                before.clarified)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'clarified'"), 0)
            XCTAssertEqual(
                try String.fetchAll(db, sql: "SELECT uuid || ':' || id FROM prompt ORDER BY uuid"),
                before.uuidIds)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// m0004 is pure ADD — no rebuild, no data motion. Assert the five report
    /// tables + their FTS mirrors/triggers exist, the CHECKs hold, and the
    /// `_ad` triggers keep the mirrors synced through an FK cascade delete
    /// (the recursive_triggers contract).
    func testM0004AddsReportTablesWithSyncedFtsMirrors() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0004-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let store = try Store(path: dbPath)
        try store.migrate()

        try store.dbQueue.write { db in
            for table in ["exploration_summary", "exploration_key_file", "exploration_finding",
                          "review_summary", "review_finding"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [table]), 1, "missing table \(table)")
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: ["\(table)_fts"]), 1, "missing FTS mirror for \(table)")
                for suffix in ["ai", "ad", "au"] {
                    XCTAssertEqual(
                        try Int.fetchOne(db, sql:
                            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?",
                            arguments: ["\(table)_\(suffix)"]), 1, "missing trigger \(table)_\(suffix)")
                }
            }
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)

            // Minimal chain + one summary + one finding.
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'r', 'r', 'r', 'p/r');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'r_1', 'r_1', '/tmp/r', 'p/r/i');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active', 'p/r/i/s');
                INSERT INTO prompt (uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES ('prompt-x', 0, '\(now)', '\(now)', 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                INSERT INTO exploration_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, status, overview)
                VALUES ('exs-1', 0, '\(now)', '\(now)', 'prompt-x', 'exploring', '');
                INSERT INTO exploration_finding (uuid, version, created_at, updated_at,
                    exploration_summary_uuid, kind, title, body, agent_name, finding_rating)
                VALUES ('exf-1', 0, '\(now)', '\(now)', 'exs-1', 'other', 'searchable finding title',
                        'searchable finding body', 'tester', NULL);
                """)

            // The rating CHECK: out-of-range refused, NULL allowed (above).
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO exploration_finding (uuid, version, created_at, updated_at,
                    exploration_summary_uuid, kind, title, body, agent_name, finding_rating)
                VALUES ('exf-bad', 0, '\(now)', '\(now)', 'exs-1', 'other', 't', 'b', 'a', 1000)
                """))
            // review_summary: complete requires a verdict.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO review_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, status, verdict, overview)
                VALUES ('rvs-bad', 0, '\(now)', '\(now)', 'prompt-x', 'complete', NULL, '')
                """))

            // FTS mirror is live…
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM exploration_finding_fts WHERE exploration_finding_fts MATCH 'searchable'"), 1)
            // …and stays synced through the prompt-delete FK cascade.
            try db.execute(sql: "DELETE FROM prompt WHERE uuid = 'prompt-x'")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exploration_summary"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exploration_finding"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM exploration_finding_fts WHERE exploration_finding_fts MATCH 'searchable'"), 0)

            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }
}
