import Foundation

/// The workflow phase registry: the per-variant ordered phase graph for the
/// daemon-held bot state machine, and the instruction text each phase hands
/// whoever asks for it.
///
/// Phase is DERIVED from db evidence at every BOT_NEXT — no stored cursor, so
/// resume is the only code path there is. Gates are evaluated by
/// BotWorkflowRepository against these codes, and a new phase or variant is an
/// entry here rather than a schema change.
///
/// Instruction prose is compiled into the binary (the Cheatsheet precedent)
/// and drift-guarded by WorkflowSpecTests, which asserts more than presence:
/// WHERE A PEN TOOL EXISTS, THE PROSE MUST NAME THE PEN TOOL. This text is
/// served verbatim through bot_next to the agents doing the work, so a block
/// that hands out a `gm` command has handed out the CLI, and an agent already
/// in the CLI writes from there too.
///
/// `gm` survives in exactly two places, and VerbRegistry is what says which:
/// the primary's four gate doors — gm prompt set-status, gm arch decide,
/// gm review rank, gm clarify package-complete — which no agent may walk
/// through, and verbs that have no pen tool at all.
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

    /// Compiled-in instruction text per (variant, phase). Less is more: each
    /// block is what its reader needs NOW — the tool, the gate, and nothing
    /// else. WorkflowSpecTests fails the build on an empty pair, and on a
    /// block that names a `gm` write the pen already covers.
    public static func instructions(variant: BotVariant, phase: Phase) -> String {
        switch phase {
        case .briefing:
            return """
            gm briefing open --prompt-uuid <prompt> --step initial (no pen tool — \
            opening the briefing is the primary's). Spawn the haiku doper: it orients \
            itself with mcp__plugin_gmcc_pen__bot_current_prompt and writes the ref set \
            with mcp__plugin_gmcc_pen__briefing_complete. Then gate on gm briefing get \
            --step initial --wait. The machine refuses to leave this phase until the \
            briefing row is ready.
            """
        case .explore:
            let agents = expectedExplorationAgents(for: variant)
                .map(\.rawValue).joined(separator: ", ")
            let spawnNote: String
            let clarifierNote: String
            switch variant {
            case .bot:
                spawnNote = "Explore IN CONTEXT (no subagents): open your general summary and write the finding rows yourself."
                clarifierNote = "run the merged clarifier pass yourself in context"
            case .rpi:
                spawnNote = "Spawn ONE general-persona explorer subagent (it adopts all methodology goals at once)."
                clarifierNote = "spawn ONE gmcc:clarifier"
            case .team:
                spawnNote = "One explorer per methodology, as teammates or a dynamic workflow — script code never writes; the agents hold the pen."
                clarifierNote = "spawn ONE gmcc:clarifier"
            }
            return """
            \(spawnNote) Every explorer works through the pen: \
            mcp__plugin_gmcc_pen__bot_summary opens its own row (agent_type: \(agents)), \
            mcp__plugin_gmcc_pen__explore_key_file_add and \
            mcp__plugin_gmcc_pen__explore_finding_add write it, and \
            mcp__plugin_gmcc_pen__explore_complete seals THAT row. Leave the findings \
            unranked here — calibration is cross-agent and belongs to one reader.
            When every expected row is complete: gm prompt set-status --status clarifying \
            (the primary's door; it creates the clarification summary), then \
            \(clarifierNote) for the merged pass — rank, seal the synthesis row, then \
            author the question and note suite. Sealing synthesis is what moves the \
            machine into clarify_open.
            """
        case .clarifyOpen:
            return """
            The merged clarifier pass — one reader, one sequence, all pen:
            1. mcp__plugin_gmcc_pen__explore_get — every summary and finding. The default \
            window is ratings under 100; unranked findings always come back as full rows.
            2. mcp__plugin_gmcc_pen__explore_rank — ONE atomic prompt-wide batch \
            (0 = critical … 999 = tombstone). The ratings are cross-agent: a rating means \
            the same thing whichever persona wrote the finding.
            3. mcp__plugin_gmcc_pen__bot_summary with agent_type synthesis — the clarifier \
            OPENS the synthesis row itself; nothing else has opened one for it. Then \
            mcp__plugin_gmcc_pen__explore_complete seals it with the cross-agent \
            synthesis. That seal is the prompt-level one and it refuses while any finding \
            is unranked.
            4. mcp__plugin_gmcc_pen__clarify_question_add (with ordered options) and \
            mcp__plugin_gmcc_pen__clarify_note_add (weight 0-999, 0 = critical), written \
            from the ranked record rather than from a re-read of the repo.
            The primary seals the suite with gm clarify seal when the pass returns.
            """
        case .clarifyUser:
            var text = """
            Ask the user each open question (AskUserQuestion; options mirror the option \
            rows), record with gm clarify answer --question-uuid (--select <option-uuid>... \
            and/or --answer text; --skip to skip). At most 2 generative follow-up passes: \
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
            gm clarify package-open --summary-uuid <clarification summary> (no pen tool — \
            the primary opens it), then curate through the pen: \
            mcp__plugin_gmcc_pen__care_ref_add with kind dope|kbite|exploration \
            (exploration entries are COPIES of ranked findings written with more intent — \
            never re-explore). Finish at the primary's door: gm clarify package-complete \
            --intent-file <clarified intent: backstory+goal+detail, clarified>. The intent \
            lives ONLY here — it is never written back to the prompt row. Then \
            gm clarify finalize (pure gate) and gm prompt set-status --status architecting.
            """
        case .archOptions:
            return """
            Spawn one architect per methodology. Each loads the clarified intent with \
            mcp__plugin_gmcc_pen__care_package_get — not raw exploration — and writes its \
            OWN proposal with mcp__plugin_gmcc_pen__arch_option_add (one row per \
            agent_name). Wait for every option before deciding.
            """
        case .architecture:
            if variant == .team {
                return """
                Read the options (gm arch get) and pick the winner at the primary's door: \
                gm arch decide --option-uuid <winner> --rationale-file P (stamps selected, \
                rejects siblings, records why — offer unused-option features to the user \
                later). Then expand ONLY the selected option into rows: persistence FIRST \
                (gm arch persist-add --change-kind add|modify|rename|delete --dope-ref \
                <entity code>; gm arch field-add --change-kind ... --renamed-from ... \
                --dope-property-ref <property code>), then gm arch general-add, then \
                gm arch summarize. Write each general-add row as the instruction its \
                implementer will execute, and name the file_path that implementer owns.
                """
            }
            return """
            Design in context (bot) or via your single subagent (rpi) from the clarified \
            record — in rpi the subagent PROPOSES and returns its proposal in its final \
            message; the primary is what persists it. The primary writes every row \
            db-natively: persistence rows FIRST (gm arch persist-add \
            --change-kind add|modify|rename|delete --dope-ref <entity code>; gm arch \
            field-add with --dope-property-ref for renames and deletes), then \
            gm arch general-add — each row the instruction its implementer will execute, \
            naming the file_path that implementer owns — then gm arch summarize. Those \
            four have no pen tool: they are the primary's, and the daemon refuses them \
            to an agent.
            """
        case .planGate:
            return """
            gm arch propose, then present the plan for user sign-off — ALWAYS include the \
            full persistence delta table (positive AND negative changes, dope refs shown). \
            Approve → gm arch approve + gm prompt set-status --status implementing (the \
            primary's door; it claims the activation). Modify → gm arch revise and return \
            to architecture.
            """
        case .implement:
            switch variant {
            case .bot:
                return """
                Implement in context, PERSISTENCE CHANGES FIRST — the persistence rows are \
                the contract the general rows are written against. Then prove it: run the \
                build loop this repo documents and report its real output, quoted; a \
                claim is not a result. Do NOT write or run test suites unless the prompt \
                asked for them. Your file writes are captured for you — there is nothing \
                to self-report. mcp__plugin_gmcc_pen__arch_get audits progress: planned \
                rows joined to what has actually been touched, plus the unplanned set.
                """
            case .rpi:
                return """
                Implement with up to 2 implementation subagents, PERSISTENCE CHANGES \
                FIRST. Give each agent only the file_path slice the plan assigned it, and \
                say plainly that another agent owns every other file. Each proves its work \
                by running the repo's documented build loop and reporting the real output; \
                none of them writes or runs tests unless the prompt asked. Capture is \
                automatic — no self-reporting. mcp__plugin_gmcc_pen__arch_get audits \
                progress.
                """
            case .team:
                return """
                Author the implementation workflow yourself, guided by this state: \
                PERSISTENCE CHANGES FIRST, then services and verbs, then frontend. Script \
                code is pure orchestration — every write happens inside an agent holding \
                the pen. Each agent takes only its assigned file_path slice and must not \
                touch another's. Each proves its work with the repo's documented build \
                loop and reports the real output; tests are not written or run unless the \
                prompt asked. Capture is automatic; gm bot reconcile at the gate is the \
                backstop for writes no turn could attribute. \
                mcp__plugin_gmcc_pen__arch_get audits progress.
                """
            }
        case .review:
            let spawn: String
            switch variant {
            case .bot: spawn = "Review in context against the plan and the recorded changes."
            case .rpi: spawn = "Spawn ONE general-persona reviewer subagent."
            case .team: spawn = "Run the review workflow — one reviewer per methodology."
            }
            return """
            gm prompt set-status --status reviewing (the primary's door), then \
            gm review open --prompt-uuid <prompt> (no pen tool — the primary opens it). \
            \(spawn) Reviewers scope themselves with mcp__plugin_gmcc_pen__arch_get and \
            mcp__plugin_gmcc_pen__file_change_list, read the record so far with \
            mcp__plugin_gmcc_pen__review_get, and write their findings with \
            mcp__plugin_gmcc_pen__review_finding_add. Calibrate at the primary's door \
            (gm review rank), then seal: gm review complete --verdict \
            approved|approved_with_nits|changes_requested (it refuses unranked findings).
            """
        case .reviewFix:
            return """
            Clarify fix intent with the user (fix all / fix critical / proceed), then run \
            the fix loop: every finding under rating 100 gets gm review resolve \
            --finding-uuid F --status fixed|accepted|wont_fix (legal after complete by \
            design — the fix loop runs post-seal). The fixes are implementation and carry \
            implementation's proof: the documented build loop, run and reported. Team: the \
            fixes themselves may run as a workflow.
            """
        case .done:
            return """
            gm prompt set-status --status done (the primary's door; it releases the \
            activation claim and closes the workflow row). Present the completion summary \
            — the db rows are the record, and there are no phase-history files.
            """
        }
    }
}
