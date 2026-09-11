import Foundation
import GMCCDaemonKit

// gmcc_mcp — the GMCC MCP stdio server (m0025): the agent PEN surface as
// typed MCP tools. A THIRD thin client of the daemon socket beside gm and
// GMVibes — reuses DaemonClient/WireCodec verbatim and NEVER touches the db
// (single-writer invariant).
//
// Hand-rolled JSON-RPC 2.0 over newline-delimited stdio: exactly the three
// methods that matter (initialize, tools/list, tools/call) plus ping;
// notifications are ignored. Three methods do not justify a dependency —
// the daemon already hand-rolls its own wire envelope. Fallback if this
// ever fights back: modelcontextprotocol/swift-sdk (no schema impact).
//
// The tool surface is DELIBERATELY the pen: primary-only verbs (rank, the
// seal gates, decide, set-status) are NOT exposed — an agent physically
// lacks the primary's verbs, which enforces the pen contract by
// construction rather than by prose. gm remains the canonical CLI for
// humans, hooks, and scripts.
//
// Registered by the plugin as server `pen`, so tools surface as
// mcp__plugin_gmcc_pen__<tool> (the plugin-scoped naming rule — a bare
// mcp__gmcc__ matcher never fires).

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

    func optStrings(_ key: String) -> [String]? {
        json[key]?.stringArray
    }
}

// MARK: - Tool registry

struct Tool {
    let name: String
    let description: String
    /// {property name: (type, description, required)}
    let params: [(String, String, String, Bool)]
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
        description: "Fetch-or-open YOUR per-agent exploration summary (identity is self-reported agent_type; synthesis is refused — the seal is the primary's).",
        params: [
            ("agent_type", "string", "aggressive|conservative|pragmatic|alternative|general", true),
            ("agent_id", "string", "Self-reported agent id for dedup/tracking", false),
            ("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false),
        ],
        run: { args, client in
            let agentType = try args.string("agent_type")
            // The synthesis row is the prompt-level SEAL — the primary's,
            // never a pen agent's. Without this the pen contract leaks:
            // bot_summary(synthesis) + explore_complete would let any agent
            // seal the prompt.
            guard agentType != ExplorationAgentType.synthesis.rawValue else {
                throw ToolError(message: "agent_type 'synthesis' is the primary's seal row — pen agents open their own methodology summary")
            }
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
        description: "building → ready: write the briefing's ref set (opinion-free; the daemon stamps staleness + kbite briefs).",
        params: [
            ("briefing_uuid", "string", "The briefing to complete", true),
            ("expected_version", "number", "The briefing version this write was based on", true),
            ("dope_refs", "array", "Dope dot-path CODES (never uuids)", false),
            ("kbite_refs", "array", "Kbite file uuids", false),
            ("file_change_refs", "array", "file_change uuids", false),
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
        description: "Seal YOUR OWN summary with its overview (agents complete only their own row — the synthesis row is the primary's).",
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
                clientKey: ClientKey.resolve(),
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
]

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

let client = DaemonClient()
defer { client.close() }

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
        ])
    case "ping":
        respond(id: id, result: [:])
    case "tools/list":
        respond(id: id, result: [
            "tools": tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                ] as [String: Any]
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
            let result = try tool.run(arguments, client)
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
