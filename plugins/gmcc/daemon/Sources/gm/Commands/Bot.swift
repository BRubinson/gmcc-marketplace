import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm bot — the daemon-held workflow state machine (m0025) plus the wrapper
/// pen verbs spawned agents drive without uuid plumbing. Phase is DERIVED
/// from db evidence at every `next`; `gm prompt set-status` remains the ONLY
/// door that moves a prompt — the machine reports and refuses, never
/// bypasses. Zero-uuid resolution: caller's active workflow (ClientKey) →
/// activation-resolved prompt → the session's single active workflow; every
/// verb keeps an explicit --prompt-uuid escape hatch.
struct Bot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bot workflow machine: next, get, status, current_prompt, briefing, summary, reconcile.",
        subcommands: [
            Next.self, Get.self, Status.self, CurrentPrompt.self,
            BriefingPull.self, Summary.self, Reconcile.self, Sweep.self,
        ]
    )

    /// Shared zero-uuid selector.
    struct Selector: ParsableArguments {
        @Option(name: .long, help: "Explicit prompt (the shadowing-hazard escape hatch).")
        var promptUuid: String?
    }

    static func resolveWorkflow(
        _ client: DaemonClient, promptUuid: String?
    ) throws -> BotWorkflowRow {
        var session: String?
        if promptUuid == nil {
            session = try? ContextBuilder.resolveSessionUuid(client)
        }
        return try client.botGet(BotGetRequest(
            promptUuid: promptUuid,
            clientKey: ClientKey.resolve(),
            sessionUuid: session)).workflow
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Derive the current phase and print its instructions, uuid bundle, and gate blockers. The workflow's one navigation verb — resume IS first-run.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector

        func run() throws {
            let response = try withClient { client -> BotNextResponse in
                var session: String?
                if selector.promptUuid == nil {
                    session = try? ContextBuilder.resolveSessionUuid(client)
                }
                return try client.botNext(BotNextRequest(
                    promptUuid: selector.promptUuid,
                    clientKey: ClientKey.resolve(),
                    sessionUuid: session))
            }
            if output.json { printJSON(response) } else {
                let w = response.workflow
                print("[gm] bot [\(w.variant)] phase: \(response.phase) (prompt \(w.promptUuid))")
                if !response.gateBlockers.isEmpty {
                    print("  next-phase blockers:")
                    for blocker in response.gateBlockers { print("    - \(blocker)") }
                }
                print("")
                print(response.instructions)
                print("")
                let u = response.uuids
                print("  prompt: \(u.promptUuid)")
                print("  session: \(u.sessionUuid)")
                if let v = u.briefingUuid { print("  briefing: \(v)") }
                if let v = u.clarificationSummaryUuid { print("  clarification: \(v)") }
                if let v = u.carePackageUuid { print("  care package: \(v)") }
                if let v = u.architectureSummaryUuid { print("  architecture: \(v)") }
                if let v = u.reviewSummaryUuid { print("  review: \(v)") }
                for (agent, uuid) in u.explorationSummaryUuids.sorted(by: { $0.key < $1.key }) {
                    print("  exploration[\(agent)]: \(uuid)")
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "The raw workflow row (zero-uuid resolved like next).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector

        func run() throws {
            let workflow = try withClient { try Bot.resolveWorkflow($0, promptUuid: selector.promptUuid) }
            if output.json { printJSON(BotWorkflowResponse(workflow: workflow)) } else {
                print("[gm] workflow \(workflow.uuid) [\(workflow.variant)] \(workflow.status) — prompt \(workflow.promptUuid), last phase \(workflow.lastServedPhase ?? "-")")
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Workflow row + derived phase + gate blockers, human-rendered.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector

        func run() throws {
            let response = try withClient { client -> BotNextResponse in
                var session: String?
                if selector.promptUuid == nil {
                    session = try? ContextBuilder.resolveSessionUuid(client)
                }
                return try client.botNext(BotNextRequest(
                    promptUuid: selector.promptUuid,
                    clientKey: ClientKey.resolve(),
                    sessionUuid: session))
            }
            if output.json { printJSON(response) } else {
                let w = response.workflow
                print("[gm] workflow [\(w.variant)] \(w.status) — phase \(response.phase)")
                for blocker in response.gateBlockers { print("  blocked: \(blocker)") }
            }
        }
    }

    struct CurrentPrompt: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "current_prompt",
            abstract: "The workflow's prompt row — spawned agents read the prompt without being told a uuid.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector

        func run() throws {
            let response = try withClient { client -> PromptGetResponse in
                let workflow = try Bot.resolveWorkflow(client, promptUuid: selector.promptUuid)
                return try client.getPrompt(PromptGetRequest(promptUuid: workflow.promptUuid))
            }
            if output.json { printJSON(response) } else {
                let p = response.prompt
                print("[gm] prompt \(p.seq) \(p.name) (\(p.status), v\(p.version)) \(p.uuid)")
                if !p.goal.isEmpty { print("goal:\n\(p.goal)\n") }
                print("detail:\n\(p.detail)")
            }
        }
    }

    struct BriefingPull: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "briefing",
            abstract: "The workflow prompt's initial briefing (a thin wrapper over the briefing family's get).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector
        @Option(name: .long, help: "Briefing step (default initial).")
        var step: String = "initial"

        func run() throws {
            let response = try withClient { client -> BriefingGetResponse in
                let workflow = try Bot.resolveWorkflow(client, promptUuid: selector.promptUuid)
                return try client.briefingGet(BriefingGetRequest(
                    briefingUuid: nil, promptUuid: workflow.promptUuid,
                    sessionUuid: nil, step: step, clientKey: ClientKey.resolve()))
            }
            if output.json { printJSON(response) } else {
                let b = response.briefing
                print("[gm] briefing \(b.uuid) (step \(b.briefingForStep), \(b.status))")
                for ref in b.dopeRefs { print("  dope: \(ref.dopeCode)") }
                for ref in b.kbiteRefs { print("  kbite: \(ref.kbiteResourceFileUuid)") }
                for ref in b.fileChangeRefs { print("  file-change: \(ref.fileChangeUuid)") }
            }
        }
    }

    struct Summary: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch-or-open the caller's per-agent exploration summary — the one wrapper taking self-reported identity (ClientKey cannot distinguish sibling agents).")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector
        @Option(name: .long, help: "aggressive|conservative|pragmatic|alternative|general|synthesis")
        var agentType: String
        @Option(name: .long, help: "Self-reported agent id for dedup/tracking.")
        var agentId: String?

        func run() throws {
            let response = try withClient { client -> ExploreSummaryResponse in
                let workflow = try Bot.resolveWorkflow(client, promptUuid: selector.promptUuid)
                return try client.exploreOpen(ExploreOpenRequest(
                    promptUuid: workflow.promptUuid, agentType: agentType, agentId: agentId))
            }
            if output.json { printJSON(response) } else {
                let s = response.summary
                print("[gm] exploration [\(s.agentType)] \(response.created ? "created" : "exists"): \(s.uuid) (\(s.status), v\(s.version))")
            }
        }
    }

    // MARK: - The delta engine (reconcile and sweep are two skins on it)

    /// What one pass of the delta engine did. `entries` is what was (or
    /// would be) recorded, in git's order, so the caller owns all rendering.
    struct SweepOutcome {
        var entries: [GitSnapshot.Entry] = []
        var baselineEstablished = false
        var baselineAdvanced = false
        /// Set when the compare-and-swap lost: the rows are recorded, the
        /// cursor is not advanced, and a later sweep re-derives the rest.
        var baselineConflict: String?
        var recorded: Int { entries.count }
    }

    /// ONE engine, two triggers: `gm bot reconcile` (operator-facing, at
    /// phase gates) and `gm bot sweep` (the per-turn Stop/SubagentStop hook).
    /// A second delta path would be a second thing to keep correct.
    ///
    /// The caller MUST have resolved `workflow` already — that ordering is
    /// load-bearing for sweep, which otherwise pays a full tracked-tree
    /// re-hash on every turn of every booted repo just to discover it has no
    /// workflow to sweep.
    static func sweepDelta(
        _ client: DaemonClient,
        workflow: BotWorkflowRow,
        origin: String,
        agentId: String? = nil,
        agentName: String? = nil,
        dryRun: Bool = false
    ) throws -> SweepOutcome {
        var outcome = SweepOutcome()
        let snapshot = try GitSnapshot.workingTree()

        guard let baseline = workflow.reconcileGitHead else {
            // First contact: establish the baseline so PRE-EXISTING
            // working-tree dirt is never attributed to this prompt. No CAS —
            // there is nothing to compare against, and this matches what
            // gm prompt start/resume already do.
            if !dryRun {
                _ = try client.botSetBaseline(BotSetBaselineRequest(
                    promptUuid: workflow.promptUuid,
                    clientKey: ClientKey.resolve(),
                    gitTree: snapshot))
            }
            outcome.baselineEstablished = true
            return outcome
        }
        if baseline == snapshot { return outcome }

        // Precise prompt-era delta: tree-to-tree diff with rename
        // detection, NUL-separated (no C-quoting, full unicode).
        let entries = try GitSnapshot.diff(from: baseline, to: snapshot)

        // Kind-aware skip: a path already recorded for the prompt is
        // re-swept when git's kind DIFFERS from the last recorded
        // kind (an Edit-recorded file later deleted via Bash must
        // land as a delete).
        var lastKind: [String: String] = [:]
        for change in try client.listFileChanges(FileChangeListRequest(
            sessionUuid: nil, promptUuid: workflow.promptUuid,
            relativePath: nil, limit: 10_000)
        ).changes.reversed() {
            lastKind[change.relativePath] = change.changeKind
        }

        let context = try ContextBuilder.ensureRequest()
        for entry in entries where lastKind[entry.path] != entry.kind.rawValue {
            if !dryRun {
                _ = try client.addFileChange(FileChangeAdd(
                    project: context.project,
                    instance: context.instance,
                    session: context.session,
                    promptUuid: workflow.promptUuid,
                    relativePath: entry.path,
                    changeKind: entry.kind,
                    ranges: [],
                    agentId: agentId,
                    agentName: agentName,
                    origin: origin))
            }
            outcome.entries.append(entry)
        }
        if !dryRun {
            do {
                // COMPARE-AND-SWAP: advance only if the cursor is still the
                // tree we diffed from. A concurrent sweep that got there
                // first keeps its own window; ours is simply not closed.
                _ = try client.botSetBaseline(BotSetBaselineRequest(
                    promptUuid: workflow.promptUuid,
                    clientKey: ClientKey.resolve(),
                    gitTree: snapshot,
                    expectedGitTree: baseline))
                outcome.baselineAdvanced = true
            } catch let error as DaemonClientError {
                guard case .server(let payload) = error else { throw error }
                outcome.baselineConflict = payload.message
            }
        }
        return outcome
    }

    /// A one-line, status-line-safe rendering of why a sweep did nothing.
    static func refusalReason(_ error: Error) -> String {
        if let error = error as? DaemonClientError {
            switch error {
            case .unreachable(let message): return "daemon unreachable: \(message)"
            case .protocolMismatch(let message, _): return "protocol mismatch: \(message)"
            case .server(let payload): return payload.message
            case .wire(let message): return "wire error: \(message)"
            }
        }
        return "\(error)"
    }

    struct Reconcile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "The completeness channel: diff the working tree against the workflow's baseline snapshot and record only PROMPT-ERA changes the hook never saw (origin=reconcile, real delete/rename kinds). Pre-existing working-tree dirt is excluded by the baseline; run at phase gates.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector
        @Flag(name: .long, help: "Report what WOULD be recorded without writing.")
        var dryRun = false

        func run() throws {
            try withClient { client in
                let workflow = try Bot.resolveWorkflow(client, promptUuid: selector.promptUuid)
                let outcome = try Bot.sweepDelta(
                    client, workflow: workflow,
                    origin: FileChangeOrigin.reconcile, dryRun: dryRun)

                if outcome.baselineEstablished {
                    print("[gm] reconcile: baseline established — pre-existing dirt excluded; future sweeps diff against it")
                    return
                }
                if outcome.entries.isEmpty, !outcome.baselineAdvanced, outcome.baselineConflict == nil {
                    print("[gm] reconcile: no changes since the baseline — nothing to sweep")
                    return
                }
                for entry in outcome.entries {
                    print("  \(dryRun ? "would record" : "recorded"): \(entry.kind.rawValue) \(entry.path)")
                }
                let tail: String
                if let conflict = outcome.baselineConflict {
                    tail = "; baseline NOT advanced — \(conflict)"
                } else {
                    tail = dryRun ? "" : "; baseline advanced"
                }
                print("[gm] reconcile: \(outcome.recorded) unhooked change(s)\(dryRun ? " (dry run)" : "") swept\(tail)")
            }
        }
    }

    /// The per-turn skin on the same engine. Called from matcherless
    /// Stop/SubagentStop, where the ONLY acceptable failure is a quiet one —
    /// so every error becomes a `refused` string in the payload and the
    /// command still exits 0. The hook caches this payload and the subagent
    /// status line reads the cache, which is what lets a command that runs on
    /// every refresh tick answer "which phase, what is blocking" without ever
    /// spawning gm.
    struct Sweep: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Per-turn capture: the reconcile engine under a hook-safe skin. Records the turn's delta (origin=turn, real delete/rename kinds) and returns the phase + blockers the status line renders. Ambiguous workflow ownership is REFUSED, never guessed. Always exits 0.")

        @OptionGroup var output: OutputOptions
        @OptionGroup var selector: Selector
        @Option(name: .long, help: "Self-reported agent id of the turn that just ended (best-effort attribution).")
        var agentId: String?
        @Option(name: .long, help: "Self-reported agent name of the turn that just ended.")
        var agentName: String?

        func run() throws {
            var payload = BotSweepPayload()
            do {
                try withClient { client in
                    // A4: RESOLVE THE OWNER BEFORE THE SNAPSHOT. Two active
                    // workflows in one repo is a normal state, and guessing
                    // between them writes rows onto the wrong prompt at
                    // per-turn frequency. resolve() takes the workflow this
                    // session's client key claims and REFUSES when more than
                    // one is in play — that refusal is the correct answer,
                    // not a failure to work around. Ordering also matters on
                    // its own: a turn with no workflow must not pay a full
                    // tracked-tree re-hash to find that out.
                    let workflow: BotWorkflowRow
                    do {
                        workflow = try Bot.resolveWorkflow(client, promptUuid: selector.promptUuid)
                    } catch {
                        payload.refused = Bot.refusalReason(error)
                        return
                    }
                    payload.promptUuid = workflow.promptUuid

                    let outcome = try Bot.sweepDelta(
                        client, workflow: workflow,
                        origin: FileChangeOrigin.turn,
                        agentId: agentId, agentName: agentName)
                    payload.recorded = outcome.recorded
                    payload.baselineConflict = outcome.baselineConflict

                    // Phase + blockers from the invocation the hook is
                    // already making — gap 6 paid for by gap 2's fix.
                    let next = try client.botNext(BotNextRequest(
                        promptUuid: workflow.promptUuid,
                        clientKey: ClientKey.resolve(),
                        sessionUuid: nil))
                    payload.phase = next.phase
                    payload.blockers = next.gateBlockers
                    payload.variant = next.workflow.variant
                }
            } catch {
                payload.refused = payload.refused ?? Bot.refusalReason(error)
            }
            if output.json { printJSON(payload) } else {
                if let refused = payload.refused {
                    print("[gm] sweep: refused — \(refused)")
                    return
                }
                print("[gm] sweep: \(payload.recorded) change(s) recorded — phase \(payload.phase ?? "-")")
                for blocker in payload.blockers { print("  blocked: \(blocker)") }
            }
        }
    }
}

/// The `gm bot sweep --json` contract, consumed by gmcc_turn_sweep.sh and —
/// through its cache file — by the subagent status line.
///
/// Deliberately has NO per-agent rows: the intent asked for "which prompt
/// each agent is writing to", but the per-task JSON the status line receives
/// carries no id that joins to a file_change row, so the honest delivered
/// surface is one session-level phase/blocker line. Caching a field no
/// consumer can use would only look like the feature.
struct BotSweepPayload: Codable {
    var recorded: Int = 0
    var promptUuid: String?
    var variant: String?
    var phase: String?
    var blockers: [String] = []
    /// Why nothing was swept, in words a status line can show. Ambiguous
    /// workflow ownership lands here rather than in a guessed row.
    var refused: String?
    /// Rows were recorded but the baseline cursor was not advanced because a
    /// concurrent sweep moved it first. Not an error — the next sweep closes
    /// the remaining window.
    var baselineConflict: String?
}

/// Working-tree snapshotting for gm bot reconcile/sweep: a THROWAWAY git
/// tree object captures the exact working-tree state (tracked + untracked,
/// .gitignore honored) without touching the real index, so two snapshots
/// diff with git's own rename/delete fidelity. Client-side only — the
/// daemon never shells out.
///
/// EVERY invocation is pinned to the repo TOPLEVEL (`git -C`), and the
/// staging pathspec is the repo-root magic `:/`, never `.`. Without both,
/// the snapshot is cwd-relative: run from `plugins/gmcc/daemon` — which is
/// where the documented build loop puts you — it silently drops every
/// change outside that subtree (agents/, hooks/, scripts/, skills/,
/// gmvibes/, .gmcc/) and the sweep under-records with no error anywhere.
enum GitSnapshot {
    struct Entry {
        let path: String
        let kind: ChangeKind
    }

    /// The repo toplevel, resolved once per process. All paths git reports
    /// are relative to it, which is also the repo-relative form file_change
    /// rows are normalized to.
    /// gm is a single-threaded CLI process; the precedent is StoreCore's
    /// shared formatter.
    nonisolated(unsafe) private static var cachedToplevel: String?

    static func toplevel() throws -> String {
        if let cachedToplevel { return cachedToplevel }
        // The one unpinned call — it is what discovers the pin.
        let resolved = try exec(["rev-parse", "--show-toplevel"], indexFile: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else {
            throw ValidationError("not inside a git repository — run gm bot reconcile inside the instance repo")
        }
        cachedToplevel = resolved
        return resolved
    }

    /// `git add -A` into a temp index + write-tree = the tree SHA of the
    /// working tree right now.
    static func workingTree() throws -> String {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmcc-reconcile-\(getpid())-\(UInt32.random(in: 0..<UInt32.max)).index").path
        defer { try? FileManager.default.removeItem(atPath: temp) }
        // Seed from HEAD so unchanged files stay cheap, then stage the world
        // — `:/` is "everything from the repo root", cwd-independent.
        _ = try run(["read-tree", "HEAD"], indexFile: temp)
        _ = try run(["add", "-A", "--", ":/"], indexFile: temp)
        return try run(["write-tree"], indexFile: temp)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// NUL-separated tree diff with rename detection. A rename yields a
    /// delete for the vacated path + a rename for the new one.
    static func diff(from baseline: String, to snapshot: String) throws -> [Entry] {
        let raw = try run(["diff-tree", "-r", "-z", "-M", "--name-status", baseline, snapshot],
                          indexFile: nil)
        var entries: [Entry] = []
        let fields = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        while index < fields.count {
            let status = fields[index]
            if status.hasPrefix("R") || status.hasPrefix("C") {
                guard index + 2 < fields.count else { break }
                let oldPath = fields[index + 1]
                let newPath = fields[index + 2]
                if status.hasPrefix("R") {
                    entries.append(Entry(path: oldPath, kind: .delete))
                    entries.append(Entry(path: newPath, kind: .rename))
                } else {
                    entries.append(Entry(path: newPath, kind: .create))
                }
                index += 3
                continue
            }
            guard index + 1 < fields.count else { break }
            let path = fields[index + 1]
            switch status.first {
            case "A": entries.append(Entry(path: path, kind: .create))
            case "D": entries.append(Entry(path: path, kind: .delete))
            default: entries.append(Entry(path: path, kind: .edit))
            }
            index += 2
        }
        return entries
    }

    /// Every git call except toplevel discovery runs pinned to the repo root.
    private static func run(_ arguments: [String], indexFile: String?) throws -> String {
        try exec(["-C", try toplevel()] + arguments, indexFile: indexFile)
    }

    private static func exec(_ arguments: [String], indexFile: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        if let indexFile {
            var env = ProcessInfo.processInfo.environment
            env["GIT_INDEX_FILE"] = indexFile
            process.environment = env
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            throw ValidationError(
                "git \(arguments.joined(separator: " ")) failed — run gm bot reconcile inside the instance repo")
        }
        return text
    }
}
