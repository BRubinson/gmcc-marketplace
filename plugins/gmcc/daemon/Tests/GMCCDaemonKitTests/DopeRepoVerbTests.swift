import XCTest
import GRDB
@testable import GMCCDaemonKit

/// End-to-end over the three whole-tree repo verbs against a temp git
/// checkout: init → build tree → write-repo → read-repo → ingest, plus both
/// directions of the revision gates.
final class DopeRepoVerbTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true)
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-repo-\(UUID().uuidString).db").path
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
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1',
                        '\(repoRoot.path)', 'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(at: repoRoot)
    }

    private func makeScopeWithTree() throws -> DopeScopeRow {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        let en = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .enumeration, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "status", name: "Status")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .option, parentUuid: en.uuid,
            fields: DopeNodeFields(code: "active", name: "Active")))
        let id = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .uuid,
                                   nullable: false, isUnique: true)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                                   enumUuid: en.uuid)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                   relatedPropertyUuid: id.uuid)))
        return try store.dbQueue.read { db in
            try self.store.fetchDopeScope(db, uuid: scope.uuid)!
        }
    }

    func testWriteReadIngestRoundTrip() throws {
        let scope = try makeScopeWithTree()
        XCTAssertEqual(scope.revision, 7)

        let written = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(written.revision, 7)
        XCTAssertTrue(written.filesWritten.contains(".gmcc/dope/main.doped.json"))

        let read = try store.dopeReadRepo(DopeReadRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(read.onDiskRevision, 7)
        XCTAssertEqual(read.dbRevision, 7)
        XCTAssertEqual(read.drift, false)

        // Hand-bump the on-disk version to revision + 1 and ingest.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let bumped = DopeDocumentBundle(
            main: DopeMainDocument(version: 8, scopeType: read.bundle.main.scopeType,
                                   scope: read.bundle.main.scope,
                                   domains: read.bundle.main.domains),
            domainFiles: read.bundle.domainFiles.map {
                DopePersistenceFileDocument(version: 8, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            })
        _ = try sandbox.writeAtomically(bumped)

        let treeBefore = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.scope.revision, 8)
        XCTAssertEqual(ingested.counts.properties, 3)

        // Content round-trips (identity churns — the locked consequence).
        let treeAfter = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        XCTAssertEqual(DopeProjection.documents(from: treeAfter).domainFiles.map(\.body),
                       DopeProjection.documents(from: treeBefore).domainFiles.map(\.body))
        XCTAssertEqual(treeAfter.domains[0].entities[0].properties.map(\.body),
                       treeBefore.domains[0].entities[0].properties.map(\.body))
        XCTAssertNotEqual(treeAfter.domains[0].identity.uuid,
                          treeBefore.domains[0].identity.uuid,
                          "ingest mints fresh rows")
    }

    func testIngestRevisionGateExactlyPlusOne() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))

        // On-disk version == db revision → refused (needs +1).
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.revisionConflict = $0 else {
                return XCTFail("wrong error: \($0)")
            }
        }
        // +2 → refused.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        func stamped(_ version: Int64) -> DopeDocumentBundle {
            DopeDocumentBundle(
                main: DopeMainDocument(version: version, scopeType: read.main.scopeType,
                                       scope: read.main.scope, domains: read.main.domains),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: version, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                })
        }
        _ = try sandbox.writeAtomically(stamped(9))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid)))
        // Exactly +1 → accepted; the same file again → refused (stale).
        _ = try sandbox.writeAtomically(stamped(8))
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid)))
    }

    func testWriteRepoRefusesWhenFilesAreAheadUnlessForced() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))

        // Stamp the files ahead of the db.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeMainDocument(version: 99, scopeType: read.main.scopeType,
                                   scope: read.main.scope, domains: read.main.domains),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: 99, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))

        XCTAssertThrowsError(
            try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.revisionConflict = $0 else {
                return XCTFail("wrong error: \($0)")
            }
        }
        let forced = try store.dopeWriteRepo(
            DopeWriteRepoRequest(scopeUuid: scope.uuid, force: true))
        XCTAssertEqual(forced.revision, 7)
        XCTAssertEqual(sandbox.peekRevision(), 7, "forced write re-stamps the db revision")
    }

    func testReadRepoWithExplicitDirPath() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let read = try store.dopeReadRepo(DopeReadRepoRequest(dirPath: repoRoot.path))
        XCTAssertEqual(read.onDiskRevision, 7)
        XCTAssertNil(read.dbRevision)
        XCTAssertNil(read.drift)
        XCTAssertThrowsError(try store.dopeReadRepo(DopeReadRepoRequest()))
        XCTAssertThrowsError(try store.dopeReadRepo(
            DopeReadRepoRequest(scopeUuid: scope.uuid, dirPath: repoRoot.path)))
    }

    /// Review fix [0]: enum refs are cross-domain-capable and domain files
    /// arrive alphabetically — a property in an EARLY domain referencing an
    /// enum in a LATE domain must survive the whole-tree insert.
    func testIngestWithCrossDomainEnumAndRelationshipRefs() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        // Late-sorting domain holds the enum + target property…
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_shared", name: "Shared")))
        let sharedEntity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "tag", name: "Tag")))
        let sharedId = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: sharedEntity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .uuid, nullable: false)))
        let sharedEnum = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .enumeration, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "kind", name: "Kind")))
        // …and the early-sorting domain references both across.
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "kind", name: "Kind", dataType: .enumeration,
                                   enumUuid: sharedEnum.uuid)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "tag", name: "Tag", dataType: .relationship,
                                   relatedPropertyUuid: sharedId.uuid)))

        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let next = read.main.version + 1
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeMainDocument(version: next, scopeType: read.main.scopeType,
                                   scope: read.main.scope, domains: read.main.domains),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: next, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.counts.domains, 2)

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        let user = core.entities.first { $0.body.code == "user" }!
        XCTAssertEqual(user.properties.first { $0.body.code == "kind" }?.body.enumRef,
                       "zzz_shared.enums.kind")
        XCTAssertEqual(user.properties.first { $0.body.code == "tag" }?.body.relatedPropertyRef,
                       "zzz_shared.tag.id")
    }

    /// Base refs are cross-domain-capable like enum refs: a composer in an
    /// EARLY domain referencing a base in a LATE-sorting domain must survive
    /// the whole-tree insert (pass-3 deferred resolution), and the ref must
    /// round-trip as the same dot-path.
    func testIngestWithCrossDomainBaseRef() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_base", name: "Base")))
        let base = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "base_entity", name: "Base Entity",
                                   entityType: .baseComposable)))
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User",
                                   baseComposableUuid: base.uuid)))

        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let next = read.main.version + 1
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeMainDocument(version: next, scopeType: read.main.scopeType,
                                   scope: read.main.scope, domains: read.main.domains),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: next, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.counts.entities, 2)

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        XCTAssertEqual(core.entities[0].body.baseComposableRef, "zzz_base.base_entity")
        // write-repo after ingest re-encodes the same dot-path.
        let written = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(written.revision, ingested.scope.revision)
        let reread = try sandbox.readBundle().bundle
        let coreFile = reread.domainFiles.first { $0.body.code == "aaa_core" }!
        XCTAssertEqual(coreFile.entities[0].body.baseComposableRef, "zzz_base.base_entity")
    }

    /// The repo pass in miniature: a cross-domain base, a materialized uuid
    /// tagged from it, and a relationship in a third entity targeting the
    /// MATERIALIZED property. Proves insertDopeTree's pass-5 deferred origin
    /// resolution and — via the second ingest — wipeDopeTree's base_origin
    /// NULL-out on a tree that already carries tags.
    func testIngestWithBaseOriginTags() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_base", name: "Base")))
        let base = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "base_entity", name: "Base Entity",
                                   entityType: .baseComposable)))
        let originUuidProp = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: base.uuid,
            fields: DopeNodeFields(code: "uuid", name: "Uuid", dataType: .uuid,
                                   nullable: false, isUnique: true)))
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        let user = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User",
                                   baseComposableUuid: base.uuid)))
        let materialized = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: user.uuid,
            fields: DopeNodeFields(code: "uuid", name: "Uuid", dataType: .uuid,
                                   nullable: false, isUnique: true,
                                   baseOriginPropertyUuid: originUuidProp.uuid)))
        let post = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "post", name: "Post")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: post.uuid,
            fields: DopeNodeFields(code: "author", name: "Author", dataType: .relationship,
                                   relatedPropertyUuid: materialized.uuid)))

        func roundTripOnce() throws {
            _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
            let read = try sandbox.readBundle().bundle
            let next = read.main.version + 1
            _ = try sandbox.writeAtomically(DopeDocumentBundle(
                main: DopeMainDocument(version: next, scopeType: read.main.scopeType,
                                       scope: read.main.scope, domains: read.main.domains),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: next, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                }))
            _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        }
        try roundTripOnce()
        // Second ingest wipes a tree that already carries base_origin tags —
        // the wipe-order regression.
        try roundTripOnce()

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        let userNode = core.entities.first { $0.body.code == "user" }!
        XCTAssertEqual(userNode.properties.first { $0.body.code == "uuid" }?.body.baseOriginRef,
                       "zzz_base.base_entity.uuid")
        let postNode = core.entities.first { $0.body.code == "post" }!
        XCTAssertEqual(postNode.properties.first { $0.body.code == "author" }?
                        .body.relatedPropertyRef,
                       "aaa_core.user.uuid",
                       "relationship must target the MATERIALIZED row, not the base's")
        try store.dbQueue.read { db in
            // The origin resolved to the base's actual row.
            let pair = try Row.fetchOne(db, sql: """
                SELECT p.uuid AS tagged, p.base_origin_property_uuid AS origin
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                WHERE e.code = 'user' AND p.code = 'uuid'
                """)
            let baseRow = try String.fetchOne(db, sql: """
                SELECT p.uuid FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                WHERE e.code = 'base_entity' AND p.code = 'uuid'
                """)
            XCTAssertEqual(pair?["origin"] as String?, baseRow)
        }
    }

    /// Review fixes [65] + [85]: ingest applies hand-edited scope
    /// name/description from main.doped.json, and bumps the scope row's
    /// optimistic-lock version ONLY when those fields actually changed.
    func testIngestScopeMetadataSemantics() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle

        func stamped(_ version: Int64, scopeBody: DopeScopeBody) -> DopeDocumentBundle {
            DopeDocumentBundle(
                main: DopeMainDocument(version: version, scopeType: read.main.scopeType,
                                       scope: scopeBody, domains: read.main.domains),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: version, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                })
        }

        // Pure tree ingest (metadata untouched): version stays.
        _ = try sandbox.writeAtomically(stamped(8, scopeBody: read.main.scope))
        let pure = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(pure.scope.version, scope.version,
                       "a pure tree ingest must not burn the scope's optimistic lock")

        // Hand-edited name: applied, version bumps by exactly 1.
        let edited = DopeScopeBody(code: read.main.scope.code, name: "GMCC Renamed",
                                   description: "hand-edited")
        _ = try sandbox.writeAtomically(stamped(9, scopeBody: edited))
        let renamed = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(renamed.scope.name, "GMCC Renamed")
        XCTAssertEqual(renamed.scope.description, "hand-edited")
        XCTAssertEqual(renamed.scope.version, pure.scope.version + 1)

        // A changed scope CODE is identity, refused.
        let recoded = DopeScopeBody(code: "not_gmcc", name: "x", description: "")
        _ = try sandbox.writeAtomically(stamped(10, scopeBody: recoded))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("wrong error: \($0)")
            }
            XCTAssertTrue(detail.contains("identity"), detail)
        }
    }

    func testStaleInstanceRootFailsLoudly() throws {
        let scope = try makeScopeWithTree()
        try FileManager.default.removeItem(at: repoRoot)
        XCTAssertThrowsError(
            try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("missing or stale"), detail)
            XCTAssertTrue(detail.contains(self.repoRoot.path), detail)
        }
    }
}
