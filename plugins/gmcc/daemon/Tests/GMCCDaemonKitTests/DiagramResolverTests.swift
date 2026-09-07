import XCTest
@testable import GMCCDaemonKit

/// Resolver semantics, pinned in plain XCTest with zero SwiftUI: composed
/// transforms, sibling-only z with the (elementZ, code) tie-break,
/// deterministic FNV-1a colors, ghost injection, the composed-base property
/// union, and the FK edge pass.
final class DiagramResolverTests: XCTestCase {

    // MARK: - Fixtures

    private func identity(_ uuid: String) -> DopeNodeIdentity {
        DopeNodeIdentity(uuid: uuid, version: 0, createdAt: "t", updatedAt: "t")
    }

    private func element(
        _ uuid: String, code: String, payload: DiagramElementPayload,
        centerX: Double = 0, centerY: Double = 0, elementZ: Double = 0,
        scale: Double = 1, children: [DiagramElementNode] = []
    ) -> DiagramElementNode {
        DiagramElementNode(
            identity: identity(uuid),
            base: DiagramElementBase(code: code, name: code, description: "",
                                     sortOrder: 0, centerX: centerX, centerY: centerY,
                                     elementZ: elementZ, scale: scale),
            payload: payload, children: children)
    }

    private func tree(_ elements: [DiagramElementNode],
                      sessionUuid: String? = "sess-1") -> DiagramTree {
        DiagramTree(identity: identity("d-1"), tier: "SESSION", projectUuid: "proj-1",
                    instanceUuid: "inst-1", sessionUuid: sessionUuid, promptUuid: nil,
                    code: "main", name: "Main", description: "", gmccDiagramPath: nil,
                    revision: 0, elements: elements)
    }

    /// A dope tree: core.user (relationship → core.profile.id), core.profile,
    /// base.timestamps (BASE_COMPOSABLE) composed by core.user.
    private func dopeTree() -> DopeScopeTree {
        func property(_ code: String, dataType: String = "text", nullable: Bool = true,
                      isUnique: Bool = false, relatedRef: String? = nil,
                      baseOrigin: String? = nil) -> DopePropertyNode {
            DopePropertyNode(identity: identity("p-\(code)"),
                             body: DopePropertyBody(
                                code: code, name: code, description: "", sortOrder: 0,
                                dataType: dataType, nullable: nullable, isUnique: isUnique,
                                autoIncrement: nil, textCharLimit: nil, enumRef: nil,
                                relatedPropertyRef: relatedRef, baseOriginRef: baseOrigin))
        }
        let user = DopeEntityNode(
            identity: identity("e-user"),
            body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil,
                                 baseComposableRef: "base.timestamps"),
            properties: [
                property("id", dataType: "uuid", nullable: false, isUnique: true),
                property("profile", dataType: "relationship",
                         relatedRef: "core.profile.id"),
            ])
        let profile = DopeEntityNode(
            identity: identity("e-profile"),
            body: DopeEntityBody(code: "profile", name: "Profile", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [property("id", dataType: "uuid", nullable: false)])
        let timestamps = DopeEntityNode(
            identity: identity("e-ts"),
            body: DopeEntityBody(code: "timestamps", name: "Timestamps",
                                 entityType: "BASE_COMPOSABLE", description: "",
                                 sortOrder: 0, repoRepresentativeFile: nil,
                                 baseComposableRef: nil),
            properties: [property("created_at", dataType: "datetime", nullable: false)])
        let core = DopeDomainNode(
            identity: identity("dom-core"),
            body: DopeDomainBody(code: "core", name: "Core", description: "", sortOrder: 0),
            entities: [user, profile], enums: [])
        let base = DopeDomainNode(
            identity: identity("dom-base"),
            body: DopeDomainBody(code: "base", name: "Base", description: "", sortOrder: 0),
            entities: [timestamps], enums: [])
        return DopeScopeTree(identity: identity("scope-1"),
                             body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                             sessionUuid: "sess-1", promptUuid: nil,
                             scopeType: "SESSION_BASE", revision: 7,
                             domains: [core, base])
    }

    private func context() -> DiagramDopeContext {
        DiagramDopeContext(entries: [
            "gmcc": DiagramDopeContext.Entry(tree: dopeTree(), resolvedVia: "session_base"),
        ])
    }

    // MARK: - Transforms

    func testTransformsComposeParentSpaceCentersAndMultiplicativeScale() {
        let stroke = element("e-s", code: "s", payload: .drawingStroke(
            DrawingStrokePayload(strokeWidth: 2,
                                 vertices: [DiagramVertex(x: 0, y: 0),
                                            DiagramVertex(x: 10, y: 0)])),
                             centerX: 20, centerY: 0, scale: 2)
        let layer = element("e-l", code: "l", payload: .drawingLayer(DrawingLayerPayload()),
                            centerX: 100, centerY: 50, scale: 2, children: [stroke])
        let resolved = DiagramResolver.resolve(tree([layer]), dope: DiagramDopeContext())

        guard case .stroke(let resolvedStroke) = resolved.topLevel[0].children[0].kind else {
            return XCTFail("expected stroke kind")
        }
        // Stroke center = layer center + child offset * layer scale
        //              = (100 + 20*2, 50 + 0) = (140, 50).
        // Vertex 1 = center + v * effScale(4) = (140 + 40, 50).
        XCTAssertEqual(resolvedStroke.points[0], CGPoint(x: 140, y: 50))
        XCTAssertEqual(resolvedStroke.points[1], CGPoint(x: 180, y: 50))
        // Stroke width scales with the ACCUMULATED transform (2 * 4 = 8).
        XCTAssertEqual(resolvedStroke.lineWidth, 8)
    }

    // MARK: - Sibling z + tie-break

    func testSiblingOrderIsElementZThenCode() {
        let a = element("e-a", code: "bbb", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 1)
        let b = element("e-b", code: "aaa", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 1)
        let c = element("e-c", code: "zzz", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 0)
        let resolved = DiagramResolver.resolve(tree([a, b, c]), dope: DiagramDopeContext())
        XCTAssertEqual(resolved.topLevel.map(\.uuid), ["e-c", "e-b", "e-a"],
                       "z first, code tie-break — deterministic paint order")
    }

    // MARK: - Deterministic color

    func testDomainHueIsStableAcrossCallsAndDistinctishAcrossCodes() {
        XCTAssertEqual(DiagramPalette.domainHue("core"), DiagramPalette.domainHue("core"))
        XCTAssertNotEqual(DiagramPalette.domainHue("core"), DiagramPalette.domainHue("base"))
        let hue = DiagramPalette.domainHue("core")
        XCTAssertGreaterThanOrEqual(hue, 0)
        XCTAssertLessThan(hue, 1)
    }

    // MARK: - Entity cards + base union + ghosts

    func testEntityCardUnionsComposedBaseProperties() throws {
        let model = try XCTUnwrap(DiagramResolver.entityCard("core.user", in: dopeTree()))
        XCTAssertEqual(model.entityName, "User")
        XCTAssertEqual(model.domainCode, "core")
        let names = model.rows.map(\.name)
        XCTAssertEqual(names, ["id", "profile", "created_at"],
                       "own properties first, composed-base union appended")
        // Badges: id is NN+UQ; profile is FK; created_at came from the base.
        XCTAssertEqual(model.rows[0].badges, ["NN", "UQ"])
        XCTAssertTrue(model.rows[1].badges.contains("FK"))
        XCTAssertTrue(model.rows[2].badges.contains("B"))
    }

    func testGhostInjection() {
        let entityKnown = element("e-known", code: "known", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let entityMissing = element("e-missing", code: "missing", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.no_such")), centerX: 400)
        let scope = element("e-scope", code: "sc", payload: .dopeScope(
            DopeScopePayload(dopeScopeCode: "gmcc")),
                            children: [entityKnown, entityMissing])
        let danglingScope = element("e-ghost", code: "gs", payload: .dopeScope(
            DopeScopePayload(dopeScopeCode: "nope")), centerX: 900,
                                    children: [element("e-ghost-child", code: "gc",
                                                       payload: .dopeEntity(DopeEntityPayload(
                                                        entityCode: "core.user")))])
        let resolved = DiagramResolver.resolve(tree([scope, danglingScope]), dope: context())

        let scopeElement = resolved.topLevel.first { $0.uuid == "e-scope" }!
        guard case .scopeCard(let card) = scopeElement.kind else {
            return XCTFail("expected scope card")
        }
        XCTAssertEqual(card.resolvedVia, "session_base")
        guard case .entityCard = scopeElement.children.first(where: { $0.uuid == "e-known" })!.kind
        else { return XCTFail("expected entity card") }
        guard case .absentEntity(let missingCode) =
                scopeElement.children.first(where: { $0.uuid == "e-missing" })!.kind
        else { return XCTFail("expected absentEntity ghost") }
        XCTAssertEqual(missingCode, "core.no_such")

        let ghostScope = resolved.topLevel.first { $0.uuid == "e-ghost" }!
        guard case .absentScope(let ghostCode) = ghostScope.kind else {
            return XCTFail("expected absentScope ghost")
        }
        XCTAssertEqual(ghostCode, "nope")
        // Children of an unresolved scope ghost too — no tree to look into.
        guard case .absentEntity = ghostScope.children[0].kind else {
            return XCTFail("expected the child of a ghost scope to ghost as well")
        }
    }

    // MARK: - FK edge pass

    func testRelationshipPropertiesBecomeEdgesBetweenRenderedCards() {
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
        let scope = element("e-scope", code: "sc", payload: .dopeScope(
            DopeScopePayload(dopeScopeCode: "gmcc")),
                            children: [userCard, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        XCTAssertEqual(edge.fromElementUuid, "e-user")
        XCTAssertEqual(edge.toElementUuid, "e-profile")
        XCTAssertEqual(edge.propertyRef, "core.user.profile")
        XCTAssertLessThan(edge.from.x, edge.to.x, "edge leaves the side facing the target")
    }

    func testEdgeToUnrenderedEntityIsSimplyOmitted() {
        // Only the user card is on the canvas — the relationship's target has
        // no card, so no edge (and no error).
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")))
        let scope = element("e-scope", code: "sc", payload: .dopeScope(
            DopeScopePayload(dopeScopeCode: "gmcc")), children: [userCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())
        XCTAssertTrue(resolved.edges.isEmpty)
    }

    // MARK: - Bounds

    func testContentBoundsCoverEveryFrameAndAnEmptyDiagramGetsAFallback() {
        let empty = DiagramResolver.resolve(tree([]), dope: DiagramDopeContext())
        XCTAssertFalse(empty.contentBounds.isNull)
        XCTAssertGreaterThan(empty.contentBounds.width, 0)

        let far = element("e-far", code: "far", payload: .drawingLayer(DrawingLayerPayload()),
                          centerX: 2000, centerY: -1500)
        let resolved = DiagramResolver.resolve(tree([far]), dope: DiagramDopeContext())
        XCTAssertTrue(resolved.contentBounds.contains(CGPoint(x: 2000, y: -1500)))
    }
}
