---
name: gm_bot
description: Lightweight GMCC workflow. Authors a prompt into the current session, clarifies it, and implements. All phases run in primary context with no subagents.
argument-hint: <prompt-name|id> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot (Lightweight, v10.0.0)

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
version: 2
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

### `{id}_{name}_initial.yaml` (raw prompt content)

```yaml
content: |
  {raw user prompt}
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

1. List available kbites: `ls $GMCC_KBITE_DIGESTED/` and for each, read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` for a one-line summary.
2. Use AskUserQuestion (multiSelect: true) to let the user pick relevant kbites.
3. For each selected kbite:
   - Read `KBITE_INDEX.md` and `KBITE_TRIGGER_MAP.md`
   - Load the top 3-5 highest-relevance chewed files
4. Update `{id}_{name}_initial.yaml`'s `kbites_loaded:` list and merge selections into `{id}_{name}_data.gmcc.yaml`'s `kbite:` list.

---

## Phase 2: Implementation Overview

Explore the codebase using Glob/Grep/Read. Identify the files relevant to this prompt, the integration points, and any ambiguities to resolve in Clarify. Keep this in primary context — no subagents.

**Persist your exploration notes** to `$GMCC_SESSION_PATH/prompts/{id}_{name}/memory/explore.md` (concise markdown — files surveyed, patterns spotted, open questions).

---

## Phase 3: Clarify

1. Flip `{id}_{name}_data.gmcc.yaml`'s `prompt_status` to `Clarifying` and update `session_data.gmcc.yaml` prompts[] entry's `status: Clarifying`.
2. Identify underspecified aspects (edge cases, scope boundaries, design preferences, backwards compat).
3. Use AskUserQuestion to resolve all ambiguities.
4. Write `$GMCC_SESSION_PATH/prompts/{id}_{name}/{id}_{name}_clarified.yaml`:

```yaml
clarified_at: {ISO 8601}
original_content: |
  {raw user prompt}
clarifications:
  - q: {question 1}
    a: {answer 1}
  - q: {question 2}
    a: {answer 2}
refined_content: |
  {The original prompt rewritten with all clarifications integrated inline.
   Single source of truth for what needs to be built.}
key_files:
  - path: {file}
    relevance: {why it matters}
constraints:
  - {constraint 1}
  - {constraint 2}
kbites_loaded:
  - {kbite name}
```

5. Update `{id}_{name}_data.gmcc.yaml`: set `prompt_status: Clarified`, set `clarified_prompt_path: {id}_{name}_clarified.yaml`, bump `updated_time`.
6. Update `session_data.gmcc.yaml` prompts[] entry: `status: Clarified`.

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
4. On completion, append a final phase-history line to `session_data.gmcc.yaml` (under a `phase_history:` section — create it if absent) noting completion of this prompt.

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
