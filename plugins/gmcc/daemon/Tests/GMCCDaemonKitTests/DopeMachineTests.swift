import XCTest
import GRDB
@testable import GMCCDaemonKit

final class DopeMachineTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-machine-\(UUID().uuidString).db").path
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

    // MARK: - Helpers

    @discardableResult
    private func initScope(prompt: String? = nil, code: String = "gmcc",
                           clone: Bool? = nil) throws -> DopeScopeResponse {
        try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: prompt, code: code, name: "GMCC",
            description: "model", cloneFromSessionBase: clone))
    }

    @discardableResult
    private func addNode(_ level: DopeLevel, parent: String,
                         _ fields: DopeNodeFields) throws -> DopeNodeResponse {
        try store.dopeNodeAdd(DopeNodeAddRequest(level: level, parentUuid: parent, fields: fields))
    }

    private func buildSmallTree(scopeUuid: String) throws -> (domain: String, entity: String,
                                                              enumUuid: String, property: String) {
        let domain = try addNode(.domain, parent: scopeUuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        let en = try addNode(.enumeration, parent: domain.uuid,
                             DopeNodeFields(code: "status", name: "Status"))
        try addNode(.option, parent: en.uuid, DopeNodeFields(code: "active", name: "Active"))
        let property = try addNode(.property, parent: entity.uuid,
                                   DopeNodeFields(code: "id", name: "Id",
                                                  dataType: .uuid, nullable: false,
                                                  isUnique: true))
        return (domain.uuid, entity.uuid, en.uuid, property.uuid)
    }

    // MARK: - Init

    func testInitIsIdempotentAndDerivesScopeType() throws {
        let first = try initScope()
        XCTAssertTrue(first.created)
        XCTAssertEqual(first.scope.scopeType, "SESSION_BASE")
        XCTAssertEqual(first.scope.revision, 0)

        let again = try initScope()
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.scope.uuid, first.scope.uuid)

        let promptScope = try initScope(prompt: "prompt-a")
        XCTAssertTrue(promptScope.created)
        XCTAssertEqual(promptScope.scope.scopeType, "PROMPT")
    }

    func testCloneFromSessionBaseCopiesTheTree() throws {
        let base = try initScope()
        _ = try buildSmallTree(scopeUuid: base.scope.uuid)
        // Plus a relationship property to prove the two-pass insert clones.
        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let entityUuid = tree.domains[0].entities[0].identity.uuid
        try addNode(.property, parent: entityUuid,
                    DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                   relatedPropertyUuid: tree.domains[0].entities[0]
                                       .properties[0].identity.uuid))

        let cloned = try initScope(prompt: "prompt-a", clone: true)
        XCTAssertTrue(cloned.created)
        let promptTree = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).tree
        XCTAssertEqual(promptTree.identity.uuid, cloned.scope.uuid)
        XCTAssertEqual(promptTree.domains.count, 1)
        XCTAssertEqual(promptTree.domains[0].entities[0].properties.count, 2)
        // Cloned rows are new rows.
        XCTAssertNotEqual(promptTree.domains[0].identity.uuid, tree.domains[0].identity.uuid)
        // The relationship ref re-resolved inside the clone.
        let owner = promptTree.domains[0].entities[0].properties.first { $0.body.code == "owner" }
        XCTAssertEqual(owner?.body.relatedPropertyRef, "core.user.id")
    }

    // MARK: - Get fallback

    func testGetFallsBackToSessionBase() throws {
        _ = try initScope()
        let viaPrompt = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a"))
        XCTAssertEqual(viaPrompt.resolvedVia, "session_base")

        _ = try initScope(prompt: "prompt-a")
        let direct = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a"))
        XCTAssertEqual(direct.resolvedVia, "prompt")
    }

    // MARK: - List (v12)

    func testListReturnsSessionBaseScopesOnly() throws {
        _ = try initScope(code: "gmcc")
        _ = try initScope(code: "alpha")
        _ = try initScope(prompt: "prompt-a", code: "gmcc")

        let scopes = try store.dopeList(DopeListRequest(sessionUuid: "sess-1")).scopes
        XCTAssertEqual(scopes.map(\.code), ["alpha", "gmcc"], "ORDER BY code")
        XCTAssertTrue(scopes.allSatisfy { $0.scopeType == "SESSION_BASE" })
    }

    func testListWithPromptReturnsPromptScopesOnlyNoUnion() throws {
        _ = try initScope(code: "gmcc")
        let promptScope = try initScope(prompt: "prompt-a", code: "gmcc").scope

        let scopes = try store.dopeList(
            DopeListRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).scopes
        XCTAssertEqual(scopes.map(\.uuid), [promptScope.uuid])
        XCTAssertEqual(scopes.first?.scopeType, "PROMPT")
    }

    func testListOfAnUninitializedTargetIsAnEmptyListNotAnError() throws {
        XCTAssertEqual(try store.dopeList(DopeListRequest(sessionUuid: "sess-1")).scopes, [])
        XCTAssertEqual(try store.dopeList(
            DopeListRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).scopes, [])
    }

    func testListRejectsUnknownUuids() throws {
        assertNotFound("session") { try self.store.dopeList(DopeListRequest(sessionUuid: "nope")) }
        assertNotFound("prompt") {
            try self.store.dopeList(DopeListRequest(sessionUuid: "sess-1", promptUuid: "nope"))
        }
    }

    // MARK: - Get absence discrimination (v12)

    func testGetOnRealButUninitializedTargetIsSummaryAbsent() throws {
        for req in [DopeGetRequest(sessionUuid: "sess-1"),
                    DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")] {
            XCTAssertThrowsError(try store.dopeGet(req)) { error in
                guard case StoreError.dopeScopeAbsent = error else {
                    return XCTFail("wrong error: \(error)")
                }
                let payload = (error as! StoreError).errorPayload
                XCTAssertEqual(payload.code, .summaryAbsent)
                XCTAssertTrue(payload.message.contains("gm dope init"), payload.message)
            }
        }
    }

    func testGetRejectsUnknownUuidsBeforeAbsence() throws {
        _ = try initScope()   // a scope EXISTS, so only the guards can fire
        assertNotFound("session") { try self.store.dopeGet(DopeGetRequest(sessionUuid: "nope")) }
        assertNotFound("prompt") {
            try self.store.dopeGet(DopeGetRequest(sessionUuid: "sess-1", promptUuid: "nope"))
        }
    }

    private func assertNotFound(
        _ entity: String, file: StaticString = #filePath, line: UInt = #line,
        _ body: () throws -> Any
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case StoreError.notFound(let got, _) = error else {
                return XCTFail("wrong error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(got, entity, file: file, line: line)
        }
    }

    // MARK: - Revision vs version split

    func testNodeMutationsBumpRevisionNotScopeVersion() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let after = try store.dbQueue.read { db in
            try self.store.fetchDopeScope(db, uuid: scope.uuid)!
        }
        XCTAssertEqual(after.revision, 5, "five node adds = five revision bumps")
        XCTAssertEqual(after.version, 0, "scope optimistic-lock version must not move")

        let update = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: ids.entity, expectedVersion: 0,
            fields: DopeNodeFields(name: "Person")))
        XCTAssertEqual(update.revision, 6)
        XCTAssertEqual(update.version, 1)
    }

    // MARK: - Field ownership + shape

    func testFieldOwnershipMatrix() throws {
        let scope = try initScope().scope
        XCTAssertThrowsError(try addNode(.domain, parent: scope.uuid,
                                         DopeNodeFields(code: "x", name: "X",
                                                        dataType: .text))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("has no field"), detail)
        }
        // entity code 'enums' is reserved.
        let domain = try addNode(.domain, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        XCTAssertThrowsError(try addNode(.entity, parent: domain.uuid,
                                         DopeNodeFields(code: "enums", name: "Enums")))
        // property requires data-type; enum data-type requires enum uuid.
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        XCTAssertThrowsError(try addNode(.property, parent: entity.uuid,
                                         DopeNodeFields(code: "p", name: "P")))
        XCTAssertThrowsError(try addNode(.property, parent: entity.uuid,
                                         DopeNodeFields(code: "p", name: "P",
                                                        dataType: .enumeration)))
    }

    func testChainRelationshipRefused() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let rel = try addNode(.property, parent: ids.entity,
                              DopeNodeFields(code: "owner", name: "Owner",
                                             dataType: .relationship,
                                             relatedPropertyUuid: ids.property))
        XCTAssertThrowsError(try addNode(
            .property, parent: ids.entity,
            DopeNodeFields(code: "chain", name: "Chain", dataType: .relationship,
                           relatedPropertyUuid: rel.uuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("chain"), detail)
        }
    }

    func testCrossScopeRefRefused() throws {
        let base = try initScope().scope
        let baseIds = try buildSmallTree(scopeUuid: base.uuid)
        let promptScope = try initScope(prompt: "prompt-a").scope
        let domain = try addNode(.domain, parent: promptScope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        XCTAssertThrowsError(try addNode(
            .property, parent: entity.uuid,
            DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                           enumUuid: baseIds.enumUuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("different dope scope"), detail)
        }
    }

    // MARK: - Deletes

    func testDeleteEnumRefusedWhileReferencedThenAllowed() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let state = try addNode(.property, parent: ids.entity,
                                DopeNodeFields(code: "state", name: "State",
                                               dataType: .enumeration,
                                               enumUuid: ids.enumUuid))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: ids.enumUuid, expectedVersion: 0))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("core.user.state"), detail)
        }
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .property, nodeUuid: state.uuid, expectedVersion: 0))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: ids.enumUuid, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.options, 1)
    }

    func testDomainDeleteHandlesInternalRelationships() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        // Internal referrers (relationship + enum property in the same
        // domain) must not block the ordered delete.
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                       relatedPropertyUuid: ids.property))
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                                       enumUuid: ids.enumUuid))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .domain, nodeUuid: ids.domain, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.properties, 3)
        try store.dbQueue.read { db in
            for table in ["dope_domain", "dope_domain_entity", "dope_domain_enum",
                          "dope_domain_enum_option", "dope_domain_entity_property"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0)
            }
        }
    }

    /// Review fix [20]: a same-entity relationship pair must not trip the
    /// RESTRICT FK during entity-delete's property sweep (the target row has
    /// the lower rowid and is scanned first by a naive bulk DELETE).
    func testEntityDeleteWithSameEntityRelationshipPair() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                       relatedPropertyUuid: ids.property))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .entity, nodeUuid: ids.entity, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.properties, 2)
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM dope_domain_entity_property"), 0)
        }
    }

    func testScopeDeleteDeferred() throws {
        let scope = try initScope().scope
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .scope, nodeUuid: scope.uuid, expectedVersion: 0)))
    }

    func testDeleteVersionGuard() throws {
        let scope = try initScope().scope
        let domain = try addNode(.domain, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .domain, nodeUuid: domain.uuid, expectedVersion: 7))) { error in
            guard case StoreError.versionConflict = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Events

    func testDopeChangeEventsAreDurable() throws {
        let scope = try initScope().scope
        _ = try addNode(.domain, parent: scope.uuid, DopeNodeFields(code: "core", name: "Core"))
        let kinds = try store.dbQueue.read { db in
            try String.fetchAll(
                db, sql: "SELECT kind FROM daemon_event WHERE subject_uuid = ?",
                arguments: [scope.uuid])
        }
        XCTAssertEqual(kinds, ["DOPE_CHANGE", "DOPE_CHANGE"], "init + node_add")
    }
}
