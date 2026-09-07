---
name: gm_bot
description: Lightweight GMCC workflow. Authors a prompt into the current session over the daemon, clarifies it, and implements. All phases run in primary context with no subagents.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot (Lightweight)

You are executing a lightweight development workflow entirely in the primary context.

All persistence goes through the `gm` CLI (bare `gm` — it is on the session PATH) — see `skills/gmcc_daemon/SKILL.md` for the subcommand reference and `skills/gmcc/ref/bot_workflows.md` for the canonical lifecycle. Never read or write ckfs yamls.

The full gm verb surface is already in context: the SessionStart hook prints
`gm cheatsheet` (exact signatures + invariants). Never run `gm ... --help`
roundtrips or guess flags — consult the sheet; run `gm cheatsheet` again only
if it is missing from context.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook runs `gm context ensure`; the session env is emitted by `gm context env` (GMCC_BOOTED, GMCC_PLUGIN_ROOT, GMCC_CKFS_ROOT, PATH — plus GMCC_ROOT when sandboxed), and all paths come from `gm paths`.

1. `gm session get --json` for current session state (session row + prompt stubs + change summary). If this exits 2 (daemon unreachable), self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`, then retry.
2. One call for the whole session's report state: `gm prompt list --with-reports --json`. Each stub carries its clarification/architecture status, refined goal, backstory note, summary version, and counts; a null report means that summary was never opened. For topic lookup across prompts use `gm search "<topic>" --json` — do NOT grep the ckfs and do NOT open memory files to find prior context. (`gm search` covers prompt/clarification/architecture/exploration/review text; the stubs also carry exploration/review state — findings, sub-100 counts, unranked resume signals, verdicts.)

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
3. Determine the entry point from the row's `status` (lifecycle v2):
   - `draft` → run on the row's verbatim content, jump to Phase 2
   - `clarifying` → re-enter Phase 3 from where it stalled (`gm clarify get` shows the summary status and open questions; content is locked)
   - `architecting` → jump to Phase 4 (`gm arch get` shows what is already authored)
   - `implementing` → jump to Phase 5 (`gm arch get` is the approved plan + implementation state)
   - `reviewing` → jump to Phase 6
   - `done` → report complete; further work is a NEW prompt
4. The remaining arguments (if any) become the continuation prompt. With no
   remaining arguments, run the drafted prompt as written — this is the
   GMVibes "run this prompt" path.
5. `command` is create-time-only in the db (no gm write path). If the row's
   `command` is empty (externally-authored drafts), record the executing
   tier in the clarification's `--backstory-note` during finalize.

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot auth-refactor implement OAuth2 flow
         ^prompt name  ^prompt content
```
1. Create the prompt row (see Prompt Creation below) — the daemon allocates `seq` atomically.
2. Create the memory dir at the path the daemon returned — the db value is the authority and the watcher matches it exactly:
   ```bash
   mkdir -p "$GMCC_CKFS_ROOT/<ckfs_relative_storage_path from the create response>/memory"
   ```
   (`$GMCC_CKFS_ROOT` unset? `gm paths --json | jq -r .ckfs_root`.) NEVER re-derive `{seq}_{name}` yourself: the daemon slugs the name, so a hand-built path can diverge and silently break memory-change events.
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
gm prompt create --name {name} \
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
> (`update-content` is draft-only; content locks on entering
> `clarifying`). From then on the source of truth is the db-native
> clarification (refined goal/detail on the summary; finalize copies the
> refined goal into `prompt.goal`); the row's `detail` stays the verbatim
> original forever.

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
   (`{kbite_root}/{name}/KBITE_PURPOSE.md`, kbite_root from
   `gm paths --json`), then
   `gm kbite get --code {name} --json` for the resource/file-stub/keyword
   overview, then `gm kbite search "<topic>" --json` (bm25 relevance-ordered;
   `--code {name}` scopes to one kbite). Read the `file_summary` brief on
   every hit and `gm kbite file-get --file-uuid U --json` every file whose
   brief is relevant to this prompt — typically 5-10 files, not a fixed
   top-N cap.

If the inherited list is empty and the prompt names no kbite, load nothing
and proceed to Phase 2.

### Phase 1b: DOPE Dump

`gm dope list --session-uuid U` — if the session carries a SESSION_BASE
scope, `gm dope get --session-uuid U --json` and keep the tree in primary
context through Phase 2 (this tier has no explore spawns, so primary
context IS the injection). The dump is always the persistence layer's
source of truth, boot-synced from `.gmcc`. No scope → note it and
move on. Full protocol: `skills/gmcc/ref/bot_workflows.md`.

---

## Phase 2: Implementation Overview

Explore the codebase using Glob/Grep/Read. Identify the files relevant to this prompt, the integration points, and any ambiguities to resolve in Clarify. Keep this in primary context — no subagents.

**Persist the exploration db-natively** — never write it to a file:

```bash
gm explore open --prompt-uuid U --json                  # explicit; works at draft
gm explore key-file-add --summary-uuid S --file-path <repo-relative>   # per key file (deduped)
gm explore finding-add --summary-uuid S --kind <kind> --title "..." \
  --body "..." --agent-name primary [--rating N]        # per finding
gm explore rank --summary-uuid S --rating <uuid>:<0-999> ...   # rank everything (0=critical, 999=ignore)
gm explore complete --summary-uuid S --expected-version V --overview "<narrative>"
```

`complete` refuses while any finding is unranked; the overview is writable only there, and exactly one of `--overview` / `--overview-file` is required. `key-file-add`/`finding-add`/`rank` are refused once complete — on a re-run: `gm explore reopen` → update → re-complete.

---

## Phase 3: Clarify (db-native)

The clarification is DB-NATIVE — no file mirror, no "grep-ability"
duplicate: the db rows ARE the record and `gm clarify get` is the render.
`SUMMARY_ABSENT` means open a summary (`gm clarify open`).
Thread `--expected-version` on every transition (capture `.version` from each
response; on `VERSION_CONFLICT`, re-read and retry). `gm prompt set-status`
is the ONLY door that moves the prompt; clarify verbs touch the summary only.

1. **Enter clarifying** (locks the STAY TRUE triple; the daemon creates the summary):
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status clarifying --json
   gm clarify get --prompt-uuid U --json        # → summary uuid + version
   ```

2. **Goal + detail question suites.** Insert what is underspecified about the *outcome* (`--category goal`: acceptance criteria, scope, definition of done) and the *approach* (`--category detail`: edge cases, integration points, design preferences) as open questions via `gm clarify ask`.

3. **Seal and answer.** Lock the question list, put the open questions to the user (AskUserQuestion), and record each answer:
   ```bash
   gm clarify seal   --summary-uuid S --expected-version {sv}
   gm clarify answer --clarification-uuid C --expected-version {cv} --answer "<user's answer>" --source user
   gm clarify answer --clarification-uuid C --expected-version {cv} --answer "<judgment call>" --source bot_inferred   # granted-by-prompt resolutions
   gm clarify answer --clarification-uuid C --expected-version {cv} --skip                                             # explicitly not applicable
   ```

4. **Finalize + advance.** Synthesize the refined goal (acceptance criteria) and refined detail (detail + answers integrated); the daemon copies the refined goal into `prompt.goal` (`detail` stays the verbatim human input):
   ```bash
   gm clarify finalize --summary-uuid S --expected-version {sv} \
     --refined-goal "<acceptance criteria>" --refined-detail "<integrated detail>" [--backstory-note "..."]
   gm prompt set-status --prompt-uuid U --expected-version {v} --status architecting --json   # gate: summary must be complete
   ```
   A wrong answer discovered later: `gm clarify reopen` → re-answer → re-finalize.

---

## Phase 4: Plan (db-native architecture)

The architecture is DB-NATIVE — the db rows ARE the record and
`gm arch get` is the render. Entering `architecting` created the summary
(`gm arch get` for its uuid).

1. **Persistence check FIRST (universal):** determine whether this prompt touches the persistence layer (SQLite schema, GRDB records, any ORM entity). Record the outcome as `gm arch persist-add` rows — possibly zero — BEFORE any general change.
2. Author the plan:
   ```bash
   gm arch summarize   --summary-uuid S --expected-version {v} --body "<concept-level: approach, components, data flow, tradeoffs — NO file specifics>"
   gm arch persist-add --summary-uuid S --class-name C --file-path <repo-rel> --reason "..."      # per persistence class
   gm arch field-add   --persistence-uuid PC --field-name F --data-type T --reason "..." --purpose "..." --nullable|--no-nullable [--foreign-key --fk-target t.col] [--indexed]
   gm arch general-add --summary-uuid S --file-path <repo-rel> [--class-name C] --reason "..." --depth pseudo|draft|actual --code "<change code>"
   ```
   Change rows record ONLY implementation changes (test infra/config counts; individual test cases at most one summary row — never per-case).
3. **Propose and get approval:**
   ```bash
   gm arch propose --summary-uuid S --expected-version {v}
   ```
   Present the plan (AskUserQuestion). Approved → `gm arch approve`; changes requested → `gm arch revise` (back to drafting), edit, re-propose.
4. **Advance:**
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status implementing --json   # gate: architecture must be approved
   ```

---

## Phase 5: Implement

1. Execute the approved architecture — **persistence changes first, always** (general changes may assume the post-migration schema, never the reverse).
2. Make edits with Read/Edit/Write.
3. After each file write, record it (run from inside the repo; **always pass `--prompt-uuid`** — the implementation-state comparison sees only attributed changes):
   ```bash
   gm file-change add --path <repo-relative path> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```
   `--content` requires EXACTLY ONE `--range`; pass neither to record the file as touched without line detail.
4. `gm arch get --prompt-uuid U` at any point shows implementation state per change row (touched/untouched), unplanned changes (scope drift), and the persistence-first audit — use it to find what is left and debug drift.

---

## Phase 6: Review + Feedback

1. **Advance to reviewing** (`gm prompt set-status ... --status reviewing`), or skip straight to `done` when the user wants no review pass (`implementing → done` is the one legal skip edge).
2. Present a summary: files modified, key decisions, known limitations; check `gm arch get` for unimplemented rows and unplanned drift.
3. **Persist the review db-natively** — never write it to a file: `gm review open --prompt-uuid U`, `gm review finding-add` per finding (kind/title/body, optional --file-path/--line-start/--line-end), `gm review rank`, then `gm review complete --overview "<narrative>" --verdict approved|approved_with_nits|changes_requested`. During the fix loop record each outcome: `gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix` (works after complete — that is when the loop runs; address every finding rated under 100).
4. Wait for user feedback; iterate. When satisfied: `gm prompt set-status ... --status done`.

There is no phase-history record — completion is prompt status `done` plus
the clarification/architecture/exploration/review rows and file-change trail.

```
Bot Complete: prompt {seq} ({name})

**Session**: {session ckfs_relative_storage_path from gm session get --json}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Implementation state**: {from gm arch get: N/M rows touched, unplanned count}
**Changes**: {brief summary}

**Next**: continue with more work in this session, or `/gm_bot <name> ...` to start a new prompt.
```

---

## Error Handling

**Daemon unreachable (`gm` exit 2):** self-heal — `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh && gm context ensure`, retry once, then surface `gm status` to the user.

**VERSION_CONFLICT:** re-run `gm prompt get --prompt-uuid U --json`, take the fresh `version`, retry the mutation.

**Session paused (user stops responding):**
```
State preserved: prompt row (gm prompt get) + report rows (gm clarify/arch/explore/review get)

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
