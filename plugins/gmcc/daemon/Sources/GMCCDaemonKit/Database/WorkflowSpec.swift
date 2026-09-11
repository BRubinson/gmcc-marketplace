import Foundation

/// The workflow phase registry — BriefingStepSpec scaled up (m0025).
///
/// Per-variant ordered phase graphs for the daemon-held bot state machine.
/// Phase is DERIVED from db evidence at every BOT_NEXT (no stored cursor —
/// resume IS the first-run code path); gates are evaluated by
/// BotWorkflowRepository against these codes. New phases and variants are
/// REGISTRY ENTRIES, never migrations (bot_workflow.variant/phase are
/// CHECKless vocabulary columns per the post-m0021 rule).
///
/// Instruction prose is compiled into the binary (the Cheatsheet precedent)
/// and drift-guarded by WorkflowSpecTests: every (variant, phase) pair must
/// carry non-empty instructions. gm prompt set-status remains the ONLY door
/// that moves a prompt — instruction text names the exact command when a
/// status gate is met; the machine never bypasses the door.
public enum WorkflowSpec {

    /// Phase codes, in canonical order of appearance across variants.
    public enum Phase: String, CaseIterable, Sendable {
        case briefing
        case explore
        case clarifyOpen = "clarify_open"
        case clarifyUser = "clarify_user"
        case carePackage = "care_package"
        case archOptions = "arch_options"
        case architecture
        case planGate = "plan_gate"
        case implement
        case review
        case reviewFix = "review_fix"
        case done
    }

    /// The ordered phase graph per variant. `task` is deliberately absent —
    /// its write-nothing contract means no workflow row exists to walk.
    public static func phases(for variant: BotVariant) -> [Phase] {
        switch variant {
        case .bot:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser,
                    .architecture, .planGate, .implement, .review, .reviewFix, .done]
        case .rpi:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                    .architecture, .planGate, .implement, .review, .reviewFix, .done]
        case .team:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                    .archOptions, .architecture, .planGate, .implement, .review,
                    .reviewFix, .done]
        }
    }

    /// The exploration agent set each variant must complete before leaving
    /// the explore phase (the synthesis row is gated separately — its
    /// complete IS the prompt-level seal).
    public static func expectedExplorationAgents(for variant: BotVariant) -> [ExplorationAgentType] {
        switch variant {
        case .bot, .rpi:
            return [.general]
        case .team:
            return [.aggressive, .conservative, .pragmatic, .alternative]
        }
    }

    /// Compiled-in instruction text per (variant, phase). Less is more:
    /// each block is what the orchestrating agent needs NOW — verbs, gates,
    /// and nothing else. WorkflowSpecTests fails the build on an empty pair.
    public static func instructions(variant: BotVariant, phase: Phase) -> String {
        switch phase {
        case .briefing:
            return """
            Open the initial briefing (gm briefing open --prompt-uuid <prompt> --step initial), \
            spawn the haiku doper (it pulls the prompt itself via gm bot verbs), then gate on \
            gm briefing get --step initial --wait. The machine refuses to leave this phase \
            until the briefing row is ready.
            """
        case .explore:
            let agents = expectedExplorationAgents(for: variant)
                .map(\.rawValue).joined(separator: ", ")
            let spawnNote: String
            switch variant {
            case .bot:
                spawnNote = "Explore IN CONTEXT (no subagents): open your general summary and write finding rows yourself."
            case .rpi:
                spawnNote = "Spawn ONE general-persona explorer subagent (it adopts all methodology goals at once)."
            case .team:
                spawnNote = "Author a dynamic workflow (or spawn teammates) — one explorer per methodology; script code never touches gm, agents hold the pen."
            }
            return """
            gm explore open --prompt-uuid <prompt> --agent-type <type> per expected agent \
            (\(agents)). \(spawnNote) Each explorer completes its OWN summary \
            (gm explore complete). Then rank prompt-wide (gm explore rank --prompt-uuid) — \
            team runs the reranker agent, bot/rpi self-ratings stand — open the synthesis \
            summary (--agent-type synthesis) and complete it with the cross-agent synthesis: \
            that completion is the prompt-level seal and refuses while anything is unranked.
            """
        case .clarifyOpen:
            return """
            gm prompt set-status --status clarifying (locks content; creates the summary). \
            Add user questions (gm clarify question-add --option ... repeatable) and internal notes \
            (gm clarify note-add, weight 0-999, 0 = critical) from the ranked exploration. \
            Seal the suite with gm clarify seal when the initial pass is complete.
            """
        case .clarifyUser:
            var text = """
            Ask the user each open question (AskUserQuestion; options mirror the option rows), \
            record with gm clarify answer --question-uuid (--select <option-uuid>... and/or \
            --answer text; --skip to skip). At most 2 generative follow-up passes: \
            question-add stays legal while the summary is answering, so add the follow-ups \
            and ask them in the same conversation.
            """
            if variant == .bot {
                text += """
                 When every question is answered or skipped: gm clarify finalize \
                --summary-uuid <clarification> --expected-version V (pure gate), then \
                gm prompt set-status --status architecting.
                """
            }
            return text
        case .carePackage:
            return """
            gm clarify package-open --summary-uuid <clarification summary>, then curate: \
            package-add --kind dope|kbite|exploration (exploration entries are COPIES of \
            ranked findings with more intentional text — never re-explore). Finish with \
            gm clarify package-complete --intent-file <clarified intent: backstory+goal+detail, \
            clarified>. The intent lives ONLY here — it is never written to the prompt row. \
            Then gm clarify finalize (pure gate) and gm prompt set-status --status architecting.
            """
        case .archOptions:
            return """
            Spawn one architect per methodology; each writes its OWN option row \
            (gm arch option-add --summary-uuid <arch summary> --agent-name <methodology> \
            --body-file P). Architects load the care package (gm clarify package-get) — \
            not raw exploration. Wait for all options before deciding.
            """
        case .architecture:
            if variant == .team {
                return """
                Read the options (gm arch get), pick the winner: gm arch decide \
                --option-uuid <winner> --rationale-file P (stamps selected, rejects \
                siblings, records why — offer unused-option features to the user later). \
                Then expand ONLY the selected option into rows: persistence first \
                (gm arch persist-add --change-kind add|modify|rename|delete --dope-ref \
                <entity code>; gm arch field-add --change-kind ... --renamed-from ... \
                --dope-property-ref <property code>), then general-add, then summarize.
                """
            }
            return """
            Design in context (bot) or via your single subagent (rpi) from the clarified \
            record. Persist db-natively: persistence rows FIRST (gm arch persist-add \
            --change-kind add|modify|rename|delete --dope-ref <entity code>; gm arch \
            field-add with --dope-property-ref for renames/deletes), then general-add, \
            then summarize.
            """
        case .planGate:
            return """
            gm arch propose, then present the plan for user sign-off — ALWAYS include the \
            full persistence delta table (positive AND negative changes, dope refs shown). \
            Approve → gm arch approve + gm prompt set-status --status implementing (claims \
            the activation). Modify → gm arch revise and return to architecture.
            """
        case .implement:
            switch variant {
            case .bot:
                return """
                Implement in context, persistence changes first. Edit/Write changes are \
                hook-recorded; record Bash-driven writes with gm file-change add. Run \
                gm bot reconcile at the end to sweep unhooked writes (delete/rename \
                fidelity). gm arch get audits progress.
                """
            case .rpi:
                return """
                Implement with up to 2 implementation subagents, persistence changes first. \
                Hook records Edit/Write; gm file-change add for Bash writes; gm bot \
                reconcile sweeps the gap at the end. gm arch get audits progress.
                """
            case .team:
                return """
                Author the implementation workflow yourself, guided by this state: \
                persistence changes first, then services/verbs, then frontend, tests if \
                requested. Script code is pure orchestration — every gm write happens \
                inside agent() subagents. Run gm bot reconcile at the gate: workflow \
                Bash writes are invisible to the hook. gm arch get audits progress.
                """
            }
        case .review:
            let spawn: String
            switch variant {
            case .bot: spawn = "Review in context against your general summary."
            case .rpi: spawn = "Spawn ONE general-persona reviewer subagent."
            case .team: spawn = "Run the review workflow — one reviewer per methodology, then the reranker."
            }
            return """
            gm prompt set-status --status reviewing, gm review open --prompt-uuid <prompt>. \
            \(spawn) Reviewers write finding rows themselves. Seal with gm review complete \
            --verdict approved|approved_with_nits|changes_requested (refuses unranked \
            findings).
            """
        case .reviewFix:
            return """
            Clarify fix intent with the user (fix all / fix critical / proceed), then run \
            the fix loop: every finding under rating 100 gets gm review resolve \
            --finding-uuid F --status fixed|accepted|wont_fix (works after complete by \
            design). Team: the fixes themselves may run as a workflow.
            """
        case .done:
            return """
            gm prompt set-status --status done (releases the activation claim and closes \
            the workflow row). Present the completion summary — db rows are the record; \
            no phase-history files.
            """
        }
    }
}
