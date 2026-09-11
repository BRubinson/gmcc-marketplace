---
name: gm_bot_team
description: Agent-team GMCC workflow (variant team). Dynamic workflows drive briefing+explore+clarify-open, implementation, and review-fix; four methodology personas per fan-out phase; architecture optioning with the decide gate.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Bot Team (variant: team)

You are executing the **team** variant: methodology fan-outs
(conservative / aggressive / pragmatic / alternative) run as teammates or
inside dynamic workflows you author; the daemon machine (`gm bot next`)
serves every phase's instructions and enforces the gates. Canonical
reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set, or agent teams are unavailable
(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), report the error and exit
(fallback: /gm_bot_rpi).

## Arguments

Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
`--command /gm_bot_team` at create and `--variant team` at start/resume.

## Variant contract (team)

- **Workflow-driven phases** — briefing + explore + clarify-open,
  implementation, and review-fix run as dynamic workflows you HAND-AUTHOR,
  guided by `gm bot next` output. Script code is pure orchestration: it
  never touches gm or the db — every read/write happens inside agent()
  subagents via the MCP pen tools (or Bash gm). Workflow Bash writes are
  invisible to the file-change hook — `gm bot reconcile` at each gate is
  mandatory.
- **Explore** — four `gmcc:code-explorer` personas, each opening its OWN
  summary (`bot_summary` / `--agent-type <methodology>`) and completing it.
  Then `gmcc:finding-reranker` applies the ONE prompt-scoped calibrated
  batch; you complete the `synthesis` summary (the seal).
- **Clarify** — `gmcc:ques` pens the question/note suite; YOU run the user
  conversation (AskUserQuestion mirroring the option rows) and the answers;
  then the care package (curated COPIES of ranked findings + dope/kbite
  refs + the clarified-intent blob), finalize, set-status architecting.
- **Architecture optioning** — four `gmcc:code-architect` personas each pen
  their OWN option row (`arch_option_add`). You pick the winner with
  `gm arch decide` (rationale recorded; siblings rejected; offer the
  losers' best features to the user), and ONLY the selected option expands
  into change rows — persistence first, change kinds + dope refs.
- **Plan gate** — propose → user sign-off with the full persistence delta
  table → approve → implementing.
- **Review** — four `gmcc:code-quality-reviewer` personas pen finding rows;
  reranker calibrates; you complete with the verdict, clarify fix intent
  with the user, run review-fix (as a workflow when the fixes fan out), done.

Teammate spawn prompts carry ONLY the methodology, the summary uuid where
the def asks for one, and the one-line target — plus the explicit
`--prompt-uuid` pull line (teammates hold no activation claim). Never paste
cheatsheets, briefings, or dope dumps into spawn prompts. Teammates are
resumable by name; there is no tear-down step.

## Error handling

Teammate spawn failure → fall back to the rpi shape for that phase, say so.
Everything else (VERSION_CONFLICT, SUMMARY_ABSENT, daemon unreachable, dead
doper): `bot_workflows.md`.
