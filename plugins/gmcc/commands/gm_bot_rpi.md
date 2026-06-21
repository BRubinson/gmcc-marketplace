---
name: gm_bot_rpi
description: Subagent-based Research/Plan/Implement workflow. Spawns specialized GMCC subagents for exploration, architecture, and code review while keeping clarification and implementation in primary context. Authors prompts into the current session.
argument-hint: <prompt-name|id> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement, v11.0.0)

You are executing an enhanced development workflow that leverages GMCC subagents for Research, Planning, and Review phases. Same prompt-into-session model as `/gm_bot`, with subagents added to Phases 2, 4, and 6. Subagent reports are persisted to `prompts/{id}_{name}/memory/`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook auto-creates `$GMCC_SESSION_PATH/{session_data.gmcc.yaml, prompts/}`. If `$GMCC_SESSION_PATH/session_data.gmcc.yaml` is missing, instruct the user to restart Claude Code.

1. Read `$GMCC_SESSION_PATH/session_data.gmcc.yaml` for current session state.
2. Skim recent clarified prompts under `$GMCC_SESSION_PATH/prompts/*/*_clarified.yaml` for context.

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Resume** (`/gm_bot_rpi 3 ...`): find prompt with `id: 3` in session_data; follow `path:` to the prompt_data file. Resume at Phase 4 if `Clarified`, re-enter Phase 3 if `Clarifying`, jump to Phase 2 if `Draft`.
- **New** (`/gm_bot_rpi auth-refactor ...`): assign next id, write draft yaml, append session_data entry, proceed.
- **No args**: AskUserQuestion for name + content.

---

## Draft Prompt Folder Layout (v10.0.0)

Each prompt is a FOLDER. At create time:

```
$GMCC_SESSION_PATH/prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index)
    {id}_{name}_initial.yaml        # prompt style: detail (verbatim) + empty goal/backstory
    memory/                          # explore.md / architecture.md / review.md
```

### `{id}_{name}_data.gmcc.yaml`

Conforms to `gmcc.gmcc_prompt_data_file`. Seed `kbite:` from parent
`session_data.gmcc.yaml`'s `kbite:` list.

```yaml
version: 3
yeet:
  - gmcc
yeet_type: gmcc.gmcc_prompt_data_file

id: {id}
code: {name}
uuid: {v4}
name: {name}
description: ""
created_time: {ISO 8601}
updated_time: {ISO 8601}
gmcc_ckfs_absolute_path: {GMCC_SESSION_PATH}/prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml
gmcc_ckfs_relative_path: projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml
kbite: []                            # seeded from session_data.kbite
initial_prompt_path: {id}_{name}_initial.yaml
clarified_prompt_path: ""
prompt_status: Draft
command: /gm_bot_rpi
```

### `{id}_{name}_initial.yaml`

Conforms to `gmcc.gmcc_initial_prompt_file`. Keeps the `.yaml` suffix but carries
`yeet:` + `yeet_type:` headers for `/gm_compile`. The three "prompt style"
components are **human-authored only**: **`backstory`** (inherited verbatim from
the parent `session_data.gmcc.yaml`'s `backstory:` at create time — empty `""`
unless set; may diverge), **`goal`** (desired outcome / acceptance criteria), and
**`detail`** (how to accomplish it).

**STAY TRUE — do NOT split, infer, or author these fields.** When creating a NEW
prompt from a passed argument, the entire passed prompt is assumed to be `detail`
and is written there **verbatim**. `goal` is left empty (`""`); `backstory` is
inherited from the session (`""` if unset). Never split a blob into goal vs
detail, never paraphrase, never invent an outcome — a human (or upcoming editor)
authors `goal`/`backstory`; the Phase 3 Clarify suite fleshes out the goal later.

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_initial_prompt_file

backstory: |
  {inherited verbatim from session_data.gmcc.yaml's backstory: field; "" if unset}
goal: |
  ""                                 # human input — left empty at create time
detail: |
  {the entire passed prompt, verbatim}
kbites_loaded: []
kbite_context_summary: ""    # filled in Phase 1 for subagent passing
```

### session_data prompts[] entry

```yaml
  - id: {id}
    name: {name}
    status: Draft
    path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml
```

---

## Phase 1: KBite Loading (New Prompt Only)

KBites are **inherited, not auto-detected** — already declared up the chain
(project → instance → session → prompt) and seeded into this prompt's `kbite:`
list. No trigger matching, no kbite picker.

1. Read the inherited kbite list from `{id}_{name}_data.gmcc.yaml`'s `kbite:`
   field (seeded from `session_data.gmcc.yaml`'s `kbite:`).
2. **Explicit add only.** If the user's prompt text explicitly asks to add a
   kbite, append it to the prompt's `kbite:` list. Never add one on your own.
3. For each inherited/added kbite: read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` +
   `KBITE_INDEX.md`, load top 3-5 chewed files, compile a **kbite context
   summary** (key learnings, takeaways, patterns). Explore freely with Bash
   (`find`, `cat`, `rg`) — read-only run of the ckfs tree.
4. Update `{id}_{name}_initial.yaml`'s `kbites_loaded:` list and
   `kbite_context_summary:` field — this summary is passed to every subagent
   spawn. Keep `{id}_{name}_data.gmcc.yaml`'s `kbite:` list in sync.

---

## Phase 2: Implementation Overview (Explore Subagent)

Spawn 1 explore subagent via Task tool. The subagent does its work in its own context window; it returns a structured report as its final message. The primary context receives the report content **and persists it** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/explore.md` (v10.0.0 — see `skills/gmcc/ref/bot_workflows.md`).

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

    ## Task Context
    **Exploration Target**: {initial prompt's goal + detail}
    **Repository**: Explore from the current working directory
    **Branch**: $(basename $GMCC_SESSION_PATH)

    ## KBite Knowledge
    {kbite_context_summary from prompt yaml}

    ## Exploration Approach
    Apply all 4 methodologies sequentially:
    1. Conservative: existing patterns to reuse
    2. Aggressive: areas that might need significant changes
    3. Pragmatic: balance effort/value
    4. Alternative: unconventional integration points

    ## Output
    Return your complete exploration report as your final message.
    Use the Code Explorer Report format from your prompt file.
    Include: Target, Key Files, Patterns, Integration Points, Dependencies, Uncertainties, Methodology Insights.
```

Read the returned report into the primary context AND write it verbatim to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/explore.md`. Use it to inform Clarify.

---

## Phase 3: Clarify

1. Flip `{id}_{name}_data.gmcc.yaml`'s `prompt_status` to `Clarifying` and update session_data prompts[] entry's `status: Clarifying`.

2. **YEET-type detection (FIRST clarify step).** Before anything else, scan the initial prompt's `goal` + `detail` (cross-referenced with the exploration report) for YEETS types:
   - **Declared** — types named explicitly in the prose (e.g. "a new yeet type for X", a mentioned struct/enum).
   - **Inferred** — data shapes the prompt describes structurally without naming a type.

   Resolve each confidently (to an existing struct/enum, a new type to create, or a clear action). If you **cannot** resolve one confidently, you **must** AskUserQuestion to clarify the intended typing behavior. Record every detection under `detected_yeet_types:` with `source:` + `confidence:`. Use `detected_yeet_types: []` if none.

3. **Goal clarification suite.** Resolve what is underspecified about the *outcome* (acceptance criteria, scope boundaries, done definition), informed by the exploration report. AskUserQuestion → `goal_clarifications:`.

4. **Detail clarification suite.** Resolve what is underspecified about the *approach* (uncertainties from exploration, edge cases, integration preferences). AskUserQuestion → `detail_clarifications:`.

5. Write `$GMCC_SESSION_PATH/prompts/{id}_{name}/{id}_{name}_clarified.yaml` (conforms to `gmcc.gmcc_clarified_prompt_file`):

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_clarified_prompt_file

clarified_at: {ISO 8601}
backstory: |
  {carried through from the initial file's backstory; "" if unset}
goal_clarifications:
  - q: {question about the outcome}
    a: {answer}
detail_clarifications:
  - q: {question about the approach}
    a: {answer}
refined_goal: |
  {initial goal + goal clarifications, integrated — the acceptance criteria}
refined_detail: |
  {initial detail + detail clarifications + exploration findings, integrated —
   how it gets built. Single source of truth from here on.}
detected_yeet_types:
  - type: {detected type token or described shape}
    resolved_to: {what it means / type to create / user's clarified intent}
    source: declared            # declared | inferred
    confidence: confident       # confident | needs_clarification
key_files:
  - path: {file}
    relevance: {why}
patterns_to_follow:
  - {pattern from exploration}
constraints:
  - {constraint}
kbites_loaded:
  - {kbite name}
```

6. Update `{id}_{name}_data.gmcc.yaml`: set `prompt_status: Clarified`, set `clarified_prompt_path: {id}_{name}_clarified.yaml`, bump `updated_time`.
7. Update `session_data.gmcc.yaml` prompts[] entry: `status: Clarified`.

---

## Phase 4: Plan (Architect Subagent)

Spawn 1 architect subagent. The returned architecture is persisted to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/architecture.md` after user approval.

```
Task tool:
  subagent_type: general-purpose
  model: opus
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

    ## Architecture Context
    **Goal**: {refined_goal from clarified prompt yaml}
    **Detail**: {refined_detail from clarified prompt yaml}

    ## Clarified Prompt
    {full clarified yaml contents}

    ## Exploration Findings
    {exploration report from Phase 2, in primary context}

    ## KBite Knowledge
    {kbite_context_summary}

    ## Architecture Approach
    Apply all 4 methodologies and synthesize the best elements.

    ## Output
    Return your architecture document as your final message.
    Format: Goal, Approach Summary, Components, Files to Modify/Create, Build Sequence, Acceptance Criteria, Trade-offs.
```

Present the architecture to the user via AskUserQuestion:
```
Architecture design complete. Review the plan:

{brief summary}

How would you like to proceed?
- Approve and implement - Start building
- Modify - I have changes to the architecture
- Reject and redesign - Start architecture over
```

Once approved, write the architecture (verbatim from the subagent) to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/architecture.md`.

---

## Phase 5: Implement

1. Follow the approved architecture's build sequence.
2. Make edits with Read/Edit/Write.
3. After each file write, append to `session_data.gmcc.yaml`'s `changed_files:` list (conforms to `gmcc_session_data_file_changed_files_entry`):
   ```yaml
   - file: {path relative to instance}
     timestamp: {ISO 8601}
     lines: [[start, end], ...]
     commit: {short sha or "uncommitted"}
     note: ""
   ```

---

## Phase 6: Review (Code Review Subagent)

Spawn 1 review subagent.

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

    ## Review Context
    **Task**: {refined_goal + refined_detail from clarified prompt}

    ## Clarified Prompt
    {clarified yaml contents}

    ## Architecture
    {architecture doc from Phase 4}

    ## Files Changed
    {list from session_data.gmcc.yaml changed_files}

    ## Output
    Return your review report as your final message.
    Format per the Code Quality Review Report in your prompt file.
```

Present findings via AskUserQuestion:
```
Code review complete. {summary}

How would you like to handle the findings?
- Fix all issues
- Fix critical only
- Proceed as-is
```

Implement requested fixes (back to Phase 5 for the fix subset).

Write the review report (verbatim from the subagent) to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/review.md`.

---

## Phase 7: Feedback Integration

1. Present a complete summary: what was built, files modified, review findings addressed, known limitations.
2. Wait for user feedback. Iterate until satisfied.
3. On completion, append to `session_data.gmcc.yaml`'s `phase_history:` list (each entry conforms to `gmcc_session_data_file_phase_history_entry`):
   ```yaml
   phase_history:
     - prompt_id: {id}
       command: /gm_bot_rpi
       completed_at: {ISO 8601}
       review_status: {pass | pass_with_issues}
   ```

```
Bot RPI Complete: prompt {id} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
**Files Modified**: {count}
**Review Status**: {pass / pass_with_issues}

**Next**: continue with more prompts in this session, or start a new prompt with `/gm_bot_rpi {next_id} ...`.
```

---

## Error Handling

**Subagent spawn failure:**
```
[GMB] Subagent spawn failed for {phase}

Falling back to primary context for this phase.
```
Continue the phase in primary context as a fallback.

**Session paused:**
```
State preserved at: $GMCC_SESSION_PATH/prompts/{id}_{name}/

To resume: /gm_bot_rpi {id} <continuation prompt>
```

**Task grows in scope:**
```
This task may benefit from full agent team treatment.

- Continue as /gm_bot_rpi
- Switch to /gm_bot_team
```
