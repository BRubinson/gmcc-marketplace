import Foundation

/// Who is on the other end of the socket.
///
/// This is a TRANSPORT TAG, not a principal. `gmcc_mcp` stamps `.agent` on
/// everything it forwards; `gm` stamps `.primary` on everything — including an
/// agent's Bash `gm` call. The door below therefore constrains the compliant
/// channel and cannot see the non-compliant one; it works only as a composite
/// with the PreToolUse `gm`-write deny.
///
/// ABSENT ON THE WIRE MEANS `.primary`. That default is what makes the field
/// additive (every existing caller and every pinned-Kit GMVibes is unchanged
/// by construction) and it is also why the decode spelling is load-bearing:
/// see the `callerRoleRaw = "callerRole"` note in Envelope.swift. A field that
/// silently decodes to nil fails OPEN — every agent would read as the primary.
///
/// A PRESENT VALUE THIS BUILD DOES NOT RECOGNISE MEANS `.agent`, and that is a
/// different rule for a different case. `.primary` is the PRIVILEGED role here,
/// so an unknown role — which can only come from a caller newer than this
/// daemon, e.g. a third `teammate` role added later — degrades to the smaller
/// surface rather than being handed the gate doors. `RawEnvelopeHead.callerRole`
/// is where both rules live.
///
/// ADDING A CASE IS AN AUTHORIZATION CHANGE. A new role is unknown to every
/// daemon already built, and each of those will read it as `.agent` until it is
/// rebuilt — so a new role must be at least as restricted as `.agent`, or the
/// rollout has to move the daemon first.
public enum CallerRole: String, Codable, Hashable, CaseIterable, Sendable {
    case primary
    case agent
}

/// What a verb is, for authorization purposes.
public enum VerbRole: Hashable, Sendable {
    /// A GATE the primary alone may walk through. There are exactly four —
    /// review rank, arch decide, prompt set-status, care-package seal — and
    /// that list is the approved post-change invariant, stated in the
    /// architecture summary in these words:
    ///
    ///   *no agent may call the primary doors (review rank, decide,
    ///   set-status, package seal); any agent may seal synthesis once
    ///   everything is ranked.*
    ///
    /// Deliberately NOT here: `exploreRank` and `exploreComplete` — decision 2
    /// hands both to the merged clarifier. `reviewRank` STAYS, because the
    /// review-side reranker is outside the approved merge.
    case primaryDoor

    /// A write any caller may make. `agentPhases` is DECLARATIVE metadata, not
    /// a second gate: the door has no workflow phase in hand at dispatch time
    /// (resolving one would put a db read on every message). It is consumed by
    /// the generated MCP `instructions` string and the advisory phase gates.
    /// `nil` means "every phase".
    case record(agentPhases: [WorkflowSpec.Phase]?)

    /// A read. Never refused on role.
    case read
}

/// One row per daemon verb: the message, how a human invokes it, the pen tool
/// that replaces that invocation for an agent, and who may call it.
public struct VerbSpec: Hashable, Sendable {
    public let messageType: MessageType
    /// The canonical `gm` invocation, or "" for transport-internal verbs that
    /// have no CLI surface (HELLO, SUBSCRIBE, EVENT, ERROR).
    public let gmInvocation: String
    /// EVERY OTHER `gm` SPELLING THAT SENDS THIS SAME MessageType.
    ///
    /// The registry's promise is that the deny set cannot drift from the verb
    /// set. One `gmInvocation` per MessageType keeps that promise against the
    /// ROSTER but not against the CLI, because `gm` ships wrappers over single
    /// verbs: `gm bot summary` IS `gm explore open` (EXPLORE_OPEN). A spelling
    /// absent from this list is a write the guard does not see — the drift the
    /// registry exists to make impossible.
    ///
    /// `VerbRegistryTests.testEveryGmLeafCommandIsRegisteredOrExplicitlyLocal`
    /// walks `gm`'s own ArgumentParser tree and fails the build on the next
    /// omission, so this list cannot silently fall behind the CLI.
    public let gmAliases: [String]
    /// The MCP pen tool an agent uses instead of `gmInvocation`, when one
    /// exists. `nil` means this verb is not on the pen surface.
    public let penTool: String?
    public let role: VerbRole

    /// Canonical first, then every alias. Empty for transport-internal verbs.
    public var gmInvocations: [String] {
        gmInvocation.isEmpty ? [] : [gmInvocation] + gmAliases
    }

    public init(
        _ messageType: MessageType,
        gm gmInvocation: String,
        aliases gmAliases: [String] = [],
        pen penTool: String? = nil,
        role: VerbRole
    ) {
        self.messageType = messageType
        self.gmInvocation = gmInvocation
        self.gmAliases = gmAliases
        self.penTool = penTool
        self.role = role
    }
}

/// Whether the door refuses or merely counts.
public enum VerbEnforcement: String, Codable, Hashable, Sendable {
    /// Log "[role] WOULD REFUSE <verb>", bump the ledger, and CONTINUE.
    case observe
    /// Return ErrorCode.forbidden.
    case enforce
}

/// The single declaration of the daemon's verb surface and its authorization
/// policy — the thing five consumers read instead of keeping five drifting
/// copies of the same policy:
///
///   1. `Server.dispatch`'s role refusal (the door),
///   2. the `gmcc_mcp` pen roster,
///   3. `gm verbs --json` (what the PreToolUse deny reason is generated from),
///   4. the tests (`VerbRegistryTests`, `WorkflowSpecTests`),
///   5. the generated MCP `instructions` string.
///
/// `VerbRegistryTests` asserts every `MessageType` is either here or in an
/// explicit allowlist, so adding a verb without making a role decision FAILS
/// THE BUILD — the `CheatsheetTests` precedent applied to authorization, and
/// the reason this cannot rot the way the old forbidden-substring loop did.
public enum VerbRegistry {

    // MARK: - Enforcement

    // ┌──────────────────────────────────────────────────────────────────┐
    // │  THE FLIP POINT.  `.observe` → `.enforce` is a ONE-LINE change   │
    // │  and it is THIS PROMPT'S FINAL REVIEWED COMMIT (amendment A5) —  │
    // │  inside review_fix, owned and reviewed, not a floating follow-up.│
    // │                                                                  │
    // │  PRECONDITION, and it is machine-readable rather than            │
    // │  remembered: read the would-refuse ledger first.                 │
    // │      gm verbs                 (prints the counter)               │
    // │      gm verbs --json          (.would_refuse)                    │
    // │      cat ~/gmcc/would_refuse.json                                │
    // │  A non-empty `by_verb` naming anything other than a genuine      │
    // │  agent reaching for a primary door means the flip would break a  │
    // │  live caller — fix that first.                                   │
    // │                                                                  │
    // │  WHY IT SHIPS OBSERVE: this prompt modifies the machine          │
    // │  executing it. run_mcp.sh rebuilds unconditionally before exec,  │
    // │  so the live pen and daemon change underneath the agents         │
    // │  currently using them. A refusal mid-run spends an agent's       │
    // │  context on a door that did not exist when it started.           │
    // │                                                                  │
    // │  The window between the Wave-1 deletion of the old              │
    // │  payload-granular synthesis guard and this flip is a KNOWN,      │
    // │  BOUNDED gap — bounded by this prompt's own close.               │
    // └──────────────────────────────────────────────────────────────────┘
    nonisolated(unsafe) public static var enforcement: VerbEnforcement = .observe

    // MARK: - Decision

    public enum Decision: Hashable, Sendable {
        case allow
        /// `.observe`: the caller is refused on paper only. Log and continue.
        case wouldRefuse(reason: String)
        /// `.enforce`: return ErrorCode.forbidden.
        case refuse(reason: String)
    }

    /// Is this role allowed to call this verb at all? Pure policy — no
    /// enforcement mode, no side effects. `decide` is what the door calls.
    public static func allows(_ type: MessageType, callerRole: CallerRole) -> Bool {
        guard callerRole == .agent else { return true }
        guard let spec = spec(for: type) else { return true }
        switch spec.role {
        case .primaryDoor: return false
        case .record, .read: return true
        }
    }

    /// The door's whole decision, enforcement mode included. A verb with no
    /// VerbSpec is ALLOWED — an unregistered verb is a build failure in the
    /// tests, never a runtime refusal (failing closed on an unknown verb
    /// would turn a missing row into an outage).
    public static func decide(_ type: MessageType, callerRole: CallerRole) -> Decision {
        guard !allows(type, callerRole: callerRole) else { return .allow }
        let reason = refusalMessage(for: type)
        switch enforcement {
        case .observe: return .wouldRefuse(reason: reason)
        case .enforce: return .refuse(reason: reason)
        }
    }

    /// The FORBIDDEN message body. Names the pen replacement when one exists,
    /// so a refusal is actionable rather than merely correct.
    public static func refusalMessage(for type: MessageType) -> String {
        let spec = spec(for: type)
        let invocation = spec.map { $0.gmInvocation.isEmpty ? $0.messageType.rawValue : $0.gmInvocation }
            ?? type.rawValue
        return "\(invocation) is a primary-only gate verb — caller_role agent refused"
    }

    // MARK: - Lookup

    private static let byMessageType: [MessageType: VerbSpec] = {
        var map: [MessageType: VerbSpec] = [:]
        for spec in all { map[spec.messageType] = spec }
        return map
    }()

    public static func spec(for type: MessageType) -> VerbSpec? {
        byMessageType[type]
    }

    /// Every `gm` spelling the registry knows, canonical and alias alike. This
    /// is the set the PreToolUse guard's deny list is generated from and the
    /// set the CLI-coverage test checks `gm`'s command tree against.
    public static var gmInvocations: Set<String> {
        Set(all.flatMap(\.gmInvocations))
    }

    /// The row a `gm` command path belongs to, whatever spelling it uses.
    public static func spec(forInvocation invocation: String) -> VerbSpec? {
        byInvocation[invocation]
    }

    private static let byInvocation: [String: VerbSpec] = {
        var map: [String: VerbSpec] = [:]
        for spec in all {
            for invocation in spec.gmInvocations { map[invocation] = spec }
        }
        return map
    }()

    /// Every pen tool that is 1:1 with a verb, plus the composites below.
    public static var penToolNames: Set<String> {
        Set(all.compactMap(\.penTool)).union(compositePenTools.keys)
    }

    /// Pen tools that are NOT 1:1 with a MessageType — a convenience the pen
    /// composes out of several verbs, so they carry no VerbSpec of their own.
    public static let compositePenTools: [String: [MessageType]] = [
        // BOT_GET to find the workflow's prompt, then PROMPT_GET to read it.
        "bot_current_prompt": [.botGet, .promptGet],
    ]

    /// MessageTypes deliberately left out of `all`. Daemon → client only: they
    /// are never dispatched, so they have no caller and no role.
    public static let unroledMessageTypes: Set<MessageType> = [.event, .error]

    // MARK: - The would-refuse ledger (amendment A5 / M5)
    //
    // The "WOULD REFUSE" log line alone has no reader — neither `gm doctor`
    // nor `gm bot status` reads daemon logs — so the enforce flip would be
    // made blind or never made at all. The ledger is the machine-readable
    // half: the daemon appends to it on the server's serial queue (single
    // writer, same as the db), and `gm verbs` reads it from its own process.
    //
    // `gm verbs` is the reader because it is the command that already prints
    // the enforcement mode, and it is purely local — no daemon, no socket —
    // so the flip's precondition can be read even when the daemon that would
    // be flipped is down. `VerbRegistryTests` asserts `gm verbs` renders the
    // counter, so the banner above cannot come to name a command that does
    // not print it.

    public struct WouldRefuseLedger: Codable, Hashable, Sendable {
        public var total: Int
        /// MessageType rawValue → count.
        public var byVerb: [String: Int]
        public var firstAt: String?
        public var lastAt: String?

        public init(
            total: Int = 0,
            byVerb: [String: Int] = [:],
            firstAt: String? = nil,
            lastAt: String? = nil
        ) {
            self.total = total
            self.byVerb = byVerb
            self.firstAt = firstAt
            self.lastAt = lastAt
        }

        public var isEmpty: Bool { total == 0 }

        /// One line for `gm verbs` — the flip's green light, or the list of
        /// live callers a flip would break.
        public var summaryLine: String {
            guard total > 0 else {
                return "verb door: observe mode, 0 would-refuse (safe to flip to .enforce)"
            }
            let verbs = byVerb.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key)×\($0.value)" }
                .joined(separator: ", ")
            return "verb door: observe mode, \(total) would-refuse since \(firstAt ?? "?") — \(verbs)"
        }
    }

    /// Protocol-layer ISO stamp. Deliberately NOT StoreCore.isoNow() — that
    /// one is internal, and the ledger must stay a Protocol-layer concern with
    /// no db dependency (the pen and gm both read it without a Store).
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    private static func isoNow() -> String { isoFormatter.string(from: Date()) }

    /// `~/gmcc/would_refuse.json` (`$GMCC_ROOT` honoured, so a sandbox keeps
    /// its own ledger).
    public static var wouldRefuseLedgerURL: URL {
        Paths.root.appendingPathComponent("would_refuse.json", isDirectory: false)
    }

    /// Read the ledger. A missing or unreadable file is an EMPTY ledger, never
    /// an error — a status line must not fail because nothing has happened yet.
    /// Read by `gm verbs` (and available to any other status surface: it is a
    /// pure file read with no Store and no socket).
    public static func wouldRefuseLedger() -> WouldRefuseLedger {
        guard let data = try? Data(contentsOf: wouldRefuseLedgerURL),
              let ledger = try? WireCodec.decoder.decode(WouldRefuseLedger.self, from: data)
        else { return WouldRefuseLedger() }
        return ledger
    }

    /// Record one would-refuse. Called by the daemon ONLY, from the server's
    /// serial queue — read-modify-write is safe under that single-writer
    /// invariant. Best-effort: a failed write must never break dispatch.
    @discardableResult
    public static func noteWouldRefuse(_ type: MessageType, at stamp: String? = nil) -> WouldRefuseLedger {
        let now = stamp ?? isoNow()
        var ledger = wouldRefuseLedger()
        ledger.total += 1
        ledger.byVerb[type.rawValue, default: 0] += 1
        if ledger.firstAt == nil { ledger.firstAt = now }
        ledger.lastAt = now
        if let data = try? WireCodec.prettyEncoder.encode(ledger) {
            try? FileManager.default.createDirectory(
                at: Paths.root, withIntermediateDirectories: true)
            try? data.write(to: wouldRefuseLedgerURL, options: .atomic)
        }
        return ledger
    }

    // MARK: - The table
    //
    // ONE ROW PER MessageType. Adding a case to MessageType without adding a
    // row here (or to `unroledMessageTypes`) fails VerbRegistryTests.

    public static let all: [VerbSpec] = [

        // ── Infra ────────────────────────────────────────────────────────
        VerbSpec(.hello, gm: "", role: .read),
        VerbSpec(.ping, gm: "gm ping", role: .read),
        VerbSpec(.status, gm: "gm status", role: .read),
        // `gm daemon restart` runs Stop before Start — same SHUTDOWN.
        VerbSpec(.shutdown, gm: "gm daemon stop", aliases: ["gm daemon restart"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.subscribe, gm: "gm events --follow", role: .read),
        // `gm sandbox refresh` takes the sanctioned Online Backup of prod.
        VerbSpec(.backup, gm: "gm backup", aliases: ["gm sandbox refresh"],
                 role: .record(agentPhases: nil)),
        // `gm context env` emits the SessionStart env block from PATHS_GET and
        // nothing else — `Context.Env.run()` calls `pathsGet` alone, and the
        // provisioning write is the separate `gm context ensure`. Registering
        // it as a WRITE would make the guard deny a pure read, which is the
        // fail-CLOSED direction the guard's contract forbids.
        VerbSpec(.pathsGet, gm: "gm paths", aliases: ["gm context env"], role: .read),
        VerbSpec(.configSet, gm: "gm config set", role: .record(agentPhases: nil)),
        VerbSpec(.eventList, gm: "gm events", role: .read),

        // ── Context bootstrap ────────────────────────────────────────────
        VerbSpec(.contextEnsure, gm: "gm context ensure", role: .record(agentPhases: nil)),
        VerbSpec(.contextGet, gm: "gm context get", role: .read),

        // ── Project / instance / session ─────────────────────────────────
        VerbSpec(.projectList, gm: "gm project list", role: .read),
        VerbSpec(.projectUpdate, gm: "gm project update", role: .record(agentPhases: nil)),
        VerbSpec(.instanceList, gm: "gm instance list", role: .read),
        VerbSpec(.instanceCurrentSession, gm: "gm instance current-session", role: .read),
        VerbSpec(.sessionList, gm: "gm session list", role: .read),
        VerbSpec(.sessionGet, gm: "gm session get", role: .read),
        VerbSpec(.sessionUpdate, gm: "gm session update", role: .record(agentPhases: nil)),
        VerbSpec(.sessionResolve, gm: "gm session resolve", role: .read),

        // ── Prompts ──────────────────────────────────────────────────────
        VerbSpec(.promptCreate, gm: "gm prompt create", role: .record(agentPhases: nil)),
        VerbSpec(.promptList, gm: "gm prompt list", role: .read),
        // `gm bot current_prompt` resolves the workflow, then sends this.
        VerbSpec(.promptGet, gm: "gm prompt get", aliases: ["gm bot current_prompt"],
                 pen: "prompt_get", role: .read),
        VerbSpec(.promptUpdateContent, gm: "gm prompt update-content", role: .record(agentPhases: nil)),
        // PRIMARY DOOR — the only thing that moves a prompt.
        VerbSpec(.promptSetStatus, gm: "gm prompt set-status", role: .primaryDoor),
        VerbSpec(.promptStart, gm: "gm prompt start", role: .record(agentPhases: nil)),
        VerbSpec(.promptResume, gm: "gm prompt resume", role: .record(agentPhases: nil)),

        // ── Bot workflow machine ─────────────────────────────────────────
        VerbSpec(.botNext, gm: "gm bot next", aliases: ["gm bot status"],
                 pen: "bot_next", role: .read),
        VerbSpec(.botGet, gm: "gm bot get", pen: "bot_get", role: .read),

        // ── Agent registry ───────────────────────────────────────────────
        // DELIBERATELY NO PEN TOOL. The registration is the SPAWNER's claim
        // about an agent it spawned; an agent registering ITSELF is exactly
        // the self-reported trust this surface replaces. A workflow script
        // calls it, which is the one named exception to "workflow scripts
        // never touch gm".
        // The alias is the SubagentStart half of the same row: the hook writes
        // identity, `gm agent register` writes authority, and both land here.
        VerbSpec(.agentRegister, gm: "gm agent register",
                 aliases: ["gm hook subagent-start"], role: .record(agentPhases: nil)),

        // ── Artifacts / prompt-qualified diagrams ────────────────────────
        // `gm render` writes the rendered artifact row it just produced.
        VerbSpec(.artifactAdd, gm: "gm artifact add", aliases: ["gm render"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.artifactList, gm: "gm artifact list", role: .read),
        VerbSpec(.promptDiagramQualify, gm: "gm prompt-diagram qualify", role: .record(agentPhases: nil)),
        VerbSpec(.promptDiagramGet, gm: "gm prompt-diagram get", role: .read),
        VerbSpec(.promptDiagramList, gm: "gm prompt-diagram list", role: .read),

        // ── File changes ─────────────────────────────────────────────────
        // `gm hook post-tool-use` is the SAME write under the machine's
        // spelling: the hook shim runs it with a raw payload on stdin. It is
        // registered as an alias so the PreToolUse deny set — which is
        // generated from this registry — can see it, because an agent typing
        // it by hand would be forging capture rows for a tool call that never
        // happened.
        VerbSpec(.fileChangeAdd, gm: "gm file-change add",
                 aliases: ["gm hook post-tool-use"], pen: "file_change_add",
                 role: .record(agentPhases: nil)),
        VerbSpec(.fileChangeList, gm: "gm file-change list", pen: "file_change_list", role: .read),

        // ── Kbites ───────────────────────────────────────────────────────
        VerbSpec(.kbiteList, gm: "gm kbite list", role: .read),
        VerbSpec(.kbiteAdd, gm: "gm kbite add", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteRemove, gm: "gm kbite remove", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteMawOpen, gm: "gm kbite maw-open", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteDigest, gm: "gm kbite digest", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteGet, gm: "gm kbite get", role: .read),
        VerbSpec(.kbiteFileGet, gm: "gm kbite file-get", pen: "kbite_file_get", role: .read),
        VerbSpec(.kbiteSearch, gm: "gm kbite search", pen: "kbite_search", role: .read),
        VerbSpec(.kbiteKeywordTag, gm: "gm kbite keyword-tag", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteExport, gm: "gm kbite export", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteImport, gm: "gm kbite import", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteDelete, gm: "gm kbite delete", role: .record(agentPhases: nil)),

        // ── Search ───────────────────────────────────────────────────────
        VerbSpec(.catalogSearch, gm: "gm catalog search", role: .read),
        VerbSpec(.search, gm: "gm search", role: .read),

        // ── Clarification machine ────────────────────────────────────────
        VerbSpec(.clarifyOpen, gm: "gm clarify open", role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyQuestionAdd, gm: "gm clarify question-add", pen: "clarify_question_add",
                 role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyNoteAdd, gm: "gm clarify note-add", pen: "clarify_note_add",
                 role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifySeal, gm: "gm clarify seal", role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyAnswer, gm: "gm clarify answer", role: .record(agentPhases: [.clarifyUser])),
        VerbSpec(.clarifyReopen, gm: "gm clarify reopen", role: .record(agentPhases: nil)),
        VerbSpec(.clarifyFinalize, gm: "gm clarify finalize", role: .record(agentPhases: [.clarifyUser])),
        VerbSpec(.clarifyGet, gm: "gm clarify get", pen: "clarify_get", role: .read),

        // ── Care package ─────────────────────────────────────────────────
        VerbSpec(.carePackageOpen, gm: "gm clarify package-open",
                 role: .record(agentPhases: [.carePackage])),
        VerbSpec(.carePackageRefAdd, gm: "gm clarify package-add", pen: "care_ref_add",
                 role: .record(agentPhases: [.carePackage])),
        // PRIMARY DOOR — the package SEAL: the clarified intent lives only here.
        VerbSpec(.carePackageComplete, gm: "gm clarify package-complete", role: .primaryDoor),
        VerbSpec(.carePackageGet, gm: "gm clarify package-get", pen: "care_package_get", role: .read),

        // ── Architecture machine ─────────────────────────────────────────
        VerbSpec(.archOpen, gm: "gm arch open", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archSummarize, gm: "gm arch summarize", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archPersistAdd, gm: "gm arch persist-add", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archFieldAdd, gm: "gm arch field-add", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archGeneralAdd, gm: "gm arch general-add", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archOptionAdd, gm: "gm arch option-add", pen: "arch_option_add",
                 role: .record(agentPhases: [.archOptions])),
        // PRIMARY DOOR — DECIDE selects one option and rejects its siblings.
        VerbSpec(.archDecide, gm: "gm arch decide", role: .primaryDoor),
        VerbSpec(.archPropose, gm: "gm arch propose", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archApprove, gm: "gm arch approve", role: .record(agentPhases: [.planGate])),
        VerbSpec(.archRevise, gm: "gm arch revise", role: .record(agentPhases: [.planGate])),
        VerbSpec(.archGet, gm: "gm arch get", pen: "arch_get", role: .read),

        // ── Exploration machine ──────────────────────────────────────────
        // bot_summary IS explore open: fetch-or-open the caller's per-agent
        // row. Amendment A2 grants it to the merged clarifier, which is what
        // lets ensureSummary run for a clarifier that never explored.
        //
        // `gm bot summary` is the OTHER CLI spelling of this same verb, and it
        // is the one the cheatsheet core hands to every spawned agent — so it
        // was the guard's single biggest blind spot until it was listed here.
        VerbSpec(.exploreOpen, gm: "gm explore open", aliases: ["gm bot summary"],
                 pen: "bot_summary",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        VerbSpec(.exploreKeyFileAdd, gm: "gm explore key-file-add", pen: "explore_key_file_add",
                 role: .record(agentPhases: [.explore])),
        VerbSpec(.exploreFindingAdd, gm: "gm explore finding-add", pen: "explore_finding_add",
                 role: .record(agentPhases: [.explore])),
        // NOT a primaryDoor — decision 2 hands the rerank to the merged
        // clarifier, which runs in clarify_open.
        VerbSpec(.exploreRank, gm: "gm explore rank", pen: "explore_rank",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        // NOT a primaryDoor either: "any agent may seal synthesis once
        // everything is ranked" is exactly what decision 2 chose.
        VerbSpec(.exploreComplete, gm: "gm explore complete", pen: "explore_complete",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        VerbSpec(.exploreReopen, gm: "gm explore reopen", role: .record(agentPhases: nil)),
        VerbSpec(.exploreGet, gm: "gm explore get", pen: "explore_get", role: .read),

        // ── Review machine ───────────────────────────────────────────────
        VerbSpec(.reviewOpen, gm: "gm review open", role: .record(agentPhases: [.review])),
        VerbSpec(.reviewFindingAdd, gm: "gm review finding-add", pen: "review_finding_add",
                 role: .record(agentPhases: [.review, .reviewFix])),
        // PRIMARY DOOR — and it STAYS one: the review-side reranker is
        // outside the approved clarifier merge.
        VerbSpec(.reviewRank, gm: "gm review rank", role: .primaryDoor),
        VerbSpec(.reviewResolve, gm: "gm review resolve", role: .record(agentPhases: [.reviewFix])),
        VerbSpec(.reviewComplete, gm: "gm review complete", role: .record(agentPhases: [.review])),
        VerbSpec(.reviewReopen, gm: "gm review reopen", role: .record(agentPhases: nil)),
        VerbSpec(.reviewGet, gm: "gm review get", pen: "review_get", role: .read),

        // ── Agent briefing ───────────────────────────────────────────────
        VerbSpec(.briefingOpen, gm: "gm briefing open", role: .record(agentPhases: [.briefing])),
        VerbSpec(.briefingComplete, gm: "gm briefing complete", pen: "briefing_complete",
                 role: .record(agentPhases: [.briefing])),
        VerbSpec(.briefingGet, gm: "gm briefing get", aliases: ["gm bot briefing"],
                 pen: "briefing_get", role: .read),
        VerbSpec(.briefingList, gm: "gm briefing list", role: .read),
        VerbSpec(.briefingStub, gm: "gm briefing stub", role: .read),

        // ── DOPED domain modeling ────────────────────────────────────────
        VerbSpec(.dopeInit, gm: "gm dope init", role: .record(agentPhases: nil)),
        VerbSpec(.dopeList, gm: "gm dope list", role: .read),
        VerbSpec(.dopeGet, gm: "gm dope get", pen: "dope_get", role: .read),
        VerbSpec(.dopeSearch, gm: "gm dope search", pen: "dope_search", role: .read),
        // ONE MessageType PER LEVEL, FIVE CLI SPELLINGS EACH. Every `gm dope
        // {scope,persistence,entity,property,enum,option}-{add,update,delete}`
        // funnels into these three verbs (Dope.runAdd / runUpdate / runDelete),
        // so all of them are writes and all of them must be visible to the
        // deny set. Only the persistence spelling was registered.
        VerbSpec(.dopeNodeAdd, gm: "gm dope persistence-add",
                 aliases: [
                    "gm dope domain-add", "gm dope entity-add",
                    "gm dope property-add", "gm dope enum-add",
                    "gm dope option-add",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeNodeUpdate, gm: "gm dope persistence-update",
                 aliases: [
                    "gm dope domain-update", "gm dope scope-update",
                    "gm dope entity-update", "gm dope property-update",
                    "gm dope enum-update", "gm dope option-update",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeNodeDelete, gm: "gm dope persistence-delete",
                 aliases: [
                    "gm dope domain-delete", "gm dope entity-delete",
                    "gm dope property-delete", "gm dope enum-delete",
                    "gm dope option-delete",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopePromote, gm: "gm dope promote", role: .record(agentPhases: nil)),
        VerbSpec(.dopeReadRepo, gm: "gm dope read-repo", role: .read),
        VerbSpec(.dopeMergePlan, gm: "gm dope merge-plan", role: .read),
        VerbSpec(.dopeResolve, gm: "gm dope resolve", role: .record(agentPhases: nil)),
        VerbSpec(.dopeWriteRepo, gm: "gm dope write-repo", role: .record(agentPhases: nil)),
        // `gm dope sync` runs DopeBootSync, which sends DOPE_INIT and
        // DOPE_INGEST — a write, files → db, forward only.
        VerbSpec(.dopeIngest, gm: "gm dope ingest", aliases: ["gm dope sync"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogAdd, gm: "gm cog add", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogUpdate, gm: "gm cog update", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogDelete, gm: "gm cog delete", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogGet, gm: "gm cog get", role: .read),
        VerbSpec(.dopeCogElementAdd, gm: "gm cog element-add", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogElementUpdate, gm: "gm cog element-update", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogElementDelete, gm: "gm cog element-delete", role: .record(agentPhases: nil)),

        // ── Diagrams ─────────────────────────────────────────────────────
        // `gm diagram from-dope` regenerates a canvas: DIAGRAM_INIT, then one
        // atomic DIAGRAM_BATCH_APPLY.
        VerbSpec(.diagramInit, gm: "gm diagram init", aliases: ["gm diagram from-dope"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.diagramList, gm: "gm diagram list", role: .read),
        VerbSpec(.diagramGet, gm: "gm diagram get", role: .read),
        VerbSpec(.diagramSearch, gm: "gm diagram search", role: .read),
        VerbSpec(.diagramNodeAdd, gm: "gm diagram element-add", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeUpdate, gm: "gm diagram element-update", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeDelete, gm: "gm diagram element-delete", role: .record(agentPhases: nil)),
        // `gm diagram update` is a one-mutation batch under the hood.
        VerbSpec(.diagramBatchApply, gm: "gm diagram batch-apply",
                 aliases: ["gm diagram update"], role: .record(agentPhases: nil)),
        VerbSpec(.diagramDelete, gm: "gm diagram delete", role: .record(agentPhases: nil)),
        VerbSpec(.diagramWriteRepo, gm: "gm diagram write-repo", role: .record(agentPhases: nil)),
        VerbSpec(.diagramIngest, gm: "gm diagram ingest", role: .record(agentPhases: nil)),
    ]
}
