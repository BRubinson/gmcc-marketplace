---
name: gm_bot_team
description: Agent-teams-based workflow. Spawns 4-teammate teams (each on a different methodology) for exploration, planning, and review. Authors prompts into the current session. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS.
argument-hint: <prompt-name|id> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot Team (Agent Teams, v11.0.0)

You are coordinating real agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) to attack a single prompt with 4 parallel methodologies per phase. Same prompt-into-session model as `/gm_bot` and `/gm_bot_rpi`. The synthesized output of each team phase is persisted to `prompts/{id}_{name}/memory/`.

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

1. Read `$GMCC_SESSION_PATH/session_data.gmcc.yaml` for current session state.
2. Skim recent clarified prompts for context.

---

## Argument Parsing

Identical to `/gm_bot` and `/gm_bot_rpi`. Quick summary:
- **Resume** (`/gm_bot_team 3 ...`): find prompt id 3; resume by status.
- **New** (`/gm_bot_team auth-refactor ...`): assign next id, write draft yaml, append session_data entry.
- **No args**: AskUserQuestion.

---

## Draft Prompt Folder Layout (v10.0.0)

Same folder shape as `/gm_bot_rpi`:

```
$GMCC_SESSION_PATH/prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index, version: 3)
    {id}_{name}_initial.yaml        # split prompt: backstory / goal / detail
    memory/                          # synthesized explore/architecture/review
```

`{id}_{name}_data.gmcc.yaml` conforms to `gmcc.gmcc_prompt_data_file` (`version: 3`)
with `command: /gm_bot_team` and `prompt_status: Draft`. Seed `kbite:` from parent
session_data. `{id}_{name}_initial.yaml` conforms to `gmcc.gmcc_initial_prompt_file`
— it keeps the `.yaml` suffix but carries `yeet:` + `yeet_type:` headers and splits
the prompt into `backstory:` (inherited from parent `session_data.gmcc.yaml`'s
`backstory:` at create time, empty unless set; may diverge), `goal:`, and `detail:`,
plus `kbites_loaded:` + `kbite_context_summary:`. session_data prompts[] entry uses
the lightweight stub shape (`id`, `name`, `status`, `path`). See `gm_bot_rpi.md` for
the exact yaml templates.

---

## Phase 1: KBite Loading (New Prompt Only)

Same as `/gm_bot_rpi`. Update `{id}_{name}_initial.yaml` with `kbites_loaded:` + `kbite_context_summary:`; merge selections into `{id}_{name}_data.gmcc.yaml`'s `kbite:` list. The summary is passed into every teammate spawn.

---

## Phase 2: Implementation Overview (Explore Team)

### Step 1: Create the Explore Team

Spawn an agent team named `gmb-explore-{prompt_name}` with **4 teammates**, each on a different methodology. Each teammate is an independent Claude Code session.

Per teammate spawn prompt (substitute `{methodology}` per teammate):

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

## Task Context
**Exploration Target**: {initial prompt's goal + detail}
**Repository**: Explore from the current working directory
**Branch**: $(basename $GMCC_SESSION_PATH)

## KBite Knowledge
{kbite_context_summary}

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

**Write the synthesized report** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/explore.md`. This informs Clarify directly.

---

## Phase 3: Clarify

1. Flip `{id}_{name}_data.gmcc.yaml`'s `prompt_status` to `Clarifying` and the session_data prompts[] entry's `status: Clarifying`.

2. **YEET-type detection (FIRST clarify step).** Before resolving open questions, scan the initial prompt's `goal` + `detail` (cross-referenced with the 4-methodology synthesis) for YEETS types:
   - **Declared** — types named explicitly in the prose.
   - **Inferred** — data shapes the prompt describes structurally without naming a type.

   Resolve each confidently, or AskUserQuestion when you cannot. Record every detection under `detected_yeet_types:` with `source:` + `confidence:`. Use `detected_yeet_types: []` if none.

3. **Goal clarification suite.** Extract the rated open questions about the *outcome* (acceptance criteria, scope) from the synthesis — highest first (start with 8s and 7s). AskUserQuestion → `goal_clarifications:` (carry each item's `rating:`).

4. **Detail clarification suite.** Extract the rated open questions about the *approach* (uncertainties, integration, edge cases) from the synthesis — highest first. AskUserQuestion → `detail_clarifications:` (carry each item's `rating:`).

5. Write `$GMCC_SESSION_PATH/prompts/{id}_{name}/{id}_{name}_clarified.yaml` (conforms to `gmcc.gmcc_clarified_prompt_file`):

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_clarified_prompt_file

clarified_at: {ISO 8601}
backstory: |
  {carried through from the initial file's backstory; "" if unset}
goal_clarifications:
  - rating: 8
    q: {question about the outcome}
    a: {answer}
detail_clarifications:
  - rating: 7
    q: {question about the approach}
    a: {answer}
refined_goal: |
  {initial goal + goal clarifications + synthesis, integrated — acceptance criteria}
refined_detail: |
  {initial detail + detail clarifications + 4-methodology synthesis, integrated}
detected_yeet_types:
  - type: {detected type token or described shape}
    resolved_to: {what it means / type to create / user's clarified intent}
    source: declared            # declared | inferred
    confidence: confident       # confident | needs_clarification
key_files:
  - path: {file}
    relevance: {why}
    consensus: {agents that flagged it}
patterns_to_follow:
  - {pattern}
constraints:
  - {constraint}
kbites_loaded:
  - {kbite name}
```

6. Update `{id}_{name}_data.gmcc.yaml`: `prompt_status: Clarified`, set `clarified_prompt_path`, bump `updated_time`.
7. Update `session_data.gmcc.yaml` prompts[] entry: `status: Clarified`.

---

## Phase 4: Plan (Architect Team)

### Step 1: Create the Architect Team

Spawn `gmb-architect-{prompt_name}` with **4 architect teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

## Architecture Context
**Goal**: {refined_goal from clarified prompt}
**Detail**: {refined_detail from clarified prompt}

## Clarified Prompt
{full clarified yaml contents}

## Exploration Synthesis
{the unified synthesis from Phase 2}

## KBite Knowledge
{kbite_context_summary}

## Methodology Assignment: {methodology}
Commit FULLY to this methodology. Propose the architecture YOUR methodology would build.

## Output
Return your architecture proposal as your final message.
Format: Goal, Approach Summary, Components, Files to Modify/Create, Build Sequence, Acceptance Criteria, Trade-offs.
```

### Step 2: Wait + Synthesize + Persist

Wait for all 4 proposals. In primary context, synthesize into a unified architecture (resolve methodology disagreements explicitly — pick a direction with rationale). **Write the synthesized architecture** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/architecture.md` (individual teammate proposals are NOT persisted).

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
3. After each file write, append to `session_data.gmcc.yaml`'s `changed_files:` list (conforms to `gmcc_session_data_file_changed_files_entry`):
   ```yaml
   - file: {path}
     timestamp: {ISO 8601}
     lines: [[start, end], ...]
     commit: {short sha or "uncommitted"}
     note: ""
   ```

---

## Phase 6: Review (Reviewer Team)

### Step 1: Create the Reviewer Team

Spawn `gmb-review-{prompt_name}` with **4 reviewer teammates**, one per methodology.

Per teammate spawn prompt:

```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

## Review Context
**Task**: {refined_goal + refined_detail from clarified prompt}

## Clarified Prompt
{clarified yaml contents}

## Approved Architecture
{unified architecture from Phase 4}

## Files Changed
{list from session_data.gmcc.yaml changed_files}

## Methodology Assignment: {methodology}
Apply YOUR methodology's lens. Conservatives look for stability risks; aggressives look for missed simplifications; pragmatists check value-vs-effort; alternatives challenge assumptions.

## Output
Return your review report as your final message.
```

### Step 2: Synthesize Findings + Persist

In primary context, merge the 4 reviews into a deduplicated list of findings, weighted by how many methodologies surfaced each one. **Write the synthesized review** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/review.md` (individual teammate reviews are NOT persisted).

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
3. On completion, append to `session_data.gmcc.yaml`'s `phase_history:` list (each entry conforms to `gmcc_session_data_file_phase_history_entry`):
   ```yaml
   phase_history:
     - prompt_id: {id}
       command: /gm_bot_team
       completed_at: {ISO 8601}
       review_status: {pass | pass_with_issues}
       teams_used: [explore, architect, review]
   ```

```
Bot Team Complete: prompt {id} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
**Files Modified**: {count}
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

**Session paused:**
```
State preserved at: $GMCC_SESSION_PATH/prompts/{id}_{name}/

To resume: /gm_bot_team {id} <continuation prompt>
```
