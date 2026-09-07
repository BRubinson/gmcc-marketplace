---
name: gm_bot_team
description: Agent-teams-based workflow. Spawns 4-teammate teams (each on a different methodology) for exploration, planning, and review. Authors prompts into the current session over the daemon. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot Team (Agent Teams)

You are coordinating real agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) to attack a single prompt with 4 parallel methodologies per phase. Same prompt-into-session model as `/gm_bot` and `/gm_bot_rpi`. Each team phase's record is DB-NATIVE: teammates write finding/key-file rows directly, an opus re-ranker calibrates the 0-999 ratings, and the primary completes the summary (overview/verdict).

All persistence goes through the `gm` CLI — see `skills/gmcc_daemon/SKILL.md` and `skills/gmcc/ref/bot_workflows.md`. Never read or write ckfs yamls.

The full gm verb surface is already in context for the primary: the
SessionStart hook prints `gm cheatsheet` (exact signatures + invariants).
Never run `gm ... --help` roundtrips or guess flags.

**Cheatsheet mandate for teammates.** Teammates are independent sessions and
do not inherit this session's SessionStart context, yet they drive gm
directly. Every teammate spawn prompt below must additionally include a
`## GM Cheatsheet` section containing the verbatim output of
`gm cheatsheet`. **`gm_bot_rpi.md` is the reference for the exact gm-call sequence** (creation, clarify transitions, artifact registration, file-change tracking) — this file only documents what differs for teams.

---

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

1. `gm session get --json` for current session state. On exit 2, self-heal per `gm_bot_rpi.md`.
2. One call for the whole session's report state: `gm prompt list --with-reports --json` (per-prompt clarification/architecture/exploration/review stubs). A null report means that summary was never opened. Topic lookup across prompts is `gm search "<topic>" --json` — do NOT grep the ckfs or open memory files for context.

---

## Argument Parsing

Identical to `/gm_bot` and `/gm_bot_rpi`. Quick summary:
- **Run / Resume** (`/gm_bot_team 3` or `/gm_bot_team 3 ...`): `gm prompt list --json` → stub with `seq: 3` → `gm prompt get`. Run/resume by status (lifecycle v2: `draft` → Phase 2, `clarifying` → Phase 3, `architecting` → Phase 4, `implementing` → Phase 5, `reviewing` → Phase 6, `done` → complete). A bare seq runs an externally-authored draft as written; `command` is create-time-only — if empty, note the tier in the clarification's `--backstory-note`.
- **New** (`/gm_bot_team auth-refactor ...`): `gm prompt create --name ... --detail "<verbatim>" --command /gm_bot_team --json` (STAY TRUE — see `gm_bot_rpi.md`), then mkdir the memory dir at the RETURNED `ckfs_relative_storage_path` (the daemon slugs the name — NEVER re-derive `{seq}_{name}` yourself; a hand-built path silently breaks memory-change events).
- **No args**: AskUserQuestion.

---

## Phase 1: KBite Loading (New Prompt Only)

Same as `/gm_bot_rpi`: read `kbite_codes` from `gm prompt get`; explicit add only (`gm kbite add --scope prompt`); read the purpose at the kbite root, then load content from the db (`gm kbite get` → `search` → `file-get`); compile the kbite context summary. The summary is passed into every teammate spawn.

## Phase 1b: DOPE Dump

`gm dope list --session-uuid U` — if the session carries a SESSION_BASE scope, `gm dope get --session-uuid U --json` and hold the tree in primary context. The dump is **force-injected into every explore teammate spawn** (see the spawn template's `## Domain Model (DOPE)` block); architects get the fetch command, not the dump. The dump is always the persistence layer's source of truth (boot-synced from `.gmcc`); no scope → note it and move on. Full protocol: `skills/gmcc/ref/bot_workflows.md`.

---

## Phase 2: Implementation Overview (Explore Team)

### Step 1: Create the Explore Team

Spawn an agent team named `gmb-explore-{prompt_name}` with **4 teammates**, each on a different methodology. Each teammate is an independent Claude Code session.

Per teammate spawn prompt (substitute `{methodology}` per teammate):

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

## Task Context
**Exploration Target**: {prompt row's goal + detail}
**Repository**: Explore from the current working directory
**Branch**: {session code from gm session get}

## KBite Knowledge
{kbite context summary}

## Domain Model (DOPE)
{dope dump — the session's SESSION_BASE tree from gm dope get, force-injected; it IS the persistence layer. Omit the section only when the session has no dope scope, and say so.}

## DB-Native Persistence (you hold the pen)
The exploration record is db rows. Summary uuid: {S — from gm explore open, run by the primary before spawning}.
As you explore, record directly via the gm CLI (bare `gm` — it is on your PATH):
- gm explore key-file-add --summary-uuid {S} --file-path <repo-relative>   (deduped set — duplicates are fine)
- gm explore finding-add --summary-uuid {S} --kind <kind> --title "..." --body "..." --agent-name {methodology} --rating <0-999>
Self-rate every finding: 0 = absolute critical … 999 = ignore (read threshold 100). NEVER call gm explore rank/complete/reopen — ranking is the re-ranker's pass and the overview is the primary's.

## Methodology Assignment: {methodology}
{methodology-specific guidance — see below}
Commit FULLY to this methodology. Do not hedge or balance.

## Output
Return a SHORT summary of what you recorded (finding count, headline discoveries) as your final message — the db rows are the real deliverable.
```

The four methodology guidances:

| Methodology | Guidance |
|-------------|----------|
| Conservative | Find existing patterns that can be reused directly. Identify code that should NOT change. Emphasize stability. Look for minimal integration points. |
| Aggressive | Find areas needing significant changes. Identify tech debt. Look for better abstractions. Consider broader architectural changes. |
| Pragmatic | Focus on high-value exploration areas. Balance effort vs benefit. Consider team familiarity and maintenance cost. |
| Alternative | Look for unconventional patterns. Challenge assumptions about current architecture. Explore edge cases and unusual code paths. |

### Step 0 (before spawning): Open the summary

`gm explore open --prompt-uuid U --json` (explicit — the prompt is still `draft`). Pass the summary uuid into every teammate spawn.

### Step 2: Wait for the Team

Wait for all 4 teammates' final messages. Teammates write their finding/key-file rows directly (persona `agent_name`); their closing summaries are just receipts.

### Step 3: Tear Down + Re-Rank

Clean up the explore team, then spawn the **re-ranker** (one agent, `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_finding_reranker.prompt.md`, model per its frontmatter): it reads EVERY finding (`gm explore get --full`), collapses cross-persona duplicates (999 tombstones), and applies one calibrated `gm explore rank` batch. Wait for it before reading findings yourself.

### Step 4: Synthesize + Complete

Read the ranked record (`gm explore get --prompt-uuid U --json` — full rows under 100 plus stubs; pull ranges via `--max-rating`/`--rating-range` as needed) and synthesize the unified mental model in primary context: consensus vs divergence, and the rated open questions for Clarify (reuse the findings' 0-999 polarity — 0 = critical unknown).

Then seal the record — never write it to a file:

```bash
gm explore complete --summary-uuid S --expected-version V --overview "<your unified synthesis>"
```

`complete` refuses while any finding is unranked (a stranded team run is visible as `unranked` counts in `gm prompt list --with-reports`). This informs Clarify directly.

---

## Phase 3: Clarify (db-native)

Same canonical db-native sequence as `gm_bot_rpi.md` (enter `clarifying` → `gm clarify ask/seal/answer/finalize` → advance to `architecting`), with team-specific additions:

1. **Goal clarification suite.** Extract the rated open questions about the *outcome* from the synthesis — most critical first (start with the 0s and low ratings; 0-999 scale, 0 = critical) — as `gm clarify ask --category goal` rows (embed each `rating:` in the question text).

2. **Detail clarification suite.** Extract the rated open questions about the *approach* — most critical first — as `--category detail` rows.

3. `gm clarify seal`, AskUserQuestion the open questions, record each answer (`gm clarify answer ... --source user`, judgment calls as `bot_inferred`, `--skip` where not applicable).

4. `gm clarify finalize --refined-goal "<acceptance criteria>" --refined-detail "<synthesis + answers integrated>" --backstory-note "<executing tier + methodology-consensus notes>"`, then advance:
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status architecting --json
   ```

---

## Phase 4: Plan (Architect Team)

### Step 1: Create the Architect Team

Spawn `gmb-architect-{prompt_name}` with **4 architect teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

## Architecture Context
**Goal**: {refined_goal from the clarification summary}
**Detail**: {refined_detail from the clarification summary}

## Qualified Prompt
{gm clarify get output: refined goal/detail + all Q/A rows}

## Exploration Synthesis
{the unified synthesis from Phase 2}

## KBite Knowledge
{kbite context summary}

## Domain Model (DOPE)
The session's dope tree is the persistence layer's source of truth — load it on demand with `gm dope get --session-uuid {U} --json`. An architecture proposing new persistence is proposing dope changes.

## Methodology Assignment: {methodology}
Commit FULLY to this methodology. Propose the architecture YOUR methodology would build.

## Output
Return your architecture proposal as your final message.
Format: Goal, Approach Summary, Components, Files to Modify/Create, Build Sequence, Acceptance Criteria, Trade-offs.
```

### Step 2: Wait + Synthesize + Persist

Wait for all 4 proposals. In primary context, synthesize into a unified architecture (resolve methodology disagreements explicitly — pick a direction with rationale). **Persist it db-natively** (no architecture.md): persistence check first (`gm arch persist-add`/`field-add` rows, possibly zero), `gm arch summarize --body "<concept-level synthesis incl. divergence resolutions>"`, `gm arch general-add` per non-persistence change, then `gm arch propose`. Individual teammate proposals are NOT persisted.

### Step 3: User Approval

AskUserQuestion:
```
Architecture synthesized from 4 methodologies. Review the unified plan:

{brief summary, noting where methodologies converged/diverged and why we picked this direction}

How would you like to proceed?
- Approve and implement
- Modify - I have changes to the architecture
- Reject and redesign
```

Approved → `gm arch approve --summary-uuid S --expected-version {v}` and
`gm prompt set-status --prompt-uuid U --expected-version {v} --status implementing --json`.
Modify → `gm arch revise`, edit rows, re-propose.

---

## Phase 5: Implement

1. Follow the approved unified architecture's build sequence — **persistence changes first, always**.
2. Make edits with Read/Edit/Write.
3. After each file write, record it (**always pass `--prompt-uuid`** — `gm arch get`'s implementation-state comparison sees only attributed changes):
   ```bash
   gm file-change add --path <repo-relative path> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```
4. `gm arch get --prompt-uuid U` shows per-row implementation state, unplanned drift, and the persistence-first audit.

---

## Phase 6: Review (Reviewer Team)

Enter it explicitly: `gm prompt set-status ... --status reviewing` (or skip
straight to `done` when the user wants no review pass — the one legal skip edge).

### Step 1: Create the Reviewer Team

Spawn `gmb-review-{prompt_name}` with **4 reviewer teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

## Review Context
**Task**: {refined_goal + refined_detail from the clarification summary}

## Qualified Prompt
{gm clarify get output}

## Approved Architecture
{unified architecture from Phase 4}

## Files Changed
{output of: gm file-change list --prompt-uuid U}

## DB-Native Persistence (you hold the pen)
The review record is db rows. Summary uuid: {S — from gm review open, run by the primary before spawning}.
Record every finding directly via the gm CLI (bare `gm` — it is on your PATH):
- gm review finding-add --summary-uuid {S} --kind <kind> --title "..." --body "..." [--file-path <p> --line-start N [--line-end M]] --agent-name {methodology} --rating <0-999>
Self-rate 0-999 (0 = critical, 999 = ignore; threshold 100). NEVER call gm review rank/resolve/complete — ranking is the re-ranker's pass; overview/verdict/resolutions are the primary's.

## Methodology Assignment: {methodology}
Apply YOUR methodology's lens. Conservatives look for stability risks; aggressives look for missed simplifications; pragmatists check value-vs-effort; alternatives challenge assumptions.

## Output
Return a SHORT summary of what you recorded as your final message — the db rows are the real deliverable.
```

(Before spawning: `gm review open --prompt-uuid U --json` and pass the summary uuid in.)

### Step 2: Re-Rank + Synthesize + Complete

Tear down the reviewer team, spawn the **re-ranker** (`gmcc_agent_finding_reranker.prompt.md`) for one calibrated `gm review rank` batch (cross-persona duplicates → 999 tombstones), then read the ranked record (`gm review get --prompt-uuid U --json`) and synthesize in primary context. Seal it — never write it to a file:

```bash
gm review complete --summary-uuid S --expected-version V \
  --overview "<your unified synthesis>" --verdict approved|approved_with_nits|changes_requested
```

### Step 3: User Decides

AskUserQuestion:
```
4-methodology review complete. {summary of findings}

- Fix all issues
- Fix critical only
- Proceed as-is
```

Implement requested fixes, recording each finding's outcome as you go:
`gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix`
(resolve works after complete — that IS the fix loop; address every finding rated under 100).

---

## Phase 7: Feedback Integration

1. Present a complete summary.
2. Wait for feedback. Iterate until satisfied, then `gm prompt set-status ... --status done`.

There is no phase-history record — completion is represented by prompt
status `done` plus the clarification/architecture/exploration/review rows and file-change trail.

```
Bot Team Complete: prompt {seq} ({name})

**Session**: {session ckfs_relative_storage_path from gm session get --json}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Teams Used**: explore, architect, review (4 teammates each)
**Review Status**: {pass / pass_with_issues}
```

---

## Error Handling

**Team spawn failure:**
```
[GMB] Team spawn failed for {phase}

Falling back to /gm_bot_rpi single-subagent flow for this phase.
```

**Daemon unreachable / VERSION_CONFLICT:** same recovery as `gm_bot_rpi.md`.

**Session paused:**
```
State preserved: prompt row (gm prompt get) + report rows (gm clarify/arch/explore/review get; a stranded 'exploring'/'reviewing' summary shows unranked counts in gm prompt list --with-reports)

To resume: /gm_bot_team {seq} <continuation prompt>
```
