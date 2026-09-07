import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The fk-by-code binding contract: read-time resolution through the dope
/// ladder against the DIAGRAM's own session/prompt context with resolved_via
/// surfaced, ghosts as a legal state (including all-ghosts above SESSION
/// tier), and — critically — dope deletes NEVER blocked by diagrams.
final class DiagramBindingTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-binding-\(UUID().uuidString).db").path
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
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @discardableResult
    private func makeScope(prompt: String? = nil, code: String = "gmcc") throws -> DopeScopeResponse {
        try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: prompt, code: code, name: "GMCC"))
    }

    private func addScopeElement(_ diagramUuid: String, code: String) throws -> DiagramNodeResponse {
        try store.diagramNodeAdd(DiagramNodeAddRequest(
            diagramUuid: diagramUuid,
            add: DiagramElementAdd(payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: code)))))
    }

    func testBindingResolvesSessionBaseAndSurfacesVia() throws {
        let scope = try makeScope()
        let diagram = try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: "main", name: "Main")).diagram
        try addScopeElement(diagram.uuid, code: "gmcc")

        let get = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(get.bindings.count, 1)
        XCTAssertEqual(get.bindings[0].resolvedVia, "session_base")
        XCTAssertEqual(get.bindings[0].scopeUuid, scope.scope.uuid)
        XCTAssertEqual(get.bindings[0].dopeRevision, scope.scope.revision)
    }

    func testPromptTierDiagramPrefersPromptScope() throws {
        let base = try makeScope()
        let promptScope = try makeScope(prompt: "prompt-a")
        let diagram = try store.diagramInit(DiagramInitRequest(
            promptUuid: "prompt-a", code: "main", name: "Main")).diagram
        try addScopeElement(diagram.uuid, code: "gmcc")

        let get = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(get.bindings[0].resolvedVia, "prompt",
                       "same-coded PROMPT scope must win over the SESSION_BASE")
        XCTAssertEqual(get.bindings[0].scopeUuid, promptScope.scope.uuid)
        XCTAssertNotEqual(get.bindings[0].scopeUuid, base.scope.uuid)
    }

    func testDanglingCodeIsALegalGhostNeverAnError() throws {
        let diagram = try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: "main", name: "Main")).diagram
        try addScopeElement(diagram.uuid, code: "no_such_scope")
        let get = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(get.bindings.count, 1)
        XCTAssertNil(get.bindings[0].resolvedVia, "absent = nil resolvedVia, not an error")
        XCTAssertNil(get.bindings[0].scopeUuid)
    }

    func testProjectTierDiagramResolvesAllGhosts() throws {
        try makeScope()  // a real scope exists, but there's no session context
        let diagram = try store.diagramInit(DiagramInitRequest(
            projectUuid: "proj-1", code: "main", name: "Main")).diagram
        try addScopeElement(diagram.uuid, code: "gmcc")
        let get = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid))
        XCTAssertNil(get.bindings[0].resolvedVia,
                     "no session in the owner chain ⇒ ghosts by construction")
    }

    func testDopeDeleteSucceedsWithBoundDiagramsPresent() throws {
        let scope = try makeScope()
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.scope.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))

        let diagram = try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: "main", name: "Main")).diagram
        let scopeElement = try addScopeElement(diagram.uuid, code: "gmcc")
        try store.diagramNodeAdd(DiagramNodeAddRequest(
            diagramUuid: diagram.uuid,
            add: DiagramElementAdd(
                parentElementUuid: scopeElement.uuid,
                payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")))))

        // A picture must never block domain evolution: deleting the bound
        // entity (and then its whole domain) succeeds; the diagram survives
        // and its binding becomes a ghost.
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .entity, nodeUuid: entity.uuid, expectedVersion: 0))
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid, expectedVersion: 0))

        let get = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(get.tree.elements.count, 1)
        XCTAssertEqual(get.tree.elements[0].children.count, 1,
                       "the dope_entity element row survives as a ghost binding")
        // The scope itself still resolves (only its contents went away).
        XCTAssertEqual(get.bindings[0].resolvedVia, "session_base")
    }
}
