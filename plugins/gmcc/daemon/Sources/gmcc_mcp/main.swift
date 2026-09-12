import Foundation
import GMCCDaemonKit

// gmcc_mcp — the GMCC MCP stdio server: the agent PEN surface as typed MCP
// tools. A thin client of the daemon socket beside gm and GMVibes — reuses
// DaemonClient/WireCodec verbatim and NEVER touches the db (single-writer
// invariant).
//
// Hand-rolled JSON-RPC 2.0 over newline-delimited stdio: exactly the three
// methods that matter (initialize, tools/list, tools/call) plus ping;
// notifications are ignored. Three methods do not justify a dependency —
// the daemon already hand-rolls its own wire envelope.
//
// THE SURFACE IS THE PEN, AND VerbRegistry DECLARES IT. Every tool below is
// a VerbSpec row carrying `pen:`; the primary's gate verbs (review rank,
// arch decide, prompt set-status, care-package seal) carry none, and the
// daemon refuses them to this client by caller role — the stamp is
// `DaemonClient(callerRole: .agent)` at the bottom of this file. Withholding
// a tool withholds the TOOL, never the capability (every agent also holds
// Bash), so the door is what enforces; the roster is what makes the door
// something an agent can comply with.
//
// READS MATTER AS MUCH AS WRITES: an agent that cannot read its own
// exploration/review/architecture rows through the pen will shell out to gm
// to get them, and then it is already in the CLI when it writes. Rating
// windows exist on explore_get/review_get for the same reason — renderResult
// caps a result at 80_000 bytes and an unnarrowable read is an incentive to
// leave.
//
// Registered by the plugin as server `pen`, so tools surface as
// mcp__plugin_gmcc_pen__<tool> (the plugin-scoped naming rule — a bare
// mcp__gmcc__ matcher never fires). Harness tool search defers tool schemas
// by default; this server declares `alwaysLoad` on its .mcp.json entry, so
// the pen is in every session's surface without a search and without holding
// up startup.

// MARK: - Minimal JSON value

enum JSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    static func parse(_ data: Data) -> JSON? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return from(raw)
    }

    static func from(_ raw: Any) -> JSON {
        switch raw {
        case let value as String: return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        case let value as [Any]: return .array(value.map(from))
        case let value as [String: Any]: return .object(value.mapValues(from))
        default: return .null
        }
    }

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15 ? Int64(value) as Any : value
        case .string(let value): return value
        case .array(let value): return value.map(\.any)
        case .object(let value): return value.mapValues(\.any)
        }
    }

    subscript(key: String) -> JSON? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var int64Value: Int64? {
        guard case .number(let value) = self else { return nil }
        return Int64(value)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var stringArray: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap(\.stringValue)
    }
}

struct ToolError: Error {
    let message: String
}

// MARK: - Argument helpers

struct Args {
    let json: JSON

    func string(_ key: String) throws -> String {
        guard let value = json[key]?.stringValue, !value.isEmpty else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    func optString(_ key: String) -> String? {
        json[key]?.stringValue
    }

    func int64(_ key: String) throws -> Int64 {
        guard let value = json[key]?.int64Value else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    func optInt(_ key: String) -> Int? {
        json[key]?.intValue
    }

    func optBool(_ key: String) -> Bool? {
        json[key]?.boolValue
    }

    func optStrings(_ key: String) -> [String]? {
        json[key]?.stringArray
    }

    /// The rating window shared by explore_get and review_get, mirroring the
    /// CLI's RatingWindowOptions: mutually exclusive, 0-999, A:B inclusive.
    /// Without it a pen read of a ranked finding set is all-or-nothing, and
    /// the 80_000-byte result cap turns "all" into a truncation.
    func ratingWindow() throws -> (full: Bool, min: Int?, max: Int?) {
        let full = optBool("full") ?? false
        let maxRating = optInt("max_rating")
        let range = optString("rating_range")
        let picked = [full, maxRating != nil, range != nil].filter { $0 }.count
        guard picked <= 1 else {
            throw ToolError(message: "full, max_rating, and rating_range are mutually exclusive")
        }
        if let range {
            let parts = range.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]),
                  (0...999).contains(low), (0...999).contains(high), low <= high else {
                throw ToolError(message: "rating_range expects A:B with 0 <= A <= B <= 999, got '\(range)'")
            }
            return (false, low, high)
        }
        if let maxRating {
            guard (0...999).contains(maxRating) else {
                throw ToolError(message: "max_rating must be 0-999")
            }
            return (false, nil, maxRating)
        }
        return (full, nil, nil)
    }
}

// MARK: - Tool registry

/// Which client serves a tool — i.e. what role the daemon is told the call
/// came from.
enum ToolAudience {
    /// Everything an agent may do. Served by the `.agent` client, and the
    /// daemon's role gate applies exactly as it always has.
    case agent
    /// One of the four gate doors. Served by the `.primary` client ONLY when
    /// the call carries a harness attestation saying the primary made it.
    case primaryDoor
}

struct Tool {
    let name: String
    let description: String
    /// {property name: (type, description, required)}
    let params: [(String, String, String, Bool)]
    /// Defaults to `.agent`, so a tool added without thinking about roles gets
    /// the restrictive side rather than a door.
    var audience: ToolAudience = .agent
    let run: (Args, DaemonClient) throws -> any Encodable

    var inputSchema: [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for (name, type, description, isRequired) in params {
            if type == "array" {
                properties[name] = ["type": "array", "items": ["type": "string"], "description": description]
            } else {
                properties[name] = ["type": type, "description": description]
            }
            if isRequired { required.append(name) }
        }
        return ["type": "object", "properties": properties, "required": required]
    }
}

/// Zero-uuid resolution shared by the bot tools: explicit prompt uuid →
/// ClientKey → the session resolved from CLAUDE_PROJECT_DIR/cwd.
private func botSelector(_ args: Args, _ client: DaemonClient) -> (String?, String?, String?) {
    let promptUuid = args.optString("prompt_uuid")
    var session: String?
    if promptUuid == nil {
        session = try? ContextBuilder.resolveSessionUuid(client)
    }
    return (promptUuid, ClientKey.resolve(), session)
}

/// The record reads are prompt-keyed, and an agent is rarely told a uuid —
/// so an explicit `prompt_uuid` wins, and otherwise the workflow BOT_GET
/// already resolves answers it. Same zero-uuid contract the bot tools have.
private func resolvePromptUuid(_ args: Args, _ client: DaemonClient) throws -> String {
    if let explicit = args.optString("prompt_uuid") { return explicit }
    let (prompt, key, session) = botSelector(args, client)
    return try client.botGet(BotGetRequest(
        promptUuid: prompt, clientKey: key, sessionUuid: session)).workflow.promptUuid
}

/// Shared schema rows for the two rating-windowed reads.
private let ratingWindowParams: [(String, String, String, Bool)] = [
    ("full", "boolean", "Return every finding as a full row (no stub partition)", false),
    ("max_rating", "number", "Widen/narrow the full-row window to ratings 0...N", false),
    ("rating_range", "string", "Full-row window as A:B (inclusive rating bounds)", false),
]

private let promptSelectorParam: (String, String, String, Bool) =
    ("prompt_uuid", "string", "Explicit prompt uuid (omit to resolve YOUR workflow's prompt)", false)

let tools: [Tool] = [
    Tool(
        name: "bot_next",
        description: "Current workflow phase + instructions + uuid bundle + gate blockers. Zero-uuid: resolves YOUR workflow.",
        params: [("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false)],
        run: { args, client in
            let (prompt, key, session) = botSelector(args, client)
            return try client.botNext(BotNextRequest(
                promptUuid: prompt, clientKey: key, sessionUuid: session))
        }),
    Tool(
        name: "bot_get",
        description: "The raw bot workflow row.",
        params: [("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false)],
        run: { args, client in
            let (prompt, key, session) = botSelector(args, client)
            return try client.botGet(BotGetRequest(
                promptUuid: prompt, clientKey: key, sessionUuid: session))
        }),
    Tool(
        name: "bot_current_prompt",
        description: "The workflow's prompt row — read the prompt without being told a uuid.",
        params: [("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false)],
        run: { args, client in
            let (prompt, key, session) = botSelector(args, client)
            let workflow = try client.botGet(BotGetRequest(
                promptUuid: prompt, clientKey: key, sessionUuid: session)).workflow
            return try client.getPrompt(PromptGetRequest(promptUuid: workflow.promptUuid))
        }),
    Tool(
        name: "bot_summary",
        description: "Fetch-or-open an exploration summary (identity is the self-reported agent_type; 'synthesis' is the prompt-level seal row the clarifier opens once everything is ranked).",
        params: [
            ("agent_type", "string", "aggressive|conservative|pragmatic|alternative|general|synthesis", true),
            ("agent_id", "string", "Self-reported agent id for dedup/tracking", false),
            ("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false),
        ],
        run: { args, client in
            let agentType = try args.string("agent_type")
            // No payload-granular synthesis guard here. Authorization is the
            // daemon's door, keyed on caller_role against VerbRegistry — and
            // the approved invariant is "no agent may call the PRIMARY doors;
            // any agent may seal synthesis once everything is ranked". The
            // merged clarifier opens this row (it never explored, so nothing
            // else can have opened one for it) and completes it in the same
            // pass; a guard here would have made that pass impossible.
            let (prompt, key, session) = botSelector(args, client)
            let workflow = try client.botGet(BotGetRequest(
                promptUuid: prompt, clientKey: key, sessionUuid: session)).workflow
            return try client.exploreOpen(ExploreOpenRequest(
                promptUuid: workflow.promptUuid,
                agentType: agentType,
                agentId: args.optString("agent_id")))
        }),
    Tool(
        name: "briefing_get",
        description: "Fetch a briefing + staleness. Zero-uuid form: pass only step and YOUR briefing resolves.",
        params: [
            ("briefing_uuid", "string", "Explicit briefing uuid", false),
            ("prompt_uuid", "string", "Owner prompt uuid", false),
            ("step", "string", "Briefing step (initial)", false),
        ],
        run: { args, client in
            var session: String?
            if args.optString("briefing_uuid") == nil, args.optString("prompt_uuid") == nil {
                session = try? ContextBuilder.resolveSessionUuid(client)
            }
            return try client.briefingGet(BriefingGetRequest(
                briefingUuid: args.optString("briefing_uuid"),
                promptUuid: args.optString("prompt_uuid"),
                sessionUuid: session,
                step: args.optString("step") ?? "initial",
                clientKey: ClientKey.resolve()))
        }),
    Tool(
        name: "briefing_complete",
        description: """
            building → ready: write the briefing's ref set (opinion-free; the daemon \
            stamps staleness + kbite briefs). ALL THREE ref classes are REQUIRED of \
            you: a briefing records what it LOOKED FOR, not only what it found. Pass \
            [] for a class you searched and came up empty on — that is a real answer. \
            Omitting a class is refused, because absent is indistinguishable from \
            never having looked.
            """,
        params: [
            ("briefing_uuid", "string", "The briefing to complete", true),
            ("expected_version", "number", "The briefing version this write was based on", true),
            ("dope_refs", "array", "Dope dot-path CODES (never uuids). Pass [] if you searched and found none — omitting this is refused", true),
            ("kbite_refs", "array", "Kbite file uuids. Pass [] if you searched and found none — omitting this is refused", true),
            ("file_change_refs", "array", "file_change uuids. Pass [] if there are none — omitting this is refused", true),
            ("agent_id", "string", "Self-reported agent id", false),
        ],
        run: { args, client in
            try client.briefingComplete(BriefingCompleteRequest(
                briefingUuid: try args.string("briefing_uuid"),
                expectedVersion: try args.int64("expected_version"),
                dopeRefs: args.optStrings("dope_refs"),
                kbiteRefs: args.optStrings("kbite_refs"),
                fileChangeRefs: args.optStrings("file_change_refs"),
                agentId: args.optString("agent_id")))
        }),
    Tool(
        name: "explore_key_file_add",
        description: "Add one key file to YOUR exploration summary (a kind=key_file finding; deduped per path).",
        params: [
            ("summary_uuid", "string", "Your exploration summary uuid", true),
            ("file_path", "string", "Repo-relative path", true),
        ],
        run: { args, client in
            try client.exploreKeyFileAdd(ExploreKeyFileAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                filePath: try args.string("file_path")))
        }),
    Tool(
        name: "explore_finding_add",
        description: "Insert an exploration finding (self-rate 0=critical…999=ignore; unranked blocks the synthesis seal).",
        params: [
            ("summary_uuid", "string", "Your exploration summary uuid", true),
            ("kind", "string", "persistence_model|implementation_pattern|existing_functionality|scope_creep_risk|general_relevant_change|key_file|other", true),
            ("title", "string", "Finding title", true),
            ("body", "string", "Finding body", true),
            ("file_path", "string", "Repo-relative anchor path", false),
            ("agent_name", "string", "Your methodology persona", true),
            ("agent_id", "string", "Self-reported agent id", false),
            ("rating", "number", "0-999 self-rating", false),
        ],
        run: { args, client in
            guard let kind = ExplorationFindingKind(rawValue: try args.string("kind")) else {
                throw ToolError(message: "unknown finding kind")
            }
            return try client.exploreFindingAdd(ExploreFindingAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                kind: kind,
                title: try args.string("title"),
                body: try args.string("body"),
                filePath: args.optString("file_path"),
                agentName: try args.string("agent_name"),
                agentId: args.optString("agent_id"),
                rating: args.optInt("rating")))
        }),
    Tool(
        name: "explore_complete",
        description: "Seal a summary with its overview — your own methodology row, or the synthesis row once every finding is ranked (it refuses while anything is unranked).",
        params: [
            ("summary_uuid", "string", "Your exploration summary uuid", true),
            ("expected_version", "number", "The summary version this write was based on", true),
            ("overview", "string", "Your overview narrative", true),
        ],
        run: { args, client in
            try client.exploreComplete(ExploreCompleteRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version"),
                overview: try args.string("overview")))
        }),
    Tool(
        name: "review_finding_add",
        description: "Insert a review finding (self-rate 0=critical…999=ignore).",
        params: [
            ("summary_uuid", "string", "The review summary uuid", true),
            ("kind", "string", "correctness_bug|spec_deviation|regression_risk|security|simplification|other", true),
            ("title", "string", "Finding title", true),
            ("body", "string", "Finding body", true),
            ("file_path", "string", "Repo-relative path", false),
            ("line_start", "number", "First line", false),
            ("line_end", "number", "Last line", false),
            ("agent_name", "string", "Your methodology persona", true),
            ("agent_id", "string", "Self-reported agent id", false),
            ("rating", "number", "0-999 self-rating", false),
        ],
        run: { args, client in
            guard let kind = ReviewFindingKind(rawValue: try args.string("kind")) else {
                throw ToolError(message: "unknown finding kind")
            }
            return try client.reviewFindingAdd(ReviewFindingAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                kind: kind,
                title: try args.string("title"),
                body: try args.string("body"),
                filePath: args.optString("file_path"),
                lineStart: args.optInt("line_start"),
                lineEnd: args.optInt("line_end"),
                agentName: try args.string("agent_name"),
                agentId: args.optString("agent_id"),
                rating: args.optInt("rating")))
        }),
    Tool(
        name: "clarify_question_add",
        description: "Insert a user-facing clarification question (+ordered options) while the summary is building.",
        params: [
            ("summary_uuid", "string", "The clarification summary uuid", true),
            ("question", "string", "The question text", true),
            ("options", "array", "Ordered pre-authored options", false),
            ("agent_name", "string", "Your persona", false),
            ("agent_id", "string", "Self-reported agent id", false),
        ],
        run: { args, client in
            try client.clarifyQuestionAdd(ClarifyQuestionAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                question: try args.string("question"),
                options: args.optStrings("options"),
                agentName: args.optString("agent_name"),
                agentId: args.optString("agent_id")))
        }),
    Tool(
        name: "clarify_note_add",
        description: "Insert an internal clarification note (weight 0=critical…999; any summary state).",
        params: [
            ("summary_uuid", "string", "The clarification summary uuid", true),
            ("body", "string", "The note text", true),
            ("confused_entity_uuid", "string", "Soft ref to the confusing entity", false),
            ("confused_entity_type", "string", "exploration_finding|briefing|question|other", false),
            ("weight", "number", "0-999 importance (0=critical)", false),
            ("question_uuid", "string", "Attach to an answered question", false),
            ("agent_name", "string", "Your persona", false),
            ("agent_id", "string", "Self-reported agent id", false),
        ],
        run: { args, client in
            try client.clarifyNoteAdd(ClarifyNoteAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                body: try args.string("body"),
                confusedEntityUuid: args.optString("confused_entity_uuid"),
                confusedEntityType: args.optString("confused_entity_type"),
                weight: args.optInt("weight"),
                questionUuid: args.optString("question_uuid"),
                agentName: args.optString("agent_name"),
                agentId: args.optString("agent_id")))
        }),
    Tool(
        name: "care_package_get",
        description: "The prompt's care package — the clarified-intent bundle downstream agents load.",
        params: [("prompt_uuid", "string", "The prompt uuid", true)],
        run: { args, client in
            try client.carePackageGet(CarePackageGetRequest(
                promptUuid: try args.string("prompt_uuid")))
        }),
    Tool(
        name: "care_ref_add",
        description: "Add one care package ref while building (dope code / kbite file / curated exploration COPY — never re-explore).",
        params: [
            ("package_uuid", "string", "The care package uuid", true),
            ("kind", "string", "dope|kbite|exploration", true),
            ("dope_code", "string", "Dope dot-path CODE (kind dope)", false),
            ("note", "string", "Curatorial note (kind dope)", false),
            ("kbite_file_uuid", "string", "Kbite file uuid (kind kbite)", false),
            ("title", "string", "Curated title (kind exploration)", false),
            ("body", "string", "Curated body (kind exploration)", false),
            ("file_path", "string", "Repo-relative anchor (kind exploration)", false),
            ("source_finding_uuid", "string", "Provenance ref (kind exploration)", false),
        ],
        run: { args, client in
            guard let kind = CarePackageRefKind(rawValue: try args.string("kind")) else {
                throw ToolError(message: "kind must be dope|kbite|exploration")
            }
            return try client.carePackageRefAdd(CarePackageRefAddRequest(
                packageUuid: try args.string("package_uuid"),
                kind: kind,
                dopeCode: args.optString("dope_code"),
                note: args.optString("note"),
                kbiteFileUuid: args.optString("kbite_file_uuid"),
                curatedTitle: args.optString("title"),
                curatedBody: args.optString("body"),
                filePath: args.optString("file_path"),
                sourceFindingUuid: args.optString("source_finding_uuid")))
        }),
    Tool(
        name: "arch_option_add",
        description: "Write YOUR methodology's architecture Option row (the architect pen; one per agent_name).",
        params: [
            ("summary_uuid", "string", "The architecture summary uuid", true),
            ("agent_name", "string", "Your methodology persona", true),
            ("agent_id", "string", "Self-reported agent id", false),
            ("body", "string", "Your full proposal (markdown)", true),
        ],
        run: { args, client in
            try client.archOptionAdd(ArchOptionAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                agentName: try args.string("agent_name"),
                agentId: args.optString("agent_id"),
                body: try args.string("body")))
        }),
    Tool(
        name: "file_change_add",
        description: "Record a file change against the current repo context (origin manual; the hook records Edit/Write itself).",
        params: [
            ("path", "string", "Repo-relative path", true),
            ("kind", "string", "edit|create|delete|rename (default edit)", false),
            ("prompt_uuid", "string", "Attribute to this prompt", false),
            ("agent_id", "string", "Self-reported agent id", false),
            ("agent_name", "string", "Self-reported persona", false),
        ],
        run: { args, client in
            let context = try ContextBuilder.ensureRequest()
            let kind = ChangeKind(rawValue: args.optString("kind") ?? "edit") ?? .edit
            return try client.addFileChange(FileChangeAdd(
                project: context.project,
                instance: context.instance,
                session: context.session,
                promptUuid: args.optString("prompt_uuid"),
                relativePath: try args.string("path"),
                changeKind: kind,
                ranges: [],
                autoAttribute: args.optString("prompt_uuid") == nil ? true : nil,
                agentId: args.optString("agent_id"),
                agentName: args.optString("agent_name"),
                origin: "manual"))
        }),
    Tool(
        name: "dope_search",
        description: "FTS over the session's dope tree (hits carry dot-paths).",
        params: [
            ("query", "string", "The search query", true),
            ("scope", "string", "prompt|session|project (default session)", false),
            ("session_uuid", "string", "Explicit session uuid", false),
            ("prompt_uuid", "string", "Prompt scope selector", false),
            ("limit", "number", "Max hits", false),
        ],
        run: { args, client in
            let scopeRaw = args.optString("scope") ?? "session"
            guard let scope = DopeSearchScope(rawValue: scopeRaw) else {
                throw ToolError(message: "scope must be prompt|session|project")
            }
            var session = args.optString("session_uuid")
            if session == nil, scope != .project {
                session = try? ContextBuilder.resolveSessionUuid(client)
            }
            return try client.dopeSearch(DopeSearchRequest(
                query: try args.string("query"),
                scope: scope,
                sessionUuid: session,
                promptUuid: args.optString("prompt_uuid"),
                limit: args.optInt("limit")))
        }),
    Tool(
        name: "kbite_search",
        description: "bm25-ranked kbite file stubs with briefs — read briefs, then kbite_file_get.",
        params: [
            ("query", "string", "The search query", true),
            ("limit", "number", "Max hits", false),
        ],
        run: { args, client in
            try client.searchKbites(KbiteSearchRequest(
                query: try args.string("query"),
                limit: args.optInt("limit")))
        }),
    Tool(
        name: "kbite_file_get",
        description: "One kbite file's digested content (may be null — raw sources live on the filesystem).",
        params: [("file_uuid", "string", "The kbite file uuid", true)],
        run: { args, client in
            try client.getKbiteFile(KbiteFileGetRequest(fileUuid: try args.string("file_uuid")))
        }),

    // ── Reading the record ───────────────────────────────────────────────
    //
    // The half of the pen that makes the other half usable: an agent reads
    // the prompt's own rows here instead of shelling out to `gm ... get`.
    // Every one is prompt-keyed and zero-uuid by default. explore_rank rides
    // along because it is the same reader's next move — read the findings,
    // calibrate them in one batch.

    Tool(
        name: "explore_get",
        description: "The prompt's exploration record: summaries, key files, findings inside the rating window, stubs outside it. Default window is ratings under 100; unranked findings are ALWAYS full rows (they are the work queue).",
        params: [
            promptSelectorParam,
            ("agent_type", "string", "Filter to one agent's summary (omit for all)", false),
        ] + ratingWindowParams,
        run: { args, client in
            let window = try args.ratingWindow()
            return try client.exploreGet(ExploreGetRequest(
                promptUuid: try resolvePromptUuid(args, client),
                agentType: args.optString("agent_type"),
                full: window.full,
                ratingMin: window.min,
                ratingMax: window.max))
        }),
    Tool(
        name: "explore_rank",
        description: "Batch-rank exploration findings PROMPT-wide: one atomic calibrated batch across every summary. One bad pair rejects the whole batch; 0 unranked is what lets the synthesis seal pass.",
        params: [
            ("ratings", "array", "\"<finding-uuid>:<0-999>\" pairs (0=critical, 999=tombstone)", true),
            promptSelectorParam,
        ],
        run: { args, client in
            let raw = args.optStrings("ratings") ?? []
            guard !raw.isEmpty else {
                throw ToolError(message: "pass at least one rating as \"<finding-uuid>:<0-999>\"")
            }
            let pairs: [FindingRating] = try raw.map { pair in
                let parts = pair.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, let rating = Int(parts[1]), (0...999).contains(rating) else {
                    throw ToolError(message: "rating '\(pair)' is not <finding-uuid>:<0-999>")
                }
                return FindingRating(findingUuid: String(parts[0]), rating: rating)
            }
            return try client.exploreRank(ExploreRankRequest(
                promptUuid: try resolvePromptUuid(args, client), ratings: pairs))
        }),
    Tool(
        name: "review_get",
        description: "The prompt's review record: summary, findings inside the rating window, stubs outside it. Same window semantics as explore_get.",
        params: [promptSelectorParam] + ratingWindowParams,
        run: { args, client in
            let window = try args.ratingWindow()
            return try client.reviewGet(ReviewGetRequest(
                promptUuid: try resolvePromptUuid(args, client),
                full: window.full,
                ratingMin: window.min,
                ratingMax: window.max))
        }),
    Tool(
        name: "clarify_get",
        description: "The prompt's clarification record: summary, questions (+answers), notes, and the care package with its dope staleness when one exists.",
        params: [promptSelectorParam],
        run: { args, client in
            try client.clarifyGet(ClarifyGetRequest(
                promptUuid: try resolvePromptUuid(args, client)))
        }),
    Tool(
        name: "arch_get",
        description: "The approved architecture with its implementation state: persistence changes before general changes, each joined to its recorded file changes, plus the touched-but-unplanned set. This is the implementation spec.",
        params: [promptSelectorParam],
        run: { args, client in
            try client.archGet(ArchGetRequest(
                promptUuid: try resolvePromptUuid(args, client)))
        }),
    Tool(
        name: "file_change_list",
        description: "Recorded file changes for the prompt (or an explicit session/path). What the machine believes you have touched — read it to check your own capture.",
        params: [
            promptSelectorParam,
            ("session_uuid", "string", "List a whole session instead of one prompt", false),
            ("path", "string", "Filter to one repo-relative path", false),
            ("limit", "number", "Max rows", false),
        ],
        run: { args, client in
            let session = args.optString("session_uuid")
            // An explicit session read is session-scoped; otherwise the
            // prompt is resolved the same way every other record read is.
            let prompt = session == nil ? try resolvePromptUuid(args, client) : args.optString("prompt_uuid")
            return try client.listFileChanges(FileChangeListRequest(
                sessionUuid: session,
                promptUuid: prompt,
                relativePath: args.optString("path"),
                limit: args.optInt("limit")))
        }),
    Tool(
        name: "dope_get",
        description: "The dope tree at a scope (prompt overlay or session base). Pass code to read one subtree by dot-path — the whole tree is large.",
        params: [
            ("code", "string", "Dot-path CODE of the subtree to read (omit for the whole tree)", false),
            ("prompt_uuid", "string", "Read this prompt's PROMPT scope instead of the session base", false),
            ("session_uuid", "string", "Explicit session uuid (default: YOUR session)", false),
            ("resolved", "boolean", "Merge the masking overlay over its base", false),
        ],
        run: { args, client in
            var session = args.optString("session_uuid")
            if session == nil { session = try? ContextBuilder.resolveSessionUuid(client) }
            guard let session else {
                throw ToolError(message: "could not resolve a session — pass session_uuid")
            }
            return try client.dopeGet(DopeGetRequest(
                sessionUuid: session,
                promptUuid: args.optString("prompt_uuid"),
                code: args.optString("code"),
                resolved: args.optBool("resolved")))
        }),
    Tool(
        name: "prompt_get",
        description: "One prompt row by uuid, with its artifacts, kbite codes, and change summary. (bot_current_prompt is the zero-uuid form of this.)",
        params: [("prompt_uuid", "string", "The prompt uuid", true)],
        run: { args, client in
            try client.getPrompt(PromptGetRequest(promptUuid: try args.string("prompt_uuid")))
        }),
] + makeFastPathTools() + makePrimaryDoorTools()

// MARK: - Upfront loading

// EVERY PEN TOOL LOADS UPFRONT, declared once as `"alwaysLoad": true` on this
// server's `.mcp.json` entry rather than per-tool here.
//
// The per-tool `_meta` flag this replaced existed for one reason: server-level
// alwaysLoad makes session startup WAIT for the server's tools (capped at the
// 5-second connect timeout), and the launcher used to run a release build
// before exec — so a session following a source edit would spend the whole
// budget in bash. The launcher no longer builds, so the wait is a socket
// connect and the reason is gone.
//
// WHAT THE OLD ARRANGEMENT COST: with six tools upfront and the rest deferred,
// an agent holding a correct frontmatter tool list still found every other pen
// call failing until it thought to run a ToolSearch by exact name — and nothing
// in any agent definition told it that step existed. From inside the agent that
// is indistinguishable from the server not being registered at all, which is
// exactly how it was reported. Loading the whole surface costs context; it buys
// the disappearance of a failure mode that reads as a lie.

// MARK: - The initialize instructions, generated from the registry

/// The `instructions` field of `initialize` — the one piece of prose the
/// harness loads at session start, ahead of any tool schema. It is GENERATED
/// from VerbRegistry so it cannot drift from the roster, ordered critical
/// first, and deliberately small (the budget below is ~2KB: this text is paid
/// for by every session the pen is loaded into).
// The pen sheet generator moved to GMCCDaemonKit as `PenSheet`. The
// SubagentStart hook hands spawned agents the same generated text, and two
// generators over one registry drift apart — which is how the retired CLI
// cheatsheet came to contradict the agent definitions it shipped beside.

/// Startup diagnostics on stderr (stdout belongs to the protocol): the roster
/// and the registry must be the same set. The build-time guard is
/// WorkflowSpecTests' parity assertion — this is the runtime echo of it, so a
/// mismatched binary says so in the MCP log instead of silently serving a
/// surface nobody declared.
@MainActor func validateRosterAgainstRegistry() {
    let served = Set(tools.map(\.name))
    let declared = VerbRegistry.penToolNames
    var lines: [String] = []
    for orphan in served.subtracting(declared).sorted() {
        lines.append("[gmcc_mcp] serves '\(orphan)' with no VerbSpec — the door has made no role decision about it")
    }
    for missing in declared.subtracting(served).sorted() {
        lines.append("[gmcc_mcp] VerbRegistry declares pen tool '\(missing)' but this binary does not serve it")
    }
    let instructionBytes = PenSheet.instructions.utf8.count
    if instructionBytes > 2_048 {
        lines.append("[gmcc_mcp] initialize instructions are \(instructionBytes) bytes (budget 2048)")
    }
    guard !lines.isEmpty else { return }
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

// MARK: - Rendering (byte-budgeted)

/// Tool results are the wire response as sorted-key JSON — the same shape
/// `--json` prints, which is the form agents parse. Budgeted under the MCP
/// output cap (rating windows on the big gets do the real limiting).
func renderResult(_ value: any Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    let budget = 80_000
    guard data.count > budget else {
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    // Clip BYTES (the budget's unit — a Character prefix could emit ~4x the
    // budget on multibyte payloads), then back off to a UTF-8 boundary by
    // dropping continuation bytes.
    var clippedData = data.prefix(budget)
    while let last = clippedData.last, last & 0b1100_0000 == 0b1000_0000 {
        clippedData = clippedData.dropLast()
    }
    if let last = clippedData.last, last & 0b1000_0000 != 0 {
        clippedData = clippedData.dropLast()
    }
    let clipped = String(data: Data(clippedData), encoding: .utf8) ?? "{}"
    return clipped + "\n… [TRUNCATED at \(budget) bytes — narrow the query (rating windows, limit) and retry]"
}

// MARK: - JSON-RPC loop

func writeMessage(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func respond(id: Any, result: [String: Any]) {
    writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
}

func respondError(id: Any, code: Int, message: String) {
    writeMessage(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

// Servers spawn with the project dir as cwd; CLAUDE_PROJECT_DIR is the
// stable root — chdir so GitContext.detect() resolves the right repo even
// if the harness launched us elsewhere.
if let projectDir = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"],
   !projectDir.isEmpty {
    FileManager.default.changeCurrentDirectoryPath(projectDir)
}

// TWO CLIENTS, NOT ONE MUTABLE ROLE. `DaemonClient.callerRole` is a `let` read
// inside a locked `request()` on an `@unchecked Sendable` type — flipping it
// per call would be a data race. Two sockets is both smaller and correct.
//
// The agent client serves every tool and is unchanged. The primary client
// serves the four gate doors and ONLY when the PreToolUse attestation says the
// primary is calling; an agent reaching for a door is handed the agent client
// and refused by the daemon, which is the same answer it has always got.
let client = DaemonClient(callerRole: .agent)
let primaryClient = DaemonClient(callerRole: .primary)
defer { client.close() }
defer { primaryClient.close() }

/// Resolve which client serves this call.
///
/// UNSTAMPED READS AS AN AGENT. The attestation is a positive literal written by
/// the PreToolUse hook, so a hook that did not run leaves no stamp at all — and
/// that must land on the restrictive side. Inferring the primary from absence is
/// precisely the forgery this closes: an agent does not know its own agent_id,
/// so omitting it is the DEFAULT path, not an exotic one.
func clientFor(_ tool: Tool, _ args: Args) -> DaemonClient {
    guard tool.audience == .primaryDoor else { return client }
    let attested = args.optString(HookRunner.attestKey)
    return attested == HookRunner.attestPrimary ? primaryClient : client
}

validateRosterAgainstRegistry()

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let message = JSON.parse(Data(line.utf8)) else { continue }
    let method = message["method"]?.stringValue ?? ""
    let id = message["id"]?.any
    // Notifications (no id) are consumed silently.
    guard let id, !(id is NSNull) else { continue }

    switch method {
    case "initialize":
        // Pin the protocol revision this server actually implements — never
        // echo the client's (claiming support for future revisions).
        respond(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": "gmcc-pen",
                "version": "\(GMCCWireProtocol.version)",
            ],
            // Loaded at session start, ahead of any tool schema — the only
            // place the pen gets to state its own contract.
            "instructions": PenSheet.instructions,
        ])
    case "ping":
        respond(id: id, result: [:])
    case "tools/list":
        respond(id: id, result: [
            "tools": tools.map { tool in
                var entry: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                ]
                return entry
            }
        ])
    case "tools/call":
        let name = message["params"]?["name"]?.stringValue ?? ""
        let arguments = Args(json: message["params"]?["arguments"] ?? .object([:]))
        guard let tool = tools.first(where: { $0.name == name }) else {
            respondError(id: id, code: -32602, message: "unknown tool '\(name)'")
            continue
        }
        do {
            let result = try tool.run(arguments, clientFor(tool, arguments))
            respond(id: id, result: [
                "content": [["type": "text", "text": try renderResult(result)]],
                "isError": false,
            ])
        } catch {
            let text: String
            switch error {
            case let toolError as ToolError:
                text = toolError.message
            case let clientError as DaemonClientError:
                text = "\(clientError)"
            default:
                text = "\(error)"
            }
            // Tool-level failures ride the result envelope (isError), never
            // a protocol error — the agent should read and react to them.
            respond(id: id, result: [
                "content": [["type": "text", "text": "ERROR: \(text)"]],
                "isError": true,
            ])
        }
    default:
        respondError(id: id, code: -32601, message: "method '\(method)' not supported")
    }
}
