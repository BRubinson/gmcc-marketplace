import XCTest

@testable import GMCCDaemonKit

/// The DOOR-SIDE assertion — the test the codebase lacked because the
/// mechanism did not exist.
///
/// It replaces the forbidden-substring loop that used to live in
/// WorkflowSpecTests (`names.contains("rank")` and friends, scraped out of
/// gmcc_mcp's source text). That loop asserted a *spelling* about a *roster*;
/// this asserts the actual authorization decision the daemon makes.
///
/// The coverage test is the CheatsheetTests precedent applied to
/// authorization: a new MessageType with no role decision FAILS THE BUILD.
final class VerbRegistryTests: XCTestCase {

    /// Enforcement is a process-global. Every test that flips it must put it
    /// back, or it leaks into whatever runs next in the same process.
    private func withEnforcement(
        _ mode: VerbEnforcement, _ body: () throws -> Void
    ) rethrows {
        let previous = VerbRegistry.enforcement
        VerbRegistry.enforcement = mode
        defer { VerbRegistry.enforcement = previous }
        try body()
    }

    // MARK: - Coverage

    func testEveryMessageTypeHasARoleDecision() {
        for type in MessageType.allCases {
            if VerbRegistry.unroledMessageTypes.contains(type) { continue }
            XCTAssertNotNil(
                VerbRegistry.spec(for: type),
                """
                MessageType.\(type) (\(type.rawValue)) has no VerbSpec. Every verb \
                needs a role decision: add a row to VerbRegistry.all, or — only \
                for a daemon→client-only message — to unroledMessageTypes.
                """)
        }
    }

    func testRegistryHasNoDuplicateRows() {
        let types = VerbRegistry.all.map(\.messageType)
        XCTAssertEqual(types.count, Set(types).count, "VerbRegistry.all repeats a MessageType")
        let penTools = VerbRegistry.all.compactMap(\.penTool)
        XCTAssertEqual(penTools.count, Set(penTools).count, "two verbs claim the same pen tool")

        // TWO ROWS CLAIMING ONE SPELLING IS A SILENT LAST-WINS. `byInvocation`
        // keeps whichever row is declared later, so a spelling aliased onto a
        // `.read` row after it was aliased onto a write would quietly leave
        // that write out of the deny set — the exact drift aliases exist to
        // stop, reintroduced through the back door.
        let invocations = VerbRegistry.all.flatMap(\.gmInvocations)
        let duplicated = Set(invocations.filter { i in invocations.filter { $0 == i }.count > 1 })
        XCTAssertTrue(
            duplicated.isEmpty,
            "these gm spellings are claimed by more than one VerbSpec: \(duplicated.sorted())")
        for composite in VerbRegistry.compositePenTools.keys {
            XCTAssertFalse(
                penTools.contains(composite),
                "\(composite) is declared BOTH as a composite and as a verb's penTool")
        }
    }

    // The CLI-coverage block that stood here walked `gm`'s ArgumentParser tree
    // to prove no command escaped the registry. That tree is gone: the daemon's
    // only clients are now the pen and the shell client, and
    // testEveryMessageTypeHasARoleDecision above covers the same ground from the
    // MessageType side — which is the side that actually authorizes.
    //
    // VerbRegistry still carries `gm <verb>` spellings. They are no longer a
    // command surface; they are the write guard's DENY SET, kept so a stale
    // binary left on a machine is still refused.

    func testUnroledMessageTypesAreDaemonToClientOnly() {
        // Widening this set is how the coverage test gets defeated — pin it.
        XCTAssertEqual(VerbRegistry.unroledMessageTypes, [.event, .error])
    }

    // MARK: - The four primary doors

    func testPrimaryDoorsAreExactlyTheApprovedFour() {
        let doors = Set(VerbRegistry.all.filter {
            if case .primaryDoor = $0.role { return true }
            return false
        }.map(\.messageType))
        // The post-change invariant, in the architecture summary's own words:
        // "no agent may call the primary doors (review rank, decide,
        // set-status, package seal); any agent may seal synthesis once
        // everything is ranked."
        XCTAssertEqual(doors, [.reviewRank, .archDecide, .promptSetStatus, .carePackageComplete])
    }

    func testExploreRankAndCompleteAreNotDoors() {
        // Decision 2 hands BOTH to the merged clarifier. If someone "tidies"
        // these into primaryDoor, the clarifier stops being able to do its job
        // the moment enforcement flips.
        for type: MessageType in [.exploreRank, .exploreComplete] {
            XCTAssertTrue(
                VerbRegistry.allows(type, callerRole: .agent),
                "\(type) must stay agent-callable — decision 2 gave it to the merged clarifier")
        }
        // …and the review-side rerank is outside that merge.
        XCTAssertFalse(VerbRegistry.allows(.reviewRank, callerRole: .agent))
    }

    // MARK: - The decision

    func testPrimaryDoorRefusesAgentUnderEnforce() {
        withEnforcement(.enforce) {
            guard case .refuse(let reason) = VerbRegistry.decide(.reviewRank, callerRole: .agent) else {
                return XCTFail("REVIEW_RANK must refuse caller_role agent under .enforce")
            }
            XCTAssertTrue(reason.contains("gm review rank"), "refusal must name the verb: \(reason)")
            XCTAssertTrue(reason.contains("caller_role agent refused"), reason)
        }
    }

    func testPrimaryDoorAllowsPrimaryUnderEnforce() {
        withEnforcement(.enforce) {
            XCTAssertEqual(VerbRegistry.decide(.reviewRank, callerRole: .primary), .allow)
            XCTAssertEqual(VerbRegistry.decide(.archDecide, callerRole: .primary), .allow)
            XCTAssertEqual(VerbRegistry.decide(.promptSetStatus, callerRole: .primary), .allow)
            XCTAssertEqual(VerbRegistry.decide(.carePackageComplete, callerRole: .primary), .allow)
        }
    }

    func testRecordAndReadVerbsSucceedForBothRoles() {
        withEnforcement(.enforce) {
            for type: MessageType in [.fileChangeAdd, .exploreFindingAdd, .briefingComplete] {
                XCTAssertEqual(VerbRegistry.decide(type, callerRole: .agent), .allow, "\(type)")
                XCTAssertEqual(VerbRegistry.decide(type, callerRole: .primary), .allow, "\(type)")
            }
            for type: MessageType in [.botNext, .kbiteSearch, .exploreGet] {
                XCTAssertEqual(VerbRegistry.decide(type, callerRole: .agent), .allow, "\(type)")
                XCTAssertEqual(VerbRegistry.decide(type, callerRole: .primary), .allow, "\(type)")
            }
        }
    }

    /// SHIP MODE. Under .observe a door NEVER returns an error — it logs and
    /// the dispatch continues. If this flips to .refuse before the final
    /// reviewed commit, the implementing run starts refusing its own agents.
    func testObserveModeNeverRefuses() {
        withEnforcement(.observe) {
            guard case .wouldRefuse = VerbRegistry.decide(.reviewRank, callerRole: .agent) else {
                return XCTFail(".observe must produce wouldRefuse, never refuse")
            }
        }
    }

    /// THE FLIP HAPPENED. This test recorded the door shipping `.observe`; it
    /// now records it shipping `.enforce`, so reverting is as deliberate an act
    /// as flipping was.
    ///
    /// Preconditions at the flip, both checked rather than remembered: the
    /// would-refuse ledger was empty (total 0, no ~/gmcc/would_refuse.json), and
    /// the launcher had stopped rebuilding on the connect path — which was the
    /// stated reason `.observe` shipped in the first place.
    func testShippedEnforcementIsEnforce() {
        XCTAssertEqual(
            VerbRegistry.enforcement, .enforce,
            "the door enforces; flipping back to .observe is a decision, not a default")
    }

    /// WHY ENFORCING IS SAFE RATHER THAN MERELY STRICT, pinned as a test because
    /// the two halves live in different files and only their conjunction is
    /// correct.
    ///
    /// With the CLI deleted, a door with no pen tool is a door nobody can walk.
    /// Enforcing against that state would not tighten a boundary — it would
    /// brick the primary at its own gates. So: every primary door must carry a
    /// pen tool, AND an agent must still be refused it.
    func testEnforcingDoesNotLockThePrimaryOutOfItsOwnDoors() {
        for spec in VerbRegistry.all where spec.role == .primaryDoor {
            XCTAssertNotNil(
                spec.penTool,
                "\(spec.gmInvocation) enforces but carries no pen tool — with no CLI it is reachable by nobody")
            guard case .refuse = VerbRegistry.decide(spec.messageType, callerRole: .agent) else {
                return XCTFail("\(spec.gmInvocation) must still refuse an agent under .enforce")
            }
            guard case .allow = VerbRegistry.decide(spec.messageType, callerRole: .primary) else {
                return XCTFail("\(spec.gmInvocation) must admit the primary under .enforce")
            }
        }
    }

    // MARK: - caller_role defaulting

    /// ABSENT and PRESENT-BUT-UNRECOGNISED are deliberately different cases.
    /// They look like one case, and collapsing them back into a single
    /// `?? .primary` is the regression this test exists to catch.
    func testAbsentCallerRoleResolvesToPrimary() {
        XCTAssertEqual(
            RawEnvelopeHead(protocolVersion: 1, typeRaw: "PING", requestId: "r").callerRole,
            .primary,
            "absent caller_role must mean primary — that is what makes the field additive")
    }

    func testUnrecognisedCallerRoleResolvesToAgentNotPrimary() {
        // `.agent` is the RESTRICTED role. A role this build does not know is
        // an authorization input, and the only safe direction for an unknown
        // authorization input is the SMALLER surface. Resolving it to
        // `.primary` would grant a future restricted role (a `teammate`
        // stamped by whatever runs team variants) the primary's doors on every
        // daemon built before that role existed — silently, and with no
        // would-refuse ledger entry, because nothing would be refused.
        XCTAssertEqual(
            RawEnvelopeHead(
                protocolVersion: 1, typeRaw: "PING", requestId: "r",
                callerRoleRaw: "teammate").callerRole,
            .agent,
            "an unrecognised role must degrade to the restricted role, never to the privileged one")
    }

    func testUnrecognisedCallerRoleIsRefusedAtAPrimaryDoor() {
        // The point of the fallback, exercised end to end: an unknown role
        // reaching a gate is stopped, not waved through.
        let head = RawEnvelopeHead(
            protocolVersion: 1, typeRaw: "REVIEW_RANK", requestId: "r",
            callerRoleRaw: "teammate")
        XCTAssertFalse(VerbRegistry.allows(.reviewRank, callerRole: head.callerRole))
        withEnforcement(.enforce) {
            guard case .refuse = VerbRegistry.decide(.reviewRank, callerRole: head.callerRole) else {
                return XCTFail("an unknown caller_role must not walk a primary door")
            }
        }
    }

    // MARK: - The would-refuse ledger (amendment A5 / M5)

    func testLedgerSummaryLineIsReadableEmptyAndPopulated() {
        XCTAssertTrue(
            VerbRegistry.WouldRefuseLedger().summaryLine.contains("0 would-refuse"),
            "an empty ledger must say so — it is the flip's green light")
        var ledger = VerbRegistry.WouldRefuseLedger()
        ledger.total = 3
        ledger.byVerb = ["REVIEW_RANK": 2, "ARCH_DECIDE": 1]
        ledger.firstAt = "2026-09-11T00:00:00Z"
        XCTAssertTrue(ledger.summaryLine.contains("REVIEW_RANK×2"), ledger.summaryLine)
        XCTAssertTrue(ledger.summaryLine.contains("ARCH_DECIDE×1"), ledger.summaryLine)
    }

    func testLedgerRoundTripsThroughTheWireCodec() throws {
        var ledger = VerbRegistry.WouldRefuseLedger()
        ledger.total = 1
        ledger.byVerb = ["PROMPT_SET_STATUS": 1]
        ledger.lastAt = "2026-09-11T00:00:00Z"
        let data = try WireCodec.prettyEncoder.encode(ledger)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // `gm verbs` and any operator reading the file both rely on these
        // keys being snake_case like the rest of the surface.
        XCTAssertNotNil(json["by_verb"])
        XCTAssertNotNil(json["last_at"])
        XCTAssertEqual(
            try WireCodec.decoder.decode(VerbRegistry.WouldRefuseLedger.self, from: data), ledger)
    }

    /// A5'S ACTUAL DELIVERABLE, AND WHY THIS TEST EXISTS. The amendment asked
    /// for the flip's precondition to be MACHINE-READABLE rather than
    /// remembered, and `summaryLine` on its own is not that — it was written,
    /// correct, and called by nothing, while the flip-point banner told the
    /// reader to run a command that printed no counter. An instruction that
    /// looks satisfied and is not is worse than no instruction: following it
    /// yields a clean-looking screen and the blind flip A5 exists to prevent.
    ///
    /// So the reader is pinned here. The ledger moved into the kit as
    /// `VerbLedger` when the CLI was deleted — the payload is the same, and
    /// `gmcc_hook verbs` is what renders it now.
    func testVerbLedgerIsTheLedgersReader() throws {
        let data = try WireCodec.prettyEncoder.encode(VerbLedger.build())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(
            json["would_refuse"],
            "the verb ledger must carry the would-refuse ledger — it is the flip's precondition")
        XCTAssertEqual(json["enforcement"] as? String, VerbRegistry.enforcement.rawValue)

        // And the human rendering, which is what the banner points a reader at.
        XCTAssertTrue(
            VerbRegistry.wouldRefuseLedger().summaryLine.contains("would-refuse"),
            "the line gm verbs prints must name the counter")
    }
}
