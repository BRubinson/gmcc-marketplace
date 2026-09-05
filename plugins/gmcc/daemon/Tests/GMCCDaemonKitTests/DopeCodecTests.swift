import XCTest
@testable import GMCCDaemonKit

final class DopeCodecTests: XCTestCase {

    // MARK: - Fixture

    private func makeTree() -> DopeScopeTree {
        func identity(_ n: Int) -> DopeNodeIdentity {
            DopeNodeIdentity(uuid: "uuid-\(n)", version: Int64(n),
                             createdAt: "2026-09-05T00:00:00Z",
                             updatedAt: "2026-09-05T00:00:00Z")
        }
        let statusEnum = DopeEnumNode(
            identity: identity(10),
            body: DopeEnumBody(code: "status", name: "Status", description: "Lifecycle",
                               sortOrder: 0, repoRepresentativeFile: "Sources/Status.swift"),
            options: [
                DopeOptionNode(identity: identity(11),
                               body: DopeOptionBody(code: "active", name: "Active",
                                                    description: "", sortOrder: 0)),
                DopeOptionNode(identity: identity(12),
                               body: DopeOptionBody(code: "done", name: "Done",
                                                    description: "", sortOrder: 1)),
            ])
        let user = DopeEntityNode(
            identity: identity(20),
            body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil),
            properties: [
                DopePropertyNode(identity: identity(21),
                                 body: DopePropertyBody(
                                    code: "id", name: "Id", description: "", sortOrder: 0,
                                    dataType: "uuid", nullable: false, isUnique: true,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relatedPropertyRef: nil)),
                DopePropertyNode(identity: identity(22),
                                 body: DopePropertyBody(
                                    code: "state", name: "State", description: "", sortOrder: 1,
                                    dataType: "enum", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: "core.enums.status", relatedPropertyRef: nil)),
            ])
        let post = DopeEntityNode(
            identity: identity(30),
            body: DopeEntityBody(code: "post", name: "Post", entityType: "MODEL",
                                 description: "", sortOrder: 1,
                                 repoRepresentativeFile: nil),
            properties: [
                DopePropertyNode(identity: identity(31),
                                 body: DopePropertyBody(
                                    code: "author", name: "Author", description: "", sortOrder: 0,
                                    dataType: "relationship", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relatedPropertyRef: "core.user.id")),
                DopePropertyNode(identity: identity(32),
                                 body: DopePropertyBody(
                                    code: "title", name: "Title", description: "", sortOrder: 1,
                                    dataType: "text", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: 200,
                                    enumRef: nil, relatedPropertyRef: nil)),
            ])
        let core = DopeDomainNode(
            identity: identity(2),
            body: DopeDomainBody(code: "core", name: "Core", description: "", sortOrder: 0),
            entities: [user, post], enums: [statusEnum])
        return DopeScopeTree(
            identity: identity(1),
            body: DopeScopeBody(code: "gmcc", name: "GMCC", description: "The model"),
            sessionUuid: "sess-1", promptUuid: nil,
            scopeType: "SESSION_BASE", revision: 3, domains: [core])
    }

    // MARK: - Parity + determinism

    func testDocumentRoundTripIsIdentity() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        let mainData = try DopeDocumentCodec.encoder.encode(bundle.main)
        let decodedMain = try DopeDocumentCodec.decoder.decode(DopeMainDocument.self, from: mainData)
        XCTAssertEqual(decodedMain, bundle.main)

        for file in bundle.domainFiles {
            let data = try DopeDocumentCodec.encoder.encode(file)
            let decoded = try DopeDocumentCodec.decoder.decode(DopeDomainFileDocument.self, from: data)
            XCTAssertEqual(decoded, file)
        }
    }

    func testEncodingIsByteDeterministic() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        let a = try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0])
        let b = try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0])
        XCTAssertEqual(a, b)
    }

    /// The uuid ban is structural: no document type has anywhere to put one.
    /// Belt-and-braces: the encoded bytes must not contain the fixture uuids
    /// or a "uuid" key at all.
    func testNoUuidAppearsInAnyDocument() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        var blobs = [try DopeDocumentCodec.encoder.encode(bundle.main)]
        blobs += try bundle.domainFiles.map { try DopeDocumentCodec.encoder.encode($0) }
        for blob in blobs {
            let text = String(decoding: blob, as: UTF8.self)
            XCTAssertFalse(text.contains("uuid-"), "row uuid leaked into a document")
            // Key position only — `"data_type" : "uuid"` is a legal VALUE.
            XCTAssertFalse(text.contains("\"uuid\" :"), "a uuid key leaked into a document")
        }
    }

    /// Wire node flattening: identity + body share one flat JSON object and
    /// the snake_case round trip preserves everything (the CodingKeys
    /// single-word constraint this file exists to guard).
    func testWireTreeRoundTripUnderWireCodec() throws {
        let tree = makeTree()
        let data = try WireCodec.encoder.encode(tree)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"sort_order\""), "snake_case strategy not applied")
        XCTAssertFalse(text.contains("\"body\""), "body wrapper leaked — flattening broken")
        XCTAssertFalse(text.contains("\"identity\""), "identity wrapper leaked — flattening broken")
        let decoded = try WireCodec.decoder.decode(DopeScopeTree.self, from: data)
        XCTAssertEqual(decoded, tree)
    }

    // MARK: - Validator

    func testValidatorAcceptsTheFixture() throws {
        try DopeValidator.validate(makeTree())
    }

    func testValidatorCollectsEveryError() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        // Break several things at once: bad code, dangling enum ref, version
        // mismatch, wrong map path.
        let badProperty = DopePropertyDocument(body: DopePropertyBody(
            code: "BadCode", name: "x", description: "", sortOrder: 0,
            dataType: "enum", nullable: true, isUnique: false,
            autoIncrement: nil, textCharLimit: nil,
            enumRef: "core.enums.missing", relatedPropertyRef: nil))
        let entity = DopeEntityDocument(
            body: DopeEntityBody(code: "extra", name: "Extra", entityType: "MODEL",
                                 description: "", sortOrder: 9,
                                 repoRepresentativeFile: nil),
            properties: [badProperty])
        let broken = DopeDomainFileDocument(
            version: bundle.main.version + 1,   // mismatch
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + [entity],
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(
            main: DopeMainDocument(
                version: bundle.main.version,
                scopeType: bundle.main.scopeType,
                scope: bundle.main.scope,
                domains: ["core": "../escape.doped.json"]),
            domainFiles: [broken])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertGreaterThanOrEqual(error.errors.count, 4,
                                        "expected aggregated errors, got: \(error.errors)")
        }
    }

    func testValidatorRejectsReservedEntityCodeAndChainRefs() throws {
        let tree = makeTree()
        var bundle = DopeProjection.documents(from: tree)
        let enumsEntity = DopeEntityDocument(
            body: DopeEntityBody(code: "enums", name: "Enums", entityType: "MODEL",
                                 description: "", sortOrder: 5, repoRepresentativeFile: nil),
            properties: [])
        let chain = DopePropertyDocument(body: DopePropertyBody(
            code: "chain", name: "Chain", description: "", sortOrder: 7,
            dataType: "relationship", nullable: true, isUnique: false,
            autoIncrement: nil, textCharLimit: nil,
            enumRef: nil, relatedPropertyRef: "core.post.author"))   // author is a relationship
        let user = bundle.domainFiles[0].entities[0]
        let patchedUser = DopeEntityDocument(body: user.body,
                                             properties: user.properties + [chain])
        let file = DopeDomainFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: [patchedUser, bundle.domainFiles[0].entities[1], enumsEntity],
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertTrue(error.errors.contains { $0.contains("reserved") },
                          "missing reserved-code error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("itself a relationship") },
                          "missing chain-ref error: \(error.errors)")
        }
    }

    func testCodeValidation() throws {
        try DopeCode.validateCode("valid_code_1", field: "code")
        for bad in ["", "Upper", "1lead", "trail_", "dou__ble", "has-dash", "has.dot",
                    String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try DopeCode.validateCode(bad, field: "code"),
                                 "'\(bad)' should be rejected")
        }
    }

    func testRefParsing() throws {
        XCTAssertEqual(try DopeCode.parseRef("core.user.id", field: "ref"),
                       .property(domain: "core", entity: "user", property: "id"))
        XCTAssertEqual(try DopeCode.parseRef("core.enums.status", field: "ref"),
                       .enumType(domain: "core", enumCode: "status"))
        for bad in ["core.user", "core.user.id.extra", "core..id", "Core.user.id"] {
            XCTAssertThrowsError(try DopeCode.parseRef(bad, field: "ref"))
        }
    }
}
