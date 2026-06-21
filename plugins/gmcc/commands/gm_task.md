---
name: gm_task
description: Load GMCC session context, then just do the task. Read-only by default — makes NO writes to the ckfs unless you explicitly ask for a retroactive write-back later in the conversation.
argument-hint: <task / request>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Task (Context-loaded, read-only, v13.0.0)

You are executing a task with full GMCC context loaded, but **without** the
prompt-authoring ceremony of `/gm_bot`. You load context, you do the work, and
you leave the ckfs untouched — unless the user explicitly asks you to write
something back.

The contract that distinguishes this command from `/gm_bot`:

> **Default behavior writes NOTHING to the ckfs (`$GMCC_CKFS_ROOT`).**
> No draft folder, no initial/clarified prompt files, no `changed_files`
> bookkeeping, no `phase_history`. Editing the user's *repository* files is the
> task and is expected — "no writes" refers to the ckfs only. The ckfs is
> written to **only** when the user explicitly asks for a retroactive
> write-back during the conversation (see the final section).

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMT] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook auto-creates `$GMCC_SESSION_PATH/{session_data.gmcc.yaml, prompts/}`. If `$GMCC_SESSION_PATH/session_data.gmcc.yaml` is missing, instruct the user to restart Claude Code (don't try to recover here).

---

## Phase 1: Load Context (read-only)

Load **session context** — this is the default scope. Do not author or modify
any ckfs files here; these are reads.

1. Read `$GMCC_SESSION_PATH/session_data.gmcc.yaml` for current session state
   (backstory, registered `kbite:`, existing `prompts:`, `changed_files:`).
2. Skim recent clarified prompts under
   `$GMCC_SESSION_PATH/prompts/*/*_clarified.yaml` for relevant prior context
   (refined goals, constraints, key files).

**Reaching wider context on demand.** Project and instance context are *not*
auto-read. When a task genuinely needs them, read them explicitly:
- Project: `$GMCC_PROJECT_PATH/project_data.gmcc.yaml`
- Instance: `$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml`

**KBites on demand.** If a task clearly benefits from a kbite, load it from
`$GMCC_KBITE_DIGESTED/{name}/` (start with `KBITE_PURPOSE.md` + `KBITE_INDEX.md`,
then the top chewed files). Prefer kbites already listed in
`session_data.gmcc.yaml`'s `kbite:` registry. Do not block on an
AskUserQuestion for kbite selection — only load what the task needs.

---

## Phase 2: Do the Task

Execute the user's request directly in the primary context using
Read / Edit / Write / Grep / Glob / Bash (and Task for subagents if a search
genuinely warrants it).

- Edit the user's repository files freely — that is the work.
- **Do not** create or modify anything under `$GMCC_CKFS_ROOT` (no prompt
  folders, no edits to `session_data.gmcc.yaml`, no `memory/` artifacts).
- If the task balloons in scope and would benefit from the full clarify → plan →
  review pipeline, suggest the user re-run it under `/gm_bot` (or `/gm_bot_rpi`
  / `/gm_bot_team`) rather than reaching for ckfs bookkeeping here.

When finished, give a concise summary: what you did, files touched, anything
deferred. Do **not** persist that summary anywhere — it stays in the chat.

---

## Retroactive Write-Back (only on explicit request)

Skip this section entirely unless the user, at some point in the conversation,
explicitly asks you to record the work into the ckfs (e.g. "save that to the
session", "record the files you changed", "write this up as a prompt"). Honor
exactly what they ask for; do not volunteer writes.

Two write targets are supported.

### A. Record changed files

Append the files you modified to `session_data.gmcc.yaml`'s `changed_files:`
list. Each entry conforms to `gmcc_session_data_file_changed_files_entry`:

```yaml
- file: {path relative to instance}
  timestamp: {ISO 8601}
  lines: [[start, end], ...]
  commit: {short sha if committed, else "uncommitted"}
  note: ""
```

### B. Record a prompt

Capture the task after the fact as a prompt folder (no clarify pipeline is run,
so it lands as a `Draft`).

1. Pick next prompt id: max existing id in `session_data.gmcc.yaml` + 1, or 1.
2. Create `$GMCC_SESSION_PATH/prompts/{id}_{name}/` and a `memory/` subdir.
3. Write `{id}_{name}_data.gmcc.yaml` (conforms to `gmcc.gmcc_prompt_data_file`,
   seed `kbite:` from `session_data.kbite`):

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
   kbite: []
   initial_prompt_path: {id}_{name}_initial.yaml
   clarified_prompt_path: ""
   prompt_status: Draft
   command: /gm_task
   ```

4. Write `{id}_{name}_initial.yaml` (conforms to
   `gmcc.gmcc_initial_prompt_file`) capturing the task as it was actually
   carried out:

   ```yaml
   yeet:
     - gmcc
   yeet_type: gmcc.gmcc_initial_prompt_file

   backstory: |
     {inherited from session_data.gmcc.yaml's backstory; "" if unset}
   goal: |
     {what the task aimed to achieve}
   detail: |
     {how it was done — the specifics}
   kbites_loaded: []
   ```

5. Append the stub to `session_data.gmcc.yaml`'s `prompts:` list (conforms to
   `gmcc_session_data_file_prompt_files_entry`):

   ```yaml
   - id: {id}
     name: {name}
     status: Draft
     path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml
   ```

After any write-back, state plainly what was persisted and where.
