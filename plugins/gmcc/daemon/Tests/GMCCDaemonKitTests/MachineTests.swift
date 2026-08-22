import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Drives the clarification and architecture state machines plus the
/// lifecycle-v2 prompt gates on a real migrated Store — every legal edge,
/// every illegal edge, the legacy bypass, and the no-synthetic-rows rule.
final class MachineTests: XCTestCase {
    private var store: Store!
    private var dbPath: String!
    private var promptUuid: String!
    private var sessionUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("machine-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        // Minimal context chain + one post-m0002 prompt.
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'repo_1', 'repo_1', '/tmp/machine-repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');
                """)
        }
        sessionUuid = "sess-1"
        promptUuid = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "machine_test", detail: "d")).uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func promptVersion() throws -> Int64 {
        try store.getPrompt(PromptGetRequest(promptUuid: promptUuid)).prompt.version
    }

    private func setStatus(_ status: PromptStatus) throws -> PromptRow {
        try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(), status: status))
    }

    func testFullLifecycleWithGatesAndMachines() throws {
        // draft → clarifying creates the summary (create-on-enter).
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        var summary = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        XCTAssertEqual(summary.status, "building")

        // Gate refuses architecting while the clarification is incomplete.
        XCTAssertThrowsError(try setStatus(.architecting))

        // Ask two questions (one pre-answered), seal, answer, finalize.
        let q1 = try store.clarifyAsk(ClarifyAskRequest(
            summaryUuid: summary.uuid, category: .goal, question: "What is the goal?")).clarification
        _ = try store.clarifyAsk(ClarifyAskRequest(
            summaryUuid: summary.uuid, category: .yeetType, question: "Detected type?",
            answer: "swift wire lowering", answerSource: .botInferred))
        // Answer while building is refused.
        XCTAssertThrowsError(try store.clarifyAnswer(ClarifyAnswerRequest(
            clarificationUuid: q1.uuid, expectedVersion: q1.version, answer: "early")))
        summary = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version)).summary
        XCTAssertEqual(summary.status, "answering")
        // Ask after seal is refused.
        XCTAssertThrowsError(try store.clarifyAsk(ClarifyAskRequest(
            summaryUuid: summary.uuid, category: .detail, question: "late?")))
        // Finalize with an open question is refused.
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version,
            refinedGoal: "g", refinedDetail: "d")))
        _ = try store.clarifyAnswer(ClarifyAnswerRequest(
            clarificationUuid: q1.uuid, expectedVersion: q1.version, answer: "ship it"))
        // Stale expected-version conflicts.
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version - 1,
            refinedGoal: "g", refinedDetail: "d")))
        let finalized = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version,
            refinedGoal: "Refined goal.", refinedDetail: "Refined detail."))
        XCTAssertEqual(finalized.summary.status, "complete")
        // CONTENT_LOCKED exemption: prompt.goal now carries the refined goal.
        XCTAssertEqual(finalized.prompt.goal, "Refined goal.")

        // Reopen (complete → answering) then re-finalize.
        let reopened = try store.clarifyReopen(ClarifyReopenRequest(
            summaryUuid: summary.uuid, expectedVersion: finalized.summary.version)).summary
        XCTAssertEqual(reopened.status, "answering")
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: reopened.version,
            refinedGoal: "Refined goal v2.", refinedDetail: "Refined detail v2."))

        // clarifying → architecting now passes and creates the arch summary.
        XCTAssertEqual(try setStatus(.architecting).status, "architecting")
        var arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        XCTAssertFalse(arch.uuid.isEmpty)

        // Gate refuses implementing while the architecture is unapproved.
        XCTAssertThrowsError(try setStatus(.implementing))

        // Author the architecture: body, one persistence change + field, one general change.
        arch = try store.archSummarize(ArchSummarizeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version, body: "Concept.")).summary
        let persist = try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "Widget",
            filePath: "/tmp/machine-repo/Sources/Widget.swift", reasonBrief: "new model")).change
        XCTAssertEqual(persist.filePath, "Sources/Widget.swift") // normalized
        _ = try store.archFieldAdd(ArchFieldAddRequest(
            persistenceChangeUuid: persist.uuid, fieldName: "owner_uuid", dataType: "TEXT",
            changeReason: "link", changePurpose: "join", nullable: false,
            isForeignKey: true, fkTarget: "owner.uuid", isIndexed: true))
        // FK without target refused.
        XCTAssertThrowsError(try store.archFieldAdd(ArchFieldAddRequest(
            persistenceChangeUuid: persist.uuid, fieldName: "bad", dataType: "TEXT",
            changeReason: "r", changePurpose: "p", nullable: true, isForeignKey: true)))
        _ = try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/UI.swift",
            reasonBrief: "render", changeDepth: .pseudo, changeCode: "draw()"))
        // Absolute-outside-instance path refused.
        XCTAssertThrowsError(try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "/etc/passwd",
            reasonBrief: "nope", changeDepth: .pseudo, changeCode: "x")))

        // propose → (revise → propose) → approve; approved is terminal.
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        // Adds are sealed after propose.
        XCTAssertThrowsError(try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/Late.swift",
            reasonBrief: "late", changeDepth: .pseudo, changeCode: "x")))
        arch = try store.archRevise(ArchReviseRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        XCTAssertEqual(arch.status, "drafting")
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        arch = try store.archApprove(ArchApproveRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        XCTAssertEqual(arch.status, "approved")
        XCTAssertThrowsError(try store.archRevise(ArchReviseRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)))

        // architecting → implementing now passes; then the skip edge.
        XCTAssertEqual(try setStatus(.implementing).status, "implementing")
        XCTAssertEqual(try setStatus(.done).status, "done")
        XCTAssertThrowsError(try setStatus(.reviewing)) // done is terminal
    }

    func testIllegalPromptEdges() throws {
        XCTAssertThrowsError(try setStatus(.architecting)) // non-adjacent
        XCTAssertThrowsError(try setStatus(.done))         // jump to terminal
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        XCTAssertThrowsError(try setStatus(.draft))        // backward
    }

    func testLegacyPromptBypassesGatesWithNoSyntheticRows() throws {
        // Backdate the prompt before the m0002 epoch.
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE prompt SET created_at = '2020-01-01T00:00:00Z' WHERE uuid = ?",
                arguments: [promptUuid!])
        }
        // Walks every state with NO backing rows created.
        for status in [PromptStatus.clarifying, .architecting, .implementing, .reviewing, .done] {
            XCTAssertEqual(try setStatus(status).status, status.rawValue)
        }
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clarification_summary"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM architecture_summary"), 0)
        }
    }

    func testArchGetComparisonBuckets() throws {
        _ = try setStatus(.clarifying)
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        let sealed = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version)).summary
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: clarify.uuid, expectedVersion: sealed.version,
            refinedGoal: "g", refinedDetail: "d"))
        _ = try setStatus(.architecting)
        let arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        _ = try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "M", filePath: "Sources/Model.swift",
            reasonBrief: "model first"))
        _ = try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/View.swift",
            reasonBrief: "view", changeDepth: .draft, changeCode: "v"))

        // Record file changes: the persistence path, then an unplanned path.
        let project = ProjectContext(
            gitRepoName: "repo", code: "repo", name: "repo",
            ckfsRelativeStoragePath: "projects/repo", uuid: "proj-1")
        let instance = InstanceContext(
            code: "repo_1", name: "repo_1", absoluteFileSystemPath: "/tmp/machine-repo",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1", uuid: "inst-1")
        let session = SessionContext(
            code: "main", name: "main",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1/sessions/main", uuid: "sess-1")
        _ = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            promptUuid: promptUuid, relativePath: "Sources/Model.swift",
            changeKind: .edit, ranges: [ChangeRange(lineStart: 1, lineEnd: 5)]))
        _ = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            promptUuid: promptUuid, relativePath: "Sources/Surprise.swift",
            changeKind: .create, ranges: []))

        let got = try store.archGet(ArchGetRequest(promptUuid: promptUuid))
        // Planned + touched.
        XCTAssertEqual(got.persistenceChanges[0].implementation.fileChangeCount, 1)
        // Planned + untouched.
        XCTAssertEqual(got.generalChanges[0].implementation.fileChangeCount, 0)
        // Touched + unplanned.
        XCTAssertEqual(got.unplannedChanges.map(\.path), ["Sources/Surprise.swift"])
        // Persistence-first: general side untouched ⇒ audit vacuous.
        XCTAssertNil(got.orderingRespected)
    }
}
