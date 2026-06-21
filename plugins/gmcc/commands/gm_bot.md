---
name: gm_bot
description: Lightweight GMCC workflow. Authors a prompt into the current session, clarifies it, and implements. All phases run in primary context with no subagents.
argument-hint: <prompt-name|id> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot (Lightweight, v11.0.0)

You are executing a lightweight development workflow entirely in the primary context.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook auto-creates `$GMCC_SESSION_PATH/{session_data.gmcc.yaml, prompts/}`. If `$GMCC_SESSION_PATH/session_data.gmcc.yaml` is missing, instruct the user to restart Claude Code (don't try to recover here).

1. Read `$GMCC_SESSION_PATH/session_data.gmcc.yaml` for current session state (existing prompts, changed_files).
2. Skim recent clarified prompts under `$GMCC_SESSION_PATH/prompts/*/*_clarified.yaml` for context if relevant.

---

## Argument Parsing

Parse `$ARGUMENTS`:

### Case 1: First token is numeric (RESUME mode)
```
/gm_bot 3 continue with the login endpoint
         ^prompt id  ^continuation
```
1. Find entry with `id: 3` in `session_data.gmcc.yaml`'s `prompts:` list. Follow `path:` to read the prompt_data file.
2. If not found: error "No prompt with id 3 in current session".
3. Determine resume phase from the prompt_data file's `prompt_status:`:
   - `Clarified` → load the sibling `{id}_{name}_clarified.yaml`, jump to Phase 4 (Plan)
   - `Clarifying` → re-enter Phase 3 (Clarify) from where it stalled
   - `Draft` → load the sibling `{id}_{name}_initial.yaml`, jump to Phase 2
4. The remaining arguments become the continuation prompt.

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot auth-refactor implement OAuth2 flow
         ^prompt name  ^prompt content
```
1. Pick next prompt id: max existing id in `session_data.gmcc.yaml` + 1, or 1 if none.
2. Create the prompt folder + initial files (see Draft Prompt Folder Layout below).
3. Append entry to `session_data.gmcc.yaml`'s `prompts:` list with `status: Draft`.
4. Proceed to Phase 1.

### Case 3: No arguments
Use AskUserQuestion:
```
What would you like to work on?

Provide a short kebab-case name + task description.
Example: auth-refactor implement OAuth2 flow

- Enter description - Type your task
```

---

## Draft Prompt Folder Layout (v10.0.0)

Each prompt is a FOLDER (not a loose file). At create time:

```
$GMCC_SESSION_PATH/prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index)
    {id}_{name}_initial.yaml        # raw user prompt content
    memory/                          # bot artifacts (explore/architecture/review)
```

Create the folder + `memory/` subdir, then write the two yaml files.

### `{id}_{name}_data.gmcc.yaml` (the index)

Conforms to `gmcc.gmcc_prompt_data_file`. Seed `kbite:` from the parent
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
clarified_prompt_path: ""            # set when Phase 3 completes
prompt_status: Draft
command: /gm_bot
```

### `{id}_{name}_initial.yaml` (the "prompt style" — split content)

Conforms to `gmcc.gmcc_initial_prompt_file`. Keeps the `.yaml` suffix but
carries `yeet:` + `yeet_type:` headers so `/gm_compile` validates it. The raw
prompt is split into three components:

- **`backstory`** — inherited from the parent `session_data.gmcc.yaml`'s
  `backstory:` field at create time (empty unless a session backstory has been
  set). May diverge per prompt thereafter.
- **`goal`** — the generally desired outcome, akin to acceptance criteria.
- **`detail`** — how to accomplish the goal: the remaining specifics.

If the user's prompt is a single undifferentiated blob, do your best to split it
into goal vs detail; when in doubt put the outcome in `goal` and everything else
in `detail`. Leave `goal`/`detail` faithful to the user's words — do not invent
requirements.

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_initial_prompt_file

backstory: |
  {inherited from session_data.gmcc.yaml's backstory: field; "" if unset}
goal: |
  {the desired outcome / acceptance criteria}
detail: |
  {how to accomplish the goal — the rest of the specifics}
kbites_loaded: []                    # filled by Phase 1
```

### session_data prompts[] entry

Append a lightweight stub conforming to `gmcc_session_data_file_prompt_files_entry`:

```yaml
  - id: {id}
    name: {name}
    status: Draft
    path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml
```

---

## Phase 1: KBite Loading (New Prompt Only)

Skip if resuming a draft or clarified prompt that already has `kbites_loaded`.

KBites are **inherited, not auto-detected**. The relevant kbites are already
declared up the chain — project → instance → session → prompt — and were seeded
into this prompt's `kbite:` list at draft-create time. There is no trigger
matching and no kbite picker.

1. Read the inherited kbite list from `{id}_{name}_data.gmcc.yaml`'s `kbite:`
   field (seeded from `session_data.gmcc.yaml`'s `kbite:`).
2. **Explicit add only.** If the user's prompt text explicitly asks to add a
   kbite (e.g. "add the swift_ui kbite", "use the spatial kbite"), append it to
   the prompt's `kbite:` list. Never add a kbite on your own initiative.
3. For each inherited/added kbite, load context from `$GMCC_KBITE_DIGESTED/{name}/`:
   read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` and `KBITE_INDEX.md`, then load the
   top 3-5 highest-relevance chewed files. Explore freely with Bash (`find`,
   `cat`, `rg`) — you have read-only run of the ckfs tree.
4. Update `{id}_{name}_initial.yaml`'s `kbites_loaded:` list to reflect what you
   loaded, and keep `{id}_{name}_data.gmcc.yaml`'s `kbite:` list in sync.

If the inherited `kbite:` list is empty and the prompt names no kbite, load
nothing and proceed to Phase 2.

---

## Phase 2: Implementation Overview

Explore the codebase using Glob/Grep/Read. Identify the files relevant to this prompt, the integration points, and any ambiguities to resolve in Clarify. Keep this in primary context — no subagents.

**Persist your exploration notes** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/explore.md` (concise markdown — files surveyed, patterns spotted, open questions).

---

## Phase 3: Clarify

1. Flip `{id}_{name}_data.gmcc.yaml`'s `prompt_status` to `Clarifying` and update `session_data.gmcc.yaml` prompts[] entry's `status: Clarifying`.

2. **YEET-type detection (FIRST clarify step).** Before any other clarification, scan the initial prompt's `goal` + `detail` for YEETS types:
   - **Declared** — types named explicitly in the prose (e.g. "a new yeet type for X", a mentioned struct/enum name).
   - **Inferred** — data shapes the prompt describes structurally without naming a type (e.g. "a record holding a name and a list of amounts" → a candidate struct).

   For each detected type, try to resolve it confidently (to a concrete struct/enum in `gmcc.yeet.yaml` or a sibling `.yeet.yaml`, to a new type to create, or to a clear action). If you **cannot** resolve it confidently, you **must** AskUserQuestion to clarify the intended typing behavior. Record every detection in the clarified file's `detected_yeet_types:` list with `source:` (`declared`/`inferred`) and `confidence:` (`confident`/`needs_clarification`). If no YEETS types are present, write `detected_yeet_types: []`.

3. **Goal clarification suite.** Identify what is underspecified about the *outcome* (acceptance criteria, scope boundaries, definition of done). AskUserQuestion; record answers under `goal_clarifications:`.

4. **Detail clarification suite.** Identify what is underspecified about the *approach* (edge cases, integration points, design preferences, backwards compat). AskUserQuestion; record answers under `detail_clarifications:`.

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
  {the initial goal rewritten with goal clarifications integrated — the
   acceptance criteria, as the single source of truth}
refined_detail: |
  {the initial detail rewritten with detail clarifications integrated — how it
   gets built}
detected_yeet_types:
  - type: {detected type token or described shape}
    resolved_to: {what it means / the type to create / the user's clarified intent}
    source: declared            # declared | inferred
    confidence: confident       # confident | needs_clarification
key_files:
  - path: {file}
    relevance: {why it matters}
constraints:
  - {constraint 1}
kbites_loaded:
  - {kbite name}
```

6. Update `{id}_{name}_data.gmcc.yaml`: set `prompt_status: Clarified`, set `clarified_prompt_path: {id}_{name}_clarified.yaml`, bump `updated_time`.
7. Update `session_data.gmcc.yaml` prompts[] entry: `status: Clarified`.

The `{id}_{name}_initial.yaml` file is **not modified** — the clarified file is the new source of truth.

---

## Phase 4: Plan

1. Enter plan mode using EnterPlanMode.
2. Design the implementation approach based on the clarified prompt + kbite context + exploration findings.
3. Write a concrete plan with files-to-edit, ordered steps, and key patterns to follow.
4. Exit plan mode for user approval.
5. **Persist the approved plan** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/architecture.md`.

---

## Phase 5: Implement

1. Execute the approved plan.
2. Make edits with Read/Edit/Write.
3. After each file write, append to `session_data.gmcc.yaml`'s `changed_files:` list (conforms to `gmcc_session_data_file_changed_files_entry`):
   ```yaml
   - file: {path relative to instance}
     timestamp: {ISO 8601}
     lines: [[start, end], ...]
     commit: {short sha if committed, else "uncommitted"}
     note: ""
   ```

---

## Phase 6: Feedback Integration

1. Present a summary: files modified, key decisions, known limitations.
2. **Persist a brief review note** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/review.md` covering what was built, what was deferred, and any known limitations.
3. Wait for user feedback. Iterate until satisfied.
4. On completion, append to `session_data.gmcc.yaml`'s `phase_history:` list (create it if absent; each entry conforms to `gmcc_session_data_file_phase_history_entry`). The lightweight tier has no review phase, so `review_status` is null:
   ```yaml
   phase_history:
     - prompt_id: {id}
       command: /gm_bot
       completed_at: {ISO 8601}
   ```

```
Bot Complete: prompt {id} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
**Files Modified**: {count}
**Changes**: {brief summary}

**Next**: continue with more work in this session, or `/gm_bot {next_id} ...` to start a new prompt.
```

---

## Error Handling

**Session paused (user stops responding):**
```
State preserved at: $GMCC_SESSION_PATH/prompts/{id}_{name}/

To resume: /gm_bot {id} <continuation prompt>
```

**Task grows in scope:**
Use AskUserQuestion:
```
This task is growing beyond lightweight scope.

Would you like to upgrade?
- Continue as /gm_bot - Keep it lightweight
- Switch to /gm_bot_rpi - Add subagent exploration and review
- Switch to /gm_bot_team - Full agent team treatment
```
