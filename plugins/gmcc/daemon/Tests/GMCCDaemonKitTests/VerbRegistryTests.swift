import ArgumentParser
import XCTest

@testable import GMCCDaemonKit
@testable import gm

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

    // MARK: - CLI coverage: the deny set cannot drift from the CLI either

    /// `gm` command paths that legitimately carry NO registry row.
    ///
    /// Everything here is either purely local (talks to no daemon at all) or
    /// a wrapper whose every request is already registered under another
    /// spelling. A NEW entry is a deliberate decision that has to be written
    /// down here, in the open — which is the whole point. If the command you
    /// are adding sends ANY write request, it does not belong in this list:
    /// give its spelling to the owning `VerbSpec`'s `aliases:` instead.
    private static let localOnlyInvocations: Set<String> = [
        // Purely local — no socket at all. `gm verbs` in particular MUST stay
        // local: the PreToolUse guard shells out to it on the Bash hot path,
        // and a guard that needed a live daemon would fail closed exactly when
        // the daemon is down.
        "gm verbs",
        "gm cheatsheet",
        "gm setup",          // local file/PATH work; STATUS is its only request

        // Reads only, and every request they make is registered under its own
        // spelling. Listing them here rather than aliasing them keeps the
        // alias lists meaning "another way to spell THIS verb".
        "gm sandbox status", // STATUS
        "gm daemon status",  // PING, and deliberately never autostarts
        "gm daemon start",   // connect/HELLO plus a local spawn

        // DOPE_PROMOTE, but `dryRun: true` — "doctor reports, it must never
        // publish as a side effect of being run" (Doctor.swift:147-152).
        // Everything else it sends is a read. A doctor that ever promotes for
        // real must move OUT of this list.
        "gm doctor",
    ]

    /// THE DRIFT THIS TEST EXISTS FOR, and it is the CLASS rather than the
    /// instance. `testEveryMessageTypeHasARoleDecision` proves the registry
    /// covers the VERB SET. It does not prove the registry covers the CLI —
    /// and the registry's promise ("the deny reason is GENERATED, so it can
    /// never drift") is worth exactly as much as its CLI coverage, because
    /// `gmcc_gm_write_guard.sh` matches the string an agent TYPES.
    ///
    /// One `gmInvocation` per MessageType was not that. `gm` ships wrappers:
    /// `Bot.Summary.run()` issues `client.exploreOpen` as `gm bot summary`,
    /// and `gm bot sweep` is the reconcile engine — both writes the deny set
    /// could not see, and `gm bot summary` is the spelling the cheatsheet core
    /// hands to every spawned agent. One missing spelling is a bug; a registry
    /// that cannot tell you a spelling is missing is the defect.
    ///
    /// Walking `gm`'s own ArgumentParser tree (the CheatsheetTests precedent)
    /// is what turns the NEXT such wrapper into a build failure instead of a
    /// silent hole. A leaf that legitimately has no row goes in the allowlist
    /// WITH ITS REASON, so omitting a verb is a visible decision.
    func testEveryGmLeafCommandIsRegisteredOrExplicitlyLocal() {
        let leaves = Set(GM.configuration.subcommands.flatMap { leafPaths($0, prefix: "gm") })
        XCTAssertGreaterThan(leaves.count, 50, "command tree walk looks broken")

        let unaccounted = leaves
            .subtracting(VerbRegistry.gmInvocations)
            .subtracting(Self.localOnlyInvocations)
        XCTAssertTrue(
            unaccounted.isEmpty,
            """
            \(unaccounted.count) `gm` command path(s) have no VerbRegistry row and are \
            not declared local:
              \(unaccounted.sorted().joined(separator: "\n  "))
            If a command sends a WRITE request, add its spelling to the owning \
            VerbSpec's `aliases:` — otherwise the PreToolUse guard's deny set, which \
            is GENERATED from this registry, cannot see it. If it sends nothing (or \
            only reads already registered elsewhere), add it to localOnlyInvocations \
            with a reason.
            """)
    }

    /// The other direction: a registry row naming a `gm` path that does not
    /// exist denies nothing and silently protects nothing.
    func testEveryRegisteredInvocationIsARealGmCommand() {
        let leaves = Set(GM.configuration.subcommands.flatMap { leafPaths($0, prefix: "gm") })
        // A row may pin a specific FLAG form ("gm events --follow" is
        // SUBSCRIBE, plain "gm events" is EVENT_LIST). Compare on the command
        // path, which is the part the guard's prefix match uses.
        let stale = Set(VerbRegistry.gmInvocations.map(commandPath)).subtracting(leaves)
        XCTAssertTrue(
            stale.isEmpty,
            """
            VerbRegistry names \(stale.count) `gm` invocation(s) that no longer exist \
            in the command tree:
              \(stale.sorted().joined(separator: "\n  "))
            A row pointing at a renamed or deleted command denies nothing.
            """)
    }

    func testLocalOnlyAllowlistHasNoStaleEntries() {
        let leaves = Set(GM.configuration.subcommands.flatMap { leafPaths($0, prefix: "gm") })
        let stale = Self.localOnlyInvocations.subtracting(leaves)
        XCTAssertTrue(
            stale.isEmpty,
            "localOnlyInvocations names commands that no longer exist: \(stale.sorted())")
    }

    /// Everything before the first flag — "gm events --follow" → "gm events".
    private func commandPath(_ invocation: String) -> String {
        invocation.split(separator: " ").prefix { !$0.hasPrefix("-") }.joined(separator: " ")
    }

    /// ArgumentParser's default command name: the type name converted to
    /// hyphen-separated lowercase (FileChange → "file-change"), used only when
    /// a command does not set commandName explicitly.
    private func derivedName(_ type: ParsableCommand.Type) -> String {
        let typeName = String(describing: type)
        var out = ""
        for (i, ch) in typeName.enumerated() {
            if ch.isUppercase, i > 0 { out.append("-") }
            out.append(ch.lowercased())
        }
        return out
    }

    /// Every typeable path to a leaf, ArgumentParser's own `aliases:` included
    /// — `gm dope domain-add` is as real a spelling as `gm dope persistence-add`
    /// and an agent can type either, so the deny set has to know both.
    private func leafPaths(_ type: ParsableCommand.Type, prefix: String) -> [String] {
        let config = type.configuration
        let names = [config.commandName ?? derivedName(type)] + config.aliases
        let paths = names.map { prefix.isEmpty ? $0 : "\(prefix) \($0)" }
        guard !config.subcommands.isEmpty else { return paths }
        return paths.flatMap { path in
            config.subcommands.flatMap { leafPaths($0, prefix: path) }
        }
    }

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

    func testShippedEnforcementIsObserve() {
        // The Wave-4 flip is a ONE-LINE change and this is the test that
        // records it happening. Read the would-refuse ledger BEFORE flipping —
        // `gm verbs` (last line, or `.would_refuse` under --json), or
        // ~/gmcc/would_refuse.json directly. That ledger is the precondition.
        XCTAssertEqual(
            VerbRegistry.enforcement, .observe,
            "the door ships .observe for the implementing run (amendment A5)")
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
    /// So the reader is pinned here. `gm verbs` renders the ledger in both
    /// output modes, and the banner in VerbRegistry.swift names `gm verbs`.
    func testGmVerbsIsTheLedgersReader() throws {
        let data = try WireCodec.prettyEncoder.encode(Verbs.parse([]).payload())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(
            json["would_refuse"],
            "gm verbs --json must carry the would-refuse ledger — it is the flip's precondition")
        XCTAssertEqual(json["enforcement"] as? String, VerbRegistry.enforcement.rawValue)

        // And the human rendering, which is what the banner points a reader at.
        XCTAssertTrue(
            VerbRegistry.wouldRefuseLedger().summaryLine.contains("would-refuse"),
            "the line gm verbs prints must name the counter")
    }
}
