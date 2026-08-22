---
name: gm_bot
description: Lightweight GMCC workflow. Authors a prompt into the current session over the daemon, clarifies it, and implements. All phases run in primary context with no subagents.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot (Lightweight, v16.3.0)

You are executing a lightweight development workflow entirely in the primary context.

All persistence goes through the `gm` CLI (`~/gmcc/bin/gm`) — see `skills/gmcc_daemon/SKILL.md` for the subcommand reference and `skills/gmcc/ref/bot_workflows.md` for the canonical lifecycle. Never read or write ckfs yamls.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook exports env, `mkdir`s `$GMCC_SESSION_PATH/prompts/`, and runs `gm context ensure`.

1. `~/gmcc/bin/gm session get --json` for current session state (session row + prompt stubs + change summary). If this exits 2 (daemon unreachable), self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`, then retry.
2. Skim recent prompts' `memory/qualified.md` files under `$GMCC_SESSION_PATH/prompts/*/memory/` for context if relevant.

---

## Argument Parsing

Parse `$ARGUMENTS`:

### Case 1: First token is numeric (RUN / RESUME mode)
```
/gm_bot 3                            # run prompt 3 as-is (continuation optional)
/gm_bot 3 continue with the login endpoint
         ^prompt seq  ^continuation (optional)
```
A prompt row may have been authored **externally** (e.g. by the GMVibes
editor over the daemon) and never touched by the bot, or partway-processed
by a prior run. Either way, a bare `/gm_bot {seq}` runs it through the
normal pipeline from its current status entry point — no continuation text
required.

1. `gm prompt list --json`; find the stub with `seq: 3`, then `gm prompt get --prompt-uuid U --json` (full content + artifacts + version).
2. If not found: error "No prompt with seq 3 in current session".
3. Determine the entry point from the row's `status`:
   - `clarified` → read `memory/qualified.md` (via the artifact pointer), jump to Phase 4 (Plan)
   - `clarifying` → re-enter Phase 3 (Clarify) from where it stalled (content is locked — output goes to `qualified.md` only)
   - `draft` → run on the row's verbatim content, jump to Phase 2
4. The remaining arguments (if any) become the continuation prompt. With no
   remaining arguments, run the drafted prompt as written — this is the
   GMVibes "run this prompt" path.
5. `command` is create-time-only in the db (no gm write path). If the row's
   `command` is empty (externally-authored drafts), record the executing
   tier in `qualified.md`'s header during Clarify.

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot auth-refactor implement OAuth2 flow
         ^prompt name  ^prompt content
```
1. Create the prompt row (see Prompt Creation below) — the daemon allocates `seq` atomically.
2. `mkdir -p "$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory"`.
3. Proceed to Phase 1.

### Case 3: No arguments
Use AskUserQuestion:
```
What would you like to work on?

Provide a short kebab-case name + task description.
Example: auth-refactor implement OAuth2 flow

- Enter description - Type your task
```

---

## Prompt Creation (NEW mode)

```bash
~/gmcc/bin/gm prompt create --name {name} \
  --detail "<the entire passed prompt, verbatim>" \
  --backstory "<session row's backstory, verbatim; omit if empty>" \
  --command /gm_bot --json
```

Capture `uuid`, `seq`, `version` (0 on create) from the JSON.

**STAY TRUE — do NOT split, infer, or author `backstory`/`goal`/`detail`.**
These are human-authored only. The entire passed prompt is `--detail`,
**verbatim**. `goal` is omitted (empty at create; the Phase 3 Clarify suite
fleshes it out later). `backstory` is inherited from the session row
(empty if unset). Never move part of the prompt into `goal`, never
paraphrase, never invent an outcome.

The daemon seeds the prompt's kbite list from the session's active kbites
at create time.

> **External authoring surface.** While status is `draft`, the prompt
> row's `backstory`/`goal`/`detail` are the human authoring surface —
> external tools (e.g. GMVibes) edit them over the daemon
> (`update-content` is draft-only). Once a prompt is `clarified`, the
> source of truth moves to `memory/qualified.md`; the row's `detail`
> stays the verbatim original forever.

---

## Phase 1: KBite Loading (New Prompt Only)

Skip if resuming a prompt whose kbites were already loaded.

KBites are **inherited, not auto-detected**. The relevant kbites are already
declared up the chain — project → instance → session → prompt — and were
seeded into the prompt row's active list at create time. There is no trigger
matching and no kbite picker.

1. Read the inherited kbite list from `gm prompt get --prompt-uuid U --json` (`kbite_codes`).
2. **Explicit add only.** If the user's prompt text explicitly asks to add a
   kbite (e.g. "add the swift_ui kbite"), register it
   (`gm kbite add --code C --scope prompt --owner-uuid U`). Never add a
   kbite on your own initiative.
3. For each inherited/added kbite, load its context from the db (digested
   knowledge is db-canonical): read the purpose at the kbite root
   (`$GMCC_KBITE/{name}/KBITE_PURPOSE.md`), then
   `gm kbite get --code {name} --json` for the resource/file-stub/keyword
   overview, `gm kbite search "<topic>" --json` to rank what matters for
   this prompt, and `gm kbite file-get --file-uuid U --json` to pull the top
   3-5 highest-relevance files' full content.

If the inherited list is empty and the prompt names no kbite, load nothing
and proceed to Phase 2.

---

## Phase 2: Implementation Overview

Explore the codebase using Glob/Grep/Read. Identify the files relevant to this prompt, the integration points, and any ambiguities to resolve in Clarify. Keep this in primary context — no subagents.

**Persist your exploration notes** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/explore.md` (concise markdown — files surveyed, patterns spotted, open questions), then register the pointer:

```bash
gm artifact add --prompt-uuid U --file-path ".../memory/explore.md" \
  --kind explore --note "<one-sentence caption>"
```

---

## Phase 3: Clarify

Runs while the prompt is still `draft` — content is unlocked until the first status transition.

1. **YEET-type detection (FIRST clarify step).** Before any other clarification, scan the prompt row's `goal` + `detail` for YEETS types:
   - **Declared** — types named explicitly in the prose (e.g. "a new yeet type for X", a mentioned struct/enum name).
   - **Inferred** — data shapes the prompt describes structurally without naming a type (e.g. "a record holding a name and a list of amounts" → a candidate struct).

   For each detected type, try to resolve it confidently (to a concrete struct/enum in `gmcc.yeet.yaml` or a sibling `.yeet.yaml`, to a new type to create, or to a clear action). If you **cannot** resolve it confidently, you **must** AskUserQuestion to clarify the intended typing behavior. Record every detection in `qualified.md`'s `detected_yeet_types` section with `source:` (`declared`/`inferred`) and `confidence:` (`confident`/`needs_clarification`); note explicitly if none.

2. **Goal clarification suite.** Identify what is underspecified about the *outcome* (acceptance criteria, scope boundaries, definition of done). AskUserQuestion; record under `goal_clarifications`.

3. **Detail clarification suite.** Identify what is underspecified about the *approach* (edge cases, integration points, design preferences, backwards compat). AskUserQuestion; record under `detail_clarifications`.

4. Write `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/qualified.md` — markdown with sections: backstory note, `goal_clarifications` / `detail_clarifications` (Q/A), `refined_goal` (the acceptance criteria), `refined_detail` (initial detail + clarifications integrated — the from-Clarify source of truth), `detected_yeet_types`, `key_files`, `constraints`, `kbites_loaded`. Register it:
   ```bash
   gm artifact add --prompt-uuid U --file-path ".../memory/qualified.md" \
     --kind qualified --note "<one-sentence caption>"
   ```

5. Write back the refined goal and transition, threading `--expected-version` (capture `.version` from each response; on `VERSION_CONFLICT`, re-`gm prompt get` and retry):
   ```bash
   gm prompt update-content --prompt-uuid U --expected-version {v}   --goal "<refined_goal>" --json   # → v+1 (goal only; detail stays verbatim)
   gm prompt set-status     --prompt-uuid U --expected-version {v+1} --status clarifying --json       # → v+2 (locks content)
   gm prompt set-status     --prompt-uuid U --expected-version {v+2} --status clarified  --json       # → v+3
   ```

---

## Phase 4: Plan

1. Enter plan mode using EnterPlanMode.
2. Design the implementation approach based on `qualified.md` + kbite context + exploration findings.
3. Write a concrete plan with files-to-edit, ordered steps, and key patterns to follow.
4. Exit plan mode for user approval.
5. **Persist the approved plan** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/architecture.md` and register it (`gm artifact add --kind architecture --note "..."`).

---

## Phase 5: Implement

1. Execute the approved plan.
2. Make edits with Read/Edit/Write.
3. After each file write, record it (run from inside the repo — git context is auto-detected):
   ```bash
   gm file-change add --path <repo-relative path> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```

---

## Phase 6: Feedback Integration

1. Present a summary: files modified, key decisions, known limitations.
2. **Persist a brief review note** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/review.md` covering what was built, what was deferred, and any known limitations; register it (`gm artifact add --kind review --note "..."`).
3. Wait for user feedback. Iterate until satisfied.

There is no phase-history record — completion is represented by prompt
status `clarified` plus the registered artifacts and file-change trail.

```
Bot Complete: prompt {seq} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Changes**: {brief summary}

**Next**: continue with more work in this session, or `/gm_bot <name> ...` to start a new prompt.
```

---

## Error Handling

**Daemon unreachable (`gm` exit 2):** self-heal — `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh && gm context ensure`, retry once, then surface `gm status` to the user.

**VERSION_CONFLICT:** re-run `gm prompt get --prompt-uuid U --json`, take the fresh `version`, retry the mutation.

**Session paused (user stops responding):**
```
State preserved: prompt row (gm prompt get) + $GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/

To resume: /gm_bot {seq} <continuation prompt>
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
