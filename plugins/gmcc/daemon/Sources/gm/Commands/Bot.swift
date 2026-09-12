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
        abstract: "Bot workflow machine: next, get, status, current_prompt, briefing, summary.",
        subcommands: [
            Next.self, Get.self, Status.self, CurrentPrompt.self,
            BriefingPull.self, Summary.self,
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
}
