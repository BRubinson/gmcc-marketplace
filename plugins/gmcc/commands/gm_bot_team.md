---
name: gm_bot_team
description: Agent-teams-based workflow. Spawns 4-teammate teams (each on a different methodology) for exploration, planning, and review. Authors prompts into the current session over the daemon. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot Team (Agent Teams, v16.3.0)

You are coordinating real agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) to attack a single prompt with 4 parallel methodologies per phase. Same prompt-into-session model as `/gm_bot` and `/gm_bot_rpi`. The synthesized output of each team phase is persisted to `prompts/{seq}_{name}/memory/` and registered in the daemon db.

All persistence goes through the `gm` CLI — see `skills/gmcc_daemon/SKILL.md` and `skills/gmcc/ref/bot_workflows.md`. Never read or write ckfs yamls. **`gm_bot_rpi.md` is the reference for the exact gm-call sequence** (creation, clarify transitions, artifact registration, file-change tracking) — this file only documents what differs for teams.

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

1. `~/gmcc/bin/gm session get --json` for current session state. On exit 2, self-heal per `gm_bot_rpi.md`.
2. One call for the whole session's report state: `gm prompt list --with-reports --json` (per-prompt clarification/architecture stubs). `is_legacy: true` + null report = pre-m0002: read ckfs artifacts (`gm artifact list`), never fabricate rows. Topic lookup across prompts is `gm search "<topic>" --json` — do NOT grep the ckfs or open memory files for context.

---

## Argument Parsing

Identical to `/gm_bot` and `/gm_bot_rpi`. Quick summary:
- **Run / Resume** (`/gm_bot_team 3` or `/gm_bot_team 3 ...`): `gm prompt list --json` → stub with `seq: 3` → `gm prompt get`. Run/resume by status (lifecycle v2: `draft` → Phase 2, `clarifying` → Phase 3, `architecting` → Phase 4, `implementing` → Phase 5, `reviewing` → Phase 6, `done` → complete; legacy pre-m0002 prompts have no clarify/arch rows — check `gm artifact list`, never fabricate). A bare seq runs an externally-authored draft as written; `command` is create-time-only — if empty, note the tier in the clarification's `--backstory-note`.
- **New** (`/gm_bot_team auth-refactor ...`): `gm prompt create --name ... --detail "<verbatim>" --command /gm_bot_team --json` (STAY TRUE — see `gm_bot_rpi.md`), then mkdir the memory dir at the RETURNED `ckfs_relative_storage_path` (the daemon slugs the name — NEVER re-derive `{seq}_{name}` yourself; a hand-built path silently breaks memory-change events).
- **No args**: AskUserQuestion.

---

## Phase 1: KBite Loading (New Prompt Only)

Same as `/gm_bot_rpi`: read `kbite_codes` from `gm prompt get`; explicit add only (`gm kbite add --scope prompt`); read the purpose at the kbite root, then load content from the db (`gm kbite get` → `search` → `file-get`); compile the kbite context summary. The summary is passed into every teammate spawn.

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
**Branch**: $(basename $GMCC_SESSION_PATH)

## KBite Knowledge
{kbite context summary}

## Methodology Assignment: {methodology}
{methodology-specific guidance — see below}
Commit FULLY to this methodology. Do not hedge or balance.

## Output
Return your exploration report as your final message.
Use the Code Explorer Report format from your prompt file.
```

The four methodology guidances:

| Methodology | Guidance |
|-------------|----------|
| Conservative | Find existing patterns that can be reused directly. Identify code that should NOT change. Emphasize stability. Look for minimal integration points. |
| Aggressive | Find areas needing significant changes. Identify tech debt. Look for better abstractions. Consider broader architectural changes. |
| Pragmatic | Focus on high-value exploration areas. Balance effort vs benefit. Consider team familiarity and maintenance cost. |
| Alternative | Look for unconventional patterns. Challenge assumptions about current architecture. Explore edge cases and unusual code paths. |

### Step 2: Wait for the Team

Wait for all 4 teammates' final messages. Each returns its exploration report directly. Individual teammate reports are NOT persisted; the synthesized unified report (Step 4) is.

### Step 3: Tear Down

Clean up the explore team once all 4 reports are in primary context.

### Step 4: Synthesize + Persist

Synthesize the 4 reports into a unified mental model:

- Merge key files, patterns, integration points
- Identify consensus (high-confidence) vs divergence (needs discussion)
- Compile rated open questions (1-8 scale, where 8 = critical unknown)

**Write the synthesized report** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/explore.md` and register it (`gm artifact add --kind explore --note "..."`). This informs Clarify directly.

---

## Phase 3: Clarify (db-native)

Same canonical db-native sequence as `gm_bot_rpi.md` (enter `clarifying` → `gm clarify ask/seal/answer/finalize` → advance to `architecting`), with team-specific additions. **NEVER write `memory/qualified.md` or `memory/architecture.md` for a post-m0002 prompt** — the db rows ARE the record; `SUMMARY_ABSENT` with `prompt_is_legacy: false` means open a summary, never a file fallback:

1. **YEET-type detection (FIRST clarify step)** over the prompt row's `goal` + `detail`, cross-referenced with the 4-methodology synthesis. Confidently-resolved detections land pre-answered (`gm clarify ask --category yeet_type --answer ... --source bot_inferred`); unresolved ones become open questions for the user.

2. **Goal clarification suite.** Extract the rated open questions about the *outcome* from the synthesis — highest first (start with 8s and 7s) — as `gm clarify ask --category goal` rows (embed each `rating:` in the question text).

3. **Detail clarification suite.** Extract the rated open questions about the *approach* — highest first — as `--category detail` rows.

4. `gm clarify seal`, AskUserQuestion the open questions, record each answer (`gm clarify answer ... --source user`, judgment calls as `bot_inferred`, `--skip` where not applicable).

5. `gm clarify finalize --refined-goal "<acceptance criteria>" --refined-detail "<synthesis + answers integrated>" --backstory-note "<executing tier + methodology-consensus notes>"`, then advance:
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

## Methodology Assignment: {methodology}
Apply YOUR methodology's lens. Conservatives look for stability risks; aggressives look for missed simplifications; pragmatists check value-vs-effort; alternatives challenge assumptions.

## Output
Return your review report as your final message.
```

### Step 2: Synthesize Findings + Persist

In primary context, merge the 4 reviews into a deduplicated list of findings, weighted by how many methodologies surfaced each one. **Write the synthesized review** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/review.md` and register it (`gm artifact add --kind review --note "..."`); individual teammate reviews are NOT persisted.

### Step 3: User Decides

AskUserQuestion:
```
4-methodology review complete. {summary of findings}

- Fix all issues
- Fix critical only
- Proceed as-is
```

Implement requested fixes.

---

## Phase 7: Feedback Integration

1. Present a complete summary.
2. Wait for feedback. Iterate until satisfied, then `gm prompt set-status ... --status done`.

There is no phase-history record — completion is represented by prompt
status `done` plus the clarification/architecture rows, registered artifacts, and file-change trail.

```
Bot Team Complete: prompt {seq} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
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
State preserved: prompt row (gm prompt get) + $GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/

To resume: /gm_bot_team {seq} <continuation prompt>
```
