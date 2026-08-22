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
2. Skim recent prompts' `memory/qualified.md` files for context.

---

## Argument Parsing

Identical to `/gm_bot` and `/gm_bot_rpi`. Quick summary:
- **Run / Resume** (`/gm_bot_team 3` or `/gm_bot_team 3 ...`): `gm prompt list --json` → stub with `seq: 3` → `gm prompt get`. Run/resume by status (`clarified` → Phase 4, `clarifying` → Phase 3, `draft` → Phase 2). A bare seq runs an externally-authored draft as written; `command` is create-time-only — if empty, note the tier in `qualified.md`.
- **New** (`/gm_bot_team auth-refactor ...`): `gm prompt create --name ... --detail "<verbatim>" --command /gm_bot_team --json` (STAY TRUE — see `gm_bot_rpi.md`), then `mkdir -p .../prompts/{seq}_{name}/memory`.
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

## Phase 3: Clarify

Runs while the prompt is still `draft`. Same canonical sequence as `gm_bot_rpi.md`, with team-specific additions:

1. **YEET-type detection (FIRST clarify step)** over the prompt row's `goal` + `detail`, cross-referenced with the 4-methodology synthesis. Resolve each confidently, or AskUserQuestion when you cannot. Record in `qualified.md`'s `detected_yeet_types` with `source:` + `confidence:`.

2. **Goal clarification suite.** Extract the rated open questions about the *outcome* from the synthesis — highest first (start with 8s and 7s). AskUserQuestion → `goal_clarifications` (carry each item's `rating:`).

3. **Detail clarification suite.** Extract the rated open questions about the *approach* — highest first. AskUserQuestion → `detail_clarifications` (carry each item's `rating:`).

4. Write `memory/qualified.md` (team flavor: per-clarification `rating`, `key_files[].consensus` listing which methodologies flagged each file) and register it (`gm artifact add --kind qualified --note "..."`).

5. Write back + transition, threading `--expected-version`:
   ```bash
   gm prompt update-content --prompt-uuid U --expected-version {v}   --goal "<refined_goal>" --json
   gm prompt set-status     --prompt-uuid U --expected-version {v+1} --status clarifying --json
   gm prompt set-status     --prompt-uuid U --expected-version {v+2} --status clarified  --json
   ```

---

## Phase 4: Plan (Architect Team)

### Step 1: Create the Architect Team

Spawn `gmb-architect-{prompt_name}` with **4 architect teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

## Architecture Context
**Goal**: {refined_goal from qualified.md}
**Detail**: {refined_detail from qualified.md}

## Qualified Prompt
{full qualified.md contents}

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

Wait for all 4 proposals. In primary context, synthesize into a unified architecture (resolve methodology disagreements explicitly — pick a direction with rationale). **Write the synthesized architecture** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/architecture.md` and register it (`gm artifact add --kind architecture --note "..."`); individual teammate proposals are NOT persisted.

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

---

## Phase 5: Implement

1. Follow the approved unified architecture's build sequence.
2. Make edits with Read/Edit/Write.
3. After each file write, record it:
   ```bash
   gm file-change add --path <repo-relative path> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```

---

## Phase 6: Review (Reviewer Team)

### Step 1: Create the Reviewer Team

Spawn `gmb-review-{prompt_name}` with **4 reviewer teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

## Review Context
**Task**: {refined_goal + refined_detail from qualified.md}

## Qualified Prompt
{qualified.md contents}

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
2. Wait for feedback. Iterate until satisfied.

There is no phase-history record — completion is represented by prompt
status `clarified` plus the registered artifacts and file-change trail.

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
