import XCTest
@testable import GMCCDaemonKit

/// Wire-contract regression tests. The exhaustive wire-key contract lives in
/// Fixtures/wire_keys.golden, regenerated and diffed by scripts/wire_keys.py
/// (static walk — no instantiation). These tests cover what a static walk
/// cannot: the two mixed-key survivor types actually decoding correctly under
/// the coder strategies, which is where retained explicit CodingKeys silently
/// nil out sibling Optional fields if the sibling keys are not deleted.
final class WireKeyTests: XCTestCase {

    func testErrorPayloadRoundTripsDaemonProtocolVersion() throws {
        let payload = ErrorPayload(
            code: .protocolMismatch,
            message: "stale daemon",
            daemonProtocolVersion: 6
        )
        let data = try NDJSON.encodeLine(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["code"] as? String, "PROTOCOL_MISMATCH")
        XCTAssertEqual(json["daemon_protocol_version"] as? Int, 6)

        let decoded = try NDJSON.decode(ErrorPayload.self, from: data)
        XCTAssertEqual(decoded.code, .protocolMismatch)
        // The directional-retry landmine: this is nil if ErrorPayload keeps an
        // explicit CodingKeys entry for daemonProtocolVersion alongside codeRaw.
        XCTAssertEqual(decoded.daemonProtocolVersion, 6)
    }

    func testRawEnvelopeHeadRoundTrips() throws {
        let head = RawEnvelopeHead(protocolVersion: 6, typeRaw: "PING", requestId: "r-1")
        let data = try NDJSON.encodeLine(head)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "PING")
        XCTAssertEqual(json["protocol_version"] as? Int, 6)
        XCTAssertEqual(json["request_id"] as? String, "r-1")

        let decoded = try NDJSON.decode(RawEnvelopeHead.self, from: data)
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertEqual(decoded.protocolVersion, 6)
        XCTAssertEqual(decoded.requestId, "r-1")
    }

    // MARK: - caller_role (amendment A7)

    /// THE FAIL-OPEN TRIPWIRE. A bare `case callerRoleRaw` in
    /// RawEnvelopeHead's CodingKeys expects the wire key `caller_role_raw`
    /// under .convertFromSnakeCase, never matches the `caller_role` the
    /// encoder emits, and decodes to nil — and because absent means
    /// `.primary`, every agent caller would read as the primary and the door
    /// would refuse nothing. The raw value must be the CAMEL "callerRole",
    /// exactly like `typeRaw = "type"`.
    ///
    /// Deliberately driven through the REAL WireCodec (NDJSON.encodeLine →
    /// NDJSON.decode), not a hand-rolled encoder: the bug lives entirely in
    /// the key STRATEGY, so an encoder that does not apply the strategy
    /// cannot see it.
    func testCallerRoleRoundTripsThroughTheRealCodec() throws {
        let request = RequestEnvelope(
            type: .reviewRank, requestId: "r-2", callerRole: .agent, payload: EmptyPayload())
        let data = try NDJSON.encodeLine(request)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            json["caller_role"] as? String, "agent",
            "the wire key is caller_role — NOT caller_role_raw, NOT callerRole")

        let head = try NDJSON.decode(RawEnvelopeHead.self, from: data)
        XCTAssertEqual(head.callerRoleRaw, "agent", "caller_role decoded to nil — A7's fail-open bug")
        XCTAssertEqual(head.callerRole, .agent)
    }

    /// Absent ⇒ `.primary` is what makes the field additive, and a primary
    /// request must stay BYTE-FOR-BYTE what it was before the field existed.
    func testPrimaryRequestOmitsCallerRoleEntirely() throws {
        let request = RequestEnvelope(
            type: .ping, requestId: "r-3", payload: EmptyPayload())
        let data = try NDJSON.encodeLine(request)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["caller_role"], "a primary request must not grow a new wire key")

        let head = try NDJSON.decode(RawEnvelopeHead.self, from: data)
        XCTAssertNil(head.callerRoleRaw)
        XCTAssertEqual(head.callerRole, .primary)
    }

    /// A role this build does not know must NOT trap — the same forward-compat
    /// rule `typeRaw` and `ErrorPayload.codeRaw` follow: the raw value is
    /// preserved and the rest of the envelope still decodes.
    ///
    /// But "never trap" does not settle WHICH role it lands on, and that half
    /// is an authorization decision, not a decoding one. `.agent` is the
    /// RESTRICTED role; `.primary` is the privileged one. Resolving an
    /// unrecognised value to `.primary` would make this the only fallback in
    /// the protocol layer that GRANTS privilege on a value the build cannot
    /// understand — so a future third role (a `teammate` stamped by whatever
    /// runs team variants) would arrive unrestricted on every daemon built
    /// before that role existed, silently, and with no would-refuse ledger
    /// entry because nothing would be refused.
    ///
    /// ABSENT is the separate case and it still means `.primary` — see
    /// `testPrimaryRequestOmitsCallerRoleEntirely` above. Absent is the
    /// additive-optional contract; present-but-unknown is an unknown claim.
    func testUnknownCallerRoleDecodesToAgentNotPrimary() throws {
        let line = Data(
            #"{"protocol_version":\#(GMCCWireProtocol.version),"type":"PING","request_id":"r-4","caller_role":"teammate"}"#
                .utf8)
        let head = try NDJSON.decode(RawEnvelopeHead.self, from: line)
        XCTAssertEqual(head.callerRoleRaw, "teammate", "the raw value must survive — never trap")
        XCTAssertEqual(
            head.callerRole, .agent,
            "an unrecognised role must degrade to the RESTRICTED role, never to the privileged one")
        XCTAssertEqual(head.type, .ping, "the rest of the head must still decode")
    }

    func testHighTrafficRowRoundTrips() throws {
        let stub = PromptStub(
            uuid: "u-1", sessionUuid: "s-1", seq: 3, code: "p3",
            name: "demo", status: "draft", version: 2,
            ckfsRelativeStoragePath: "projects/r/prompts/3_demo",
            createdAt: "2026-08-22T00:00:00Z", updatedAt: "2026-08-22T00:00:00Z")
        let data = try NDJSON.encodeLine(stub)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["session_uuid"] as? String, "s-1")
        let decoded = try NDJSON.decode(PromptStub.self, from: data)
        XCTAssertEqual(decoded, stub)
    }
}
