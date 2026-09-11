import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0023's whole contract: the (owner, step) upsert-reset semantics, the
/// partial-unique NULL-prompt case, the server-side staleness stamp and its
/// computed drift/ghost reporting, the per-instance activation registry
/// (never a last-writer-wins session pointer), the auto-attribute ladder,
/// and the deterministic active-briefing resolution spawned agents rely on.
final class BriefingTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0023-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
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
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-b")), 'sess-1', 2, 'p2', 'two', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Helpers

    private func makeScope(revision: Int64 = 5) throws {
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO dope_scope (id, uuid, version, created_at, updated_at,
                    project_uuid, instance_uuid, session_uuid, prompt_uuid, scope_type,
                    code, name, description, revision)
                VALUES (NULL, 'scope-1', 0, '\(now)', '\(now)',
                    'proj-1', 'inst-1', 'sess-1', NULL, 'SESSION_INSTANCE',
                    'gmcc', 'GMCC', '', \(revision));
                INSERT INTO dope_persistence (id, uuid, version, created_at, updated_at,
                    dope_scope_uuid, code, name, description, sort_order, content_revision)
                VALUES (NULL, 'dom-1', 0, '\(now)', '\(now)', 'scope-1', 'agentics', 'Agentics', '', 0, 0);
                INSERT INTO dope_persistence_entity (id, uuid, version, created_at, updated_at,
                    dope_persistence_uuid, code, name, entity_type, description, sort_order)
                VALUES (NULL, 'ent-1', 0, '\(now)', '\(now)', 'dom-1', 'agent_briefing', 'Agent Briefing', 'MODEL', '', 0);
                """)
        }
    }

    private func bumpScope(to revision: Int64) throws {
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE dope_scope SET revision = ? WHERE uuid = 'scope-1'",
                arguments: [revision])
        }
    }

    // MARK: - Open / reset / uniqueness

    func testOpenCreatesThenResetsInsteadOfDuplicating() throws {
        let first = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        XCTAssertTrue(first.created)
        XCTAssertEqual(first.briefing.status, "building")
        XCTAssertEqual(first.briefing.sessionUuid, "sess-1")

        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: first.briefing.uuid,
            expectedVersion: first.briefing.version,
            dopeRefs: ["agentics.agent_briefing"]))

        let second = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        XCTAssertFalse(second.created)
        XCTAssertEqual(second.briefing.uuid, first.briefing.uuid)
        XCTAssertEqual(second.briefing.status, "building")
        // m0025: reset TRUNCATES the ref children — a step's briefing is its
        // CURRENT briefing, stale refs must not leak into the rebuilt one.
        XCTAssertTrue(second.briefing.dopeRefs.isEmpty)
    }

    func testExactlyOneOwnerIsEnforced() throws {
        XCTAssertThrowsError(try store.briefingOpen(
            BriefingOpenRequest(
                promptUuid: "prompt-a", sessionUuid: "sess-1", briefingForStep: "initial")))
        XCTAssertThrowsError(try store.briefingOpen(
            BriefingOpenRequest(briefingForStep: "initial")))
        XCTAssertThrowsError(try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "bogus_step")))
    }

    func testTaskOwnedRowsAreUniquePerSessionAndStep() throws {
        let task = try store.briefingOpen(
            BriefingOpenRequest(sessionUuid: "sess-1", briefingForStep: "initial"))
        XCTAssertTrue(task.created)
        XCTAssertNil(task.briefing.promptUuid)

        // A second task open on the same step resets, never duplicates
        // (SQLite UNIQUE would admit two NULL-prompt rows without the
        // partial index; the reset path plus the index both hold the line).
        let again = try store.briefingOpen(
            BriefingOpenRequest(sessionUuid: "sess-1", briefingForStep: "initial"))
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.briefing.uuid, task.briefing.uuid)

        // And it coexists with a prompt-owned row for the same step.
        let promptOwned = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        XCTAssertTrue(promptOwned.created)
    }

    func testPromptOwnedOpenClaimsActivation() throws {
        // Review finding 5f68f01d: briefings are consumed in draft/
        // architecting phases, before set-status implementing would claim —
        // so OPEN claims for the calling instance, making the zero-uuid
        // ladder succeed from the very first phase.
        _ = try store.briefingOpen(BriefingOpenRequest(
            promptUuid: "prompt-a", briefingForStep: "initial",
            clientKey: "test-instance-open"))
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try self.store.resolveActivePrompt(
                    db, sessionUuid: "sess-1", clientKey: "test-instance-open"),
                "prompt-a")
        }
        // Task-owned opens claim nothing (no prompt to claim). (Task rows
        // coexist with prompt rows on the same step via the partial pair.)
        _ = try store.briefingOpen(BriefingOpenRequest(
            sessionUuid: "sess-1", briefingForStep: "initial",
            clientKey: "test-instance-task"))
        try store.dbQueue.read { db in
            let keys = try self.store.fetchActivations(db, sessionUuid: "sess-1")
                .map(\.clientKey)
            XCTAssertFalse(keys.contains("test-instance-task"))
        }
    }

    func testDeadClaudeClaimsAreFilteredAndEvicted() throws {
        try store.dbQueue.write { db in
            // pid 1 is launchd — alive, but its start time is never 12345,
            // so this parses as a claude key whose instance is gone.
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "claude:1:12345")
        }
        try store.dbQueue.read { db in
            // Filtered out of resolution (read path)...
            XCTAssertNil(
                try self.store.resolveActivePrompt(db, sessionUuid: "sess-1", clientKey: nil))
        }
        try store.dbQueue.write { db in
            // ...and physically evicted on the next claim (write path).
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-b", clientKey: "test-instance-live")
            let keys = try self.store.fetchActivations(db, sessionUuid: "sess-1")
                .map(\.clientKey)
            XCTAssertEqual(keys, ["test-instance-live"])
        }
    }

    // MARK: - Complete: server stamp, kbite denormalization, staleness

    func testCompleteStampsScopeRevisionServerSideAndGetComputesDrift() throws {
        try makeScope(revision: 5)
        let open = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        let ready = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: open.briefing.uuid,
            expectedVersion: open.briefing.version,
            dopeRefs: ["agentics.agent_briefing", "agentics.vanished_entity"]))
        XCTAssertEqual(ready.briefing.status, "ready")
        XCTAssertEqual(ready.briefing.dopeScopeUuid, "scope-1")
        XCTAssertEqual(ready.briefing.dopeScopeRevision, 5)

        let fresh = try store.briefingGet(
            BriefingGetRequest(briefingUuid: open.briefing.uuid))
        XCTAssertFalse(fresh.staleness.drifted)
        // The dangling dot-path reports as a ghost, never an error.
        XCTAssertEqual(fresh.staleness.ghostDotPaths, ["agentics.vanished_entity"])

        try bumpScope(to: 9)
        let stale = try store.briefingGet(
            BriefingGetRequest(briefingUuid: open.briefing.uuid))
        XCTAssertTrue(stale.staleness.drifted)
        XCTAssertEqual(stale.staleness.stampedRevision, 5)
        XCTAssertEqual(stale.staleness.currentRevision, 9)
    }

    func testCompleteRefusesDanglingFileChangeRefAndGetAbsentIsTyped() throws {
        let open = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        // A file-change child carries a REAL FK — a dangling ref is a typed
        // refusal (unlike kbite refs, which drop ghost-tolerantly).
        XCTAssertThrowsError(try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: open.briefing.uuid,
            expectedVersion: open.briefing.version,
            fileChangeRefs: ["no-such-change"])))

        XCTAssertThrowsError(
            try store.briefingGet(BriefingGetRequest(promptUuid: "prompt-b"))
        ) { error in
            guard case StoreError.summaryAbsent = error else {
                return XCTFail("expected summaryAbsent, got \(error)")
            }
        }
    }

    // MARK: - Activation registry (per Claude instance, never per session)

    func testConcurrentInstancesKeepSeparateActivations() throws {
        try store.dbQueue.write { db in
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "test-instance-one")
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-b", clientKey: "test-instance-two")
        }
        try store.dbQueue.read { db in
            // Both prompts are active at once — the whole point.
            XCTAssertEqual(try self.store.fetchActivations(db, sessionUuid: "sess-1").count, 2)
            // Each instance resolves ITS OWN prompt.
            XCTAssertEqual(
                try self.store.resolveActivePrompt(
                    db, sessionUuid: "sess-1", clientKey: "test-instance-one"), "prompt-a")
            XCTAssertEqual(
                try self.store.resolveActivePrompt(
                    db, sessionUuid: "sess-1", clientKey: "test-instance-two"), "prompt-b")
            // A keyless caller with TWO claims gets nothing — never a guess.
            XCTAssertNil(
                try self.store.resolveActivePrompt(db, sessionUuid: "sess-1", clientKey: nil))
        }
        // Releasing one leaves the single-claim fallback unambiguous again.
        try store.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM prompt_activation WHERE prompt_uuid = 'prompt-b'")
        }
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try self.store.resolveActivePrompt(db, sessionUuid: "sess-1", clientKey: nil),
                "prompt-a")
        }
    }

    func testReclaimReplacesBothSidesOldRows() throws {
        try store.dbQueue.write { db in
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "test-instance-one")
            // Same instance moves to another prompt: old claim replaced.
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-b", clientKey: "test-instance-one")
        }
        try store.dbQueue.read { db in
            let rows = try self.store.fetchActivations(db, sessionUuid: "sess-1")
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].promptUuid, "prompt-b")
        }
    }

    // MARK: - Deterministic active-briefing resolution

    func testActiveResolutionFollowsCallerClaimThenTaskFallback() throws {
        // Two instances, two prompts, two briefings for the same step.
        let a = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: a.briefing.uuid, expectedVersion: a.briefing.version,
            dopeRefs: ["for.a"]))
        let b = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-b", briefingForStep: "initial"))
        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: b.briefing.uuid, expectedVersion: b.briefing.version,
            dopeRefs: ["for.b"]))
        try store.dbQueue.write { db in
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "test-instance-one")
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-b", clientKey: "test-instance-two")
        }
        // Each instance's zero-uuid lookup lands on ITS prompt's briefing.
        let forA = try store.briefingGet(BriefingGetRequest(
            sessionUuid: "sess-1", step: "initial", clientKey: "test-instance-one"))
        XCTAssertEqual(forA.briefing.dopeRefs.map(\.dopeCode), ["for.a"])
        let forB = try store.briefingGet(BriefingGetRequest(
            sessionUuid: "sess-1", step: "initial", clientKey: "test-instance-two"))
        XCTAssertEqual(forB.briefing.dopeRefs.map(\.dopeCode), ["for.b"])

        // An unclaimed instance with ambiguous claims falls to the task row.
        let task = try store.briefingOpen(
            BriefingOpenRequest(sessionUuid: "sess-1", briefingForStep: "initial"))
        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: task.briefing.uuid,
            expectedVersion: task.briefing.version,
            dopeRefs: ["task.owned"]))
        let fallback = try store.briefingGet(BriefingGetRequest(
            sessionUuid: "sess-1", step: "initial", clientKey: "test-instance-three"))
        XCTAssertEqual(fallback.briefing.uuid, task.briefing.uuid)
    }

    func testStubIsInstanceScopedAndHookSafe() throws {
        // Nothing anywhere: empty stub, never an error.
        let empty = try store.briefingStub(BriefingStubRequest(
            agentType: "gmcc:code-explorer", sessionUuid: "sess-1", clientKey: "test-instance-nine"))
        XCTAssertTrue(empty.stub.contains("session_uuid: sess-1"))

        let open = try store.briefingOpen(
            BriefingOpenRequest(promptUuid: "prompt-a", briefingForStep: "initial"))
        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: open.briefing.uuid,
            expectedVersion: open.briefing.version,
            dopeRefs: ["agentics.agent_briefing"]))
        try store.dbQueue.write { db in
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "test-instance-one")
        }
        let stub = try store.briefingStub(BriefingStubRequest(
            agentType: "gmcc:code-explorer", sessionUuid: "sess-1", clientKey: "test-instance-one"))
        XCTAssertTrue(stub.stub.contains("active_prompt_uuid: prompt-a"))
        XCTAssertTrue(stub.stub.contains(open.briefing.uuid))
        XCTAssertTrue(stub.stub.contains("gm briefing get --briefing-uuid"))
        XCTAssertLessThanOrEqual(stub.stub.utf8.count, 2048)
        // A role with no mapped step still gets the uuid block, no briefing line.
        let reranker = try store.briefingStub(BriefingStubRequest(
            agentType: "gmcc:finding-reranker", sessionUuid: "sess-1", clientKey: "test-instance-one"))
        XCTAssertFalse(reranker.stub.contains("briefing_uuid"))
    }

    // MARK: - Auto-attribute ladder on file changes

    func testFileChangeAutoAttributeUsesCallerClaim() throws {
        try store.dbQueue.write { db in
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-a", clientKey: "test-instance-one")
            try self.store.claimActivation(
                db, sessionUuid: "sess-1", promptUuid: "prompt-b", clientKey: "test-instance-two")
        }
        let project = ProjectContext(
            gitRepoName: "repo", code: "repo", name: "repo",
            ckfsRelativeStoragePath: "projects/repo")
        let instance = InstanceContext(
            code: "repo_1", name: "repo_1", absoluteFileSystemPath: "/tmp/repo",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1")
        let session = SessionContext(
            code: "main", name: "main", ckfsRelativeStoragePath: "x")

        func add(clientKey: String?, auto: Bool) throws -> String? {
            let response = try store.addFileChange(FileChangeAdd(
                project: project, instance: instance, session: session,
                relativePath: "Sources/File.swift", changeKind: .edit, ranges: [],
                autoAttribute: auto ? true : nil, clientKey: clientKey))
            return try store.dbQueue.read { db in
                try String.fetchOne(
                    db, sql: "SELECT prompt_uuid FROM file_change WHERE uuid = ?",
                    arguments: [response.fileChangeUuid])
            }
        }

        // Caller's own claim wins.
        XCTAssertEqual(try add(clientKey: "test-instance-two", auto: true), "prompt-b")
        // Ambiguous keyless auto-attribution stays unattributed.
        XCTAssertNil(try add(clientKey: nil, auto: true))
        // Without the opt-in flag, nothing changes at all.
        XCTAssertNil(try add(clientKey: "test-instance-two", auto: false))
    }

    // MARK: - Set-status side effect

    func testSetStatusClaimsAndReleasesActivation() throws {
        // Walk prompt-a to implementing with a client key.
        var version: Int64 = 0
        for status in [PromptStatus.clarifying, .architecting, .implementing] {
            // clarifying → architecting is gated on a complete clarification;
            // drive the summaries the minimal legal way.
            if status == .architecting {
                try store.dbQueue.write { db in
                    try db.execute(sql: """
                        UPDATE clarification_summary SET status = 'complete'
                        WHERE prompt_uuid = 'prompt-a'
                        """)
                }
            }
            if status == .implementing {
                try store.dbQueue.write { db in
                    try db.execute(sql: """
                        UPDATE architecture_summary SET status = 'approved'
                        WHERE prompt_uuid = 'prompt-a'
                        """)
                }
            }
            let row = try store.setPromptStatus(PromptSetStatusRequest(
                promptUuid: "prompt-a", expectedVersion: version, status: status,
                clientKey: "test-instance-one"))
            version = row.version
        }
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try self.store.resolveActivePrompt(
                    db, sessionUuid: "sess-1", clientKey: "test-instance-one"), "prompt-a")
        }
        // done releases the prompt's claim (whoever calls it).
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: "prompt-a", expectedVersion: version, status: .done))
        try store.dbQueue.read { db in
            XCTAssertTrue(try self.store.fetchActivations(db, sessionUuid: "sess-1").isEmpty)
        }
    }
}
