import XCTest

@testable import GMCCDaemonKit

/// Who a pen call is FROM, decided by the harness rather than claimed by the
/// caller.
///
/// The property under test is fail-CLOSED. Inferring "primary" from a missing
/// agent id is forgeable by omission — and omission is the default, since an
/// agent does not know its own agent_id to send. So the primary is marked with
/// a positive literal, and anything unstamped must read as an agent. A
/// regression here is silent and only matters once role enforcement is live,
/// which is the worst possible time to discover it.
final class PenAttestTests: XCTestCase {

    private func payload(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func attestation(_ line: String?) -> Any? {
        guard let line,
              let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let output = root["hookSpecificOutput"] as? [String: Any],
              let input = output["updatedInput"] as? [String: Any]
        else { return nil }
        return input[HookRunner.attestKey]
    }

    func testPrimaryIsStampedWithAPositiveLiteral() {
        let line = HookRunner.penAttest(stdin: payload([
            "tool_name": "mcp__plugin_gmcc_pen__bot_next",
            "tool_input": ["prompt_uuid": "p"],
        ]))
        XCTAssertEqual(attestation(line) as? String, HookRunner.attestPrimary,
                       "the primary must be marked explicitly, never inferred from absence")
    }

    func testSubagentIsStampedWithItsAgentId() {
        let line = HookRunner.penAttest(stdin: payload([
            "tool_name": "mcp__plugin_gmcc_pen__explore_finding_add",
            "agent_id": "aconservative-d32a81b4",
            "tool_input": ["title": "t"],
        ]))
        XCTAssertEqual(attestation(line) as? String, "aconservative-d32a81b4")
    }

    /// THE FORGERY ATTEMPT. A caller that supplies its own attestation must not
    /// keep it — the hook overwrites, it does not merge.
    func testCallerSuppliedAttestationIsOverwritten() {
        let line = HookRunner.penAttest(stdin: payload([
            "tool_name": "mcp__plugin_gmcc_pen__prompt_get",
            "agent_id": "areal-agent",
            "tool_input": [HookRunner.attestKey: HookRunner.attestPrimary],
        ]))
        XCTAssertEqual(attestation(line) as? String, "areal-agent",
                       "an agent claiming to be the primary must be overwritten by the harness's own id")
    }

    func testExistingArgumentsSurvive() {
        let line = HookRunner.penAttest(stdin: payload([
            "tool_name": "mcp__plugin_gmcc_pen__bot_next",
            "tool_input": ["prompt_uuid": "keep-me", "step": "initial"],
        ]))
        guard let line, let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let output = root["hookSpecificOutput"] as? [String: Any],
              let input = output["updatedInput"] as? [String: Any]
        else { return XCTFail("no updatedInput") }
        XCTAssertEqual(input["prompt_uuid"] as? String, "keep-me")
        XCTAssertEqual(input["step"] as? String, "initial")
    }

    /// An empty agent_id is absence, not an identity.
    func testEmptyAgentIdReadsAsPrimary() {
        let line = HookRunner.penAttest(stdin: payload([
            "tool_name": "mcp__plugin_gmcc_pen__bot_next",
            "agent_id": "",
            "tool_input": [:] as [String: Any],
        ]))
        XCTAssertEqual(attestation(line) as? String, HookRunner.attestPrimary)
    }

    /// The matcher is configuration and can be widened by accident; the code
    /// guards itself.
    func testNonPenToolIsNotRewritten() {
        XCTAssertNil(HookRunner.penAttest(stdin: payload([
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ])), "a non-pen tool call must pass through untouched")
    }

    /// Undecidable input stays SILENT rather than emitting a stamp. Silence
    /// means no attestation, and no attestation reads as an agent — the
    /// restrictive side.
    func testUndecidableInputEmitsNothing() {
        XCTAssertNil(HookRunner.penAttest(stdin: Data()))
        XCTAssertNil(HookRunner.penAttest(stdin: Data("not json".utf8)))
    }
}
