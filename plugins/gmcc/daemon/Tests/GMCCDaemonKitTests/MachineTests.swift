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
            summaryUuid: summary.uuid, category: .detail, question: "Which integration point?",
            answer: "the wire codec", answerSource: .botInferred))
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

    /// m0005 removed the legacy tier: create-on-enter is now universal, so
    /// draft → clarifying always materialises a clarification summary and the
    /// clarifying → architecting gate always has a summary to check. The old
    /// backdate-the-prompt bypass has no remaining code path.
    func testCreateOnEnterIsUniversalWithNoLegacyBypass() throws {
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE prompt SET created_at = '2020-01-01T00:00:00Z' WHERE uuid = ?",
                arguments: [promptUuid!])
        }
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clarification_summary"), 1)
        }
        // An old created_at buys no gate bypass: the summary is still building.
        XCTAssertThrowsError(try setStatus(.architecting))
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

    func testExplorationMachine() throws {
        // Open works at draft (Phase 2 timing) and is idempotent; prompt
        // status never creates one (skip-to-done stays legal — asserted at
        // the end of testReviewMachine on a fresh prompt).
        let opened = try store.exploreOpen(ExploreOpenRequest(promptUuid: promptUuid))
        XCTAssertTrue(opened.created)
        XCTAssertEqual(opened.summary.status, "exploring")
        XCTAssertFalse(try store.exploreOpen(ExploreOpenRequest(promptUuid: promptUuid)).created)
        let summaryUuid = opened.summary.uuid

        // Key files dedupe as upsert-ignore.
        let kf1 = try store.exploreKeyFileAdd(ExploreKeyFileAddRequest(
            summaryUuid: summaryUuid, filePath: "Sources/A.swift"))
        XCTAssertTrue(kf1.created)
        let kf2 = try store.exploreKeyFileAdd(ExploreKeyFileAddRequest(
            summaryUuid: summaryUuid, filePath: "Sources/A.swift"))
        XCTAssertFalse(kf2.created)
        XCTAssertEqual(kf1.keyFile.uuid, kf2.keyFile.uuid)

        // Two findings: one pre-rated, one unranked.
        let f1 = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .implementationPattern, title: "pattern",
            body: "body", agentName: "conservative", rating: 40)).finding
        let f2 = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .scopeCreepRisk, title: "risk",
            body: "body", agentName: "aggressive")).finding
        XCTAssertNil(f2.findingRating)

        // Complete refuses while unranked; the rank gate is the enforcement.
        var summary = opened.summary
        XCTAssertThrowsError(try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version, overview: "o")))

        // Batch atomicity: one bad pair (foreign uuid) rejects the whole batch.
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            summaryUuid: summaryUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 10),
                      FindingRating(findingUuid: "not-a-finding", rating: 10)])))
        XCTAssertNil(try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid))
            .findings.first(where: { $0.uuid == f2.uuid })?.findingRating)
        // Duplicate uuids reject too.
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            summaryUuid: summaryUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 10),
                      FindingRating(findingUuid: f2.uuid, rating: 20)])))

        // A good batch lands; unrankedCount hits zero.
        let ranked = try store.exploreRank(ExploreRankRequest(
            summaryUuid: summaryUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 150)]))
        XCTAssertEqual(ranked.unrankedCount, 0)

        // GET partitions at 100: f1 (40) full, f2 (150) stub; --full unhides.
        let got = try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(got.findings.map(\.uuid), [f1.uuid])
        XCTAssertEqual(got.findingStubs.map(\.uuid), [f2.uuid])
        XCTAssertEqual(
            try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid, full: true))
                .findings.count, 2)
        // Rating-range window shifts the partition.
        XCTAssertEqual(
            try store.exploreGet(ExploreGetRequest(
                promptUuid: promptUuid, ratingMin: 100, ratingMax: 200)).findings.map(\.uuid),
            [f2.uuid])

        // Complete carries the overview (its only write path); rank refused
        // after complete; reopen re-arms and preserves everything.
        summary = try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid)).summary
        summary = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version,
            overview: "the narrative")).summary
        XCTAssertEqual(summary.status, "complete")
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            summaryUuid: summaryUuid,
            ratings: [FindingRating(findingUuid: f1.uuid, rating: 5)])))
        summary = try store.exploreReopen(ExploreReopenRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version)).summary
        XCTAssertEqual(summary.status, "exploring")
        XCTAssertEqual(summary.overview, "the narrative")
        // A post-reopen finding inserts unranked and re-blocks complete.
        _ = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .other, title: "new", body: "b",
            agentName: "primary"))
        XCTAssertThrowsError(try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version, overview: "v2")))
    }

    func testReviewMachine() throws {
        let opened = try store.reviewOpen(ReviewOpenRequest(promptUuid: promptUuid))
        let summaryUuid = opened.summary.uuid
        XCTAssertEqual(opened.summary.status, "reviewing")

        // line_end without line_start refused; located finding lands.
        XCTAssertThrowsError(try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .correctnessBug, title: "t", body: "b",
            lineEnd: 5, agentName: "a")))
        let f1 = try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .correctnessBug, title: "bug",
            body: "b", filePath: "Sources/A.swift", lineStart: 3, lineEnd: 9,
            agentName: "conservative", rating: 10)).finding
        let f2 = try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .simplification, title: "nit",
            body: "b", agentName: "pragmatic", rating: 400)).finding

        // Complete requires the verdict and carries overview + verdict.
        var summary = try store.reviewGet(ReviewGetRequest(promptUuid: promptUuid)).summary
        summary = try store.reviewComplete(ReviewCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version,
            overview: "review narrative", verdict: .approvedWithNits)).summary
        XCTAssertEqual(summary.verdict, "approved_with_nits")

        // Resolve works AFTER complete (the fix loop), stubs keep status,
        // lateral corrections allowed, never back to open.
        let resolved = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: f1.version, status: .fixed)).finding
        XCTAssertEqual(resolved.status, "fixed")
        let corrected = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: resolved.version, status: .accepted)).finding
        XCTAssertEqual(corrected.status, "accepted")
        XCTAssertThrowsError(try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: corrected.version, status: .open)))
        let got = try store.reviewGet(ReviewGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(got.findingStubs.first(where: { $0.uuid == f2.uuid })?.status, "open")

        // Resolve survives a reopen mid-fix-loop (the ungated design).
        summary = try store.reviewReopen(ReviewReopenRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version)).summary
        XCTAssertEqual(summary.status, "reviewing")
        _ = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f2.uuid, expectedVersion: f2.version, status: .wontFix))

        // SUMMARY_ABSENT on a fresh prompt: no review summary, and prompt
        // transitions never created one behind our back (skip-to-done
        // legality).
        let fresh = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "fresh", detail: "d")).uuid
        do {
            _ = try store.reviewGet(ReviewGetRequest(promptUuid: fresh))
            XCTFail("expected summaryAbsent")
        } catch let StoreError.summaryAbsent(entity, _) {
            XCTAssertEqual(entity, "review")
        }
    }
}
