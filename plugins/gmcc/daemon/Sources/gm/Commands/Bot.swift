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
            BriefingPull.self, Summary.self, Reconcile.self,
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
                let snapshot = try GitSnapshot.workingTree()

                guard let baseline = workflow.reconcileGitHead else {
                    // First contact: establish the baseline so PRE-EXISTING
                    // working-tree dirt is never attributed to this prompt.
                    if !dryRun {
                        _ = try client.botSetBaseline(BotSetBaselineRequest(
                            promptUuid: workflow.promptUuid,
                            clientKey: ClientKey.resolve(),
                            gitTree: snapshot))
                    }
                    print("[gm] reconcile: baseline established (\(snapshot.prefix(12))) — pre-existing dirt excluded; future sweeps diff against it")
                    return
                }
                if baseline == snapshot {
                    print("[gm] reconcile: no changes since the baseline — nothing to sweep")
                    return
                }

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
                var swept = 0
                for entry in entries where lastKind[entry.path] != entry.kind.rawValue {
                    if dryRun {
                        print("  would record: \(entry.kind.rawValue) \(entry.path)")
                        swept += 1
                        continue
                    }
                    _ = try client.addFileChange(FileChangeAdd(
                        project: context.project,
                        instance: context.instance,
                        session: context.session,
                        promptUuid: workflow.promptUuid,
                        relativePath: entry.path,
                        changeKind: entry.kind,
                        ranges: [],
                        origin: "reconcile"))
                    print("  recorded: \(entry.kind.rawValue) \(entry.path)")
                    swept += 1
                }
                if !dryRun {
                    _ = try client.botSetBaseline(BotSetBaselineRequest(
                        promptUuid: workflow.promptUuid,
                        clientKey: ClientKey.resolve(),
                        gitTree: snapshot))
                }
                print("[gm] reconcile: \(swept) unhooked change(s)\(dryRun ? " (dry run)" : "") swept; baseline advanced")
            }
        }
    }
}

/// Working-tree snapshotting for gm bot reconcile: a THROWAWAY git tree
/// object captures the exact working-tree state (tracked + untracked,
/// .gitignore honored) without touching the real index, so two snapshots
/// diff with git's own rename/delete fidelity. Client-side only — the
/// daemon never shells out.
enum GitSnapshot {
    struct Entry {
        let path: String
        let kind: ChangeKind
    }

    /// `git add -A` into a temp index + write-tree = the tree SHA of the
    /// working tree right now.
    static func workingTree() throws -> String {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmcc-reconcile-\(getpid())-\(UInt32.random(in: 0..<UInt32.max)).index").path
        defer { try? FileManager.default.removeItem(atPath: temp) }
        // Seed from HEAD so unchanged files stay cheap, then stage the world.
        _ = try run(["read-tree", "HEAD"], indexFile: temp)
        _ = try run(["add", "-A", "."], indexFile: temp)
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

    private static func run(_ arguments: [String], indexFile: String?) throws -> String {
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
            throw ValidationError("git \(arguments.first ?? "") failed — run gm bot reconcile inside the instance repo")
        }
        return text
    }
}
