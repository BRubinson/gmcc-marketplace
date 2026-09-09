---
name: gm_bot_team
description: Agent-teams-based workflow. Spawns 4-teammate teams (each on a different methodology) for exploration, planning, and review. Authors prompts into the current session over the daemon. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Bot Team (Agent Teams)

You are coordinating real agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`)
to attack a single prompt with 4 parallel methodologies per phase. Same
prompt-into-session model as `/gm_bot` and `/gm_bot_rpi`.

**The shared lifecycle — state machine, pen contract, briefing/doper
protocol, rating rules, STAY TRUE, resume logic, error recovery — is
`skills/gmcc/ref/bot_workflows.md`. This file is ONLY the team-tier
delta.** Full gm signatures: `gm cheatsheet --full` (the SessionStart
sheet is the compact core, not the full surface).

## Current session state

!`gm session get --json`
!`gm prompt list --with-reports --json`
!`gm dope list --json`

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

**Agent Teams Check**: If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not enabled, output:
```
[GMB] ERROR: Agent teams not enabled

/gm_bot_team requires the experimental agent teams feature.
Enable it via env var or settings.json, then retry.
Or use /gm_bot_rpi for subagent-based workflow.
```
Exit without proceeding.

## Argument Parsing

Identical to the other tiers — run/resume by seq, new prompt by slug name,
no args → AskUserQuestion. Creation, STAY TRUE, the mkdir contract, and
resume-by-status: `bot_workflows.md`. Record `--command /gm_bot_team` at
create.

## Team Mechanics (the actual delta)

- **Teammates spawn from the SAME agent defs as every tier**:
  `subagent_type: "gmcc:code-explorer"` / `"gmcc:code-architect"` /
  `"gmcc:code-quality-reviewer"`. The def carries the pen contract,
  methodology modes, and rating rules — spawn prompts carry ONLY the
  uuids, the lowercase methodology, and the briefing-pull line.
- **Teammates are full sessions**: SessionStart feeds each one the
  compact cheatsheet core; the SubagentStart briefing stub does NOT fire
  for them, which is why every teammate spawn prompt names the pull
  command explicitly. Never paste cheatsheets, kbite summaries, or dope
  dumps into spawn prompts.
- **No team ceremony**: the session has a single implicit team —
  `team_name` is accepted but ignored. Address a teammate by NAME via
  `SendMessage({to: name, ...})`; give teammates distinct names
  (`gmb-explore-conservative`, …). Teammates are RESUMABLE — a
  SendMessage to an existing name continues it with its context intact;
  there is no tear-down step, just stop waiting on them.
- **4 teammates per phase**, one per methodology: `conservative`,
  `aggressive`, `pragmatic`, `alternative` (lowercase — the daemon
  normalizes `agent_name` to lowercase at write).
- **Re-rank pass**: after a phase's teammates finish, spawn
  `gmcc:finding-reranker` with the summary uuid (its def carries the
  whole protocol). Wait for it before reading findings yourself.

## Phase Flow

Follow the canonical lifecycle in `bot_workflows.md`; per-phase team
deltas below.

### Brief

`gm briefing open --prompt-uuid U --step initial --json`, spawn
`gmcc:doper` (owner uuid + step + one-line topic), then gate with
`gm briefing get --prompt-uuid U --step S --wait --json` — exit 0 before
any teammate spawn, nothing else in between (teammates hold no claim, so
their own pulls also use the explicit `--prompt-uuid` form). Repeat both
the open and the gate with `--step pre_architecture` after clarify
finalize.

### Explore (4 explorer teammates)

`gm explore open --prompt-uuid U --json` first, then spawn 4
`gmcc:code-explorer` teammates. Per-teammate spawn prompt, whole thing:

```
Methodology: {methodology}
Exploration summary uuid: {S}
Target: {one-line exploration topic from the prompt row}
Pull your briefing first: gm briefing get --prompt-uuid {U} --step initial
```

Teammates write their key-file/finding rows directly and return short
receipts. Then: `gmcc:finding-reranker` with summary uuid S → primary
reads the ranked record (`gm explore get --prompt-uuid U --json`),
synthesizes consensus vs divergence + rated open questions for Clarify,
and seals with `gm explore complete` (overview via `--overview-file` for
long narratives).

### Clarify

Canonical sequence per `bot_workflows.md`. Team additions: the goal and
detail suites are the rated open questions from the synthesis (most
critical first — 0-999 polarity, 0 = critical; embed each `rating:` in
the question text), and `finalize --backstory-note` records the
executing tier + methodology-consensus notes.

### Plan (4 architect teammates)

Spawn 4 `gmcc:code-architect` teammates (proposal-only — no db rows).
Per-teammate spawn prompt:

```
Methodology: {methodology}
Prompt uuid: {U}
Goal: {refined_goal, one line}
Pull your briefing first: gm briefing get --prompt-uuid {U} --step pre_architecture
```

(The def has them ground everything else with `gm clarify get` /
`gm explore get` / dope + kbite search reads.) Wait for all 4 proposals,
synthesize in primary context (resolve methodology disagreements
explicitly — pick a direction with rationale), then persist db-natively
per `bot_workflows.md` (persistence rows first; individual teammate
proposals are NOT persisted). AskUserQuestion for approval, noting where
methodologies converged/diverged; approve → `implementing`, modify →
`gm arch revise`.

### Implement

Per `bot_workflows.md`: persistence changes first; Edit/Write bookkeeping
is automatic (PostToolUse hook); record Bash-driven writes manually;
`gm arch get` audits progress.

### Review (4 reviewer teammates)

`gm review open --prompt-uuid U --json`, then 4
`gmcc:code-quality-reviewer` teammates:

```
Methodology: {methodology}
Review summary uuid: {S}
Task: {refined_goal, one line}
Changed files: gm file-change list --prompt-uuid {U}
Pull your briefing first: gm briefing get --prompt-uuid {U} --step pre_architecture
```

Then `gmcc:finding-reranker` with summary uuid S → primary reads, seals
with `gm review complete ... --verdict ...`, AskUserQuestion (fix all /
fix critical / proceed), and runs the fix loop (`gm review resolve` per
finding under 100).

### Complete

Present the summary, iterate on feedback, `gm prompt set-status ...
--status done`. Completion is db rows only — no phase-history file.

```
Bot Team Complete: prompt {seq} ({name})

**Session**: {session ckfs_relative_storage_path from gm session get --json}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Teams Used**: explore, architect, review (4 teammates each)
**Review Verdict**: {verdict}
```

## Error Handling

**Teammate spawn failure:**
```
[GMB] Team spawn failed for {phase}

Falling back to /gm_bot_rpi single-subagent flow for this phase.
```

**Daemon unreachable / VERSION_CONFLICT / SUMMARY_ABSENT:** recovery per
`bot_workflows.md`.

**Session paused:** state is the prompt row + report rows (a stranded
`exploring`/`reviewing` summary shows unranked counts in
`gm prompt list --with-reports`). Resume: `/gm_bot_team {seq} <continuation>`.
