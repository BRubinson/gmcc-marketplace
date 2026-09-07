---
name: gm_bot_rpi
description: Subagent-based Research/Plan/Implement workflow. Spawns specialized GMCC subagents for exploration, architecture, and code review while keeping clarification and implementation in primary context. Authors prompts into the current session over the daemon.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement)

You are executing an enhanced development workflow that leverages GMCC subagents for Research, Planning, and Review phases. Same prompt-into-session model as `/gm_bot`, with subagents added to Phases 2, 4, and 6. Subagent reports are persisted to `prompts/{seq}_{name}/memory/` and registered in the daemon db.

All persistence goes through the `gm` CLI (bare `gm` — it is on the session PATH) — see `skills/gmcc_daemon/SKILL.md` for the full subcommand reference and `skills/gmcc/ref/bot_workflows.md` for the canonical lifecycle. Never read or write ckfs yamls.

The full gm verb surface is already in context: the SessionStart hook prints
`gm cheatsheet` (exact signatures + invariants). Never run `gm ... --help`
roundtrips or guess flags — consult the sheet.

**Cheatsheet mandate for subagents.** Subagents do not inherit SessionStart
context. Every Task prompt in the phases below must additionally include a
`## GM Cheatsheet` section containing the verbatim output of
`gm cheatsheet`, so workers read gm data shapes and report against
the real verb surface.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook runs `gm context ensure`; the session env is emitted by `gm context env` (GMCC_BOOTED, GMCC_PLUGIN_ROOT, GMCC_CKFS_ROOT, PATH — plus GMCC_ROOT when sandboxed), and all paths come from `gm paths`. Then:

1. `gm session get --json` for current session state (session row + prompt stubs + change summary). If this exits 2 (daemon unreachable), self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`, then retry.
2. One call for the whole session's report state: `gm prompt list --with-reports --json` (per-prompt clarification/architecture status, refined goal, backstory note, version, counts). A null report means that summary was never opened. Topic lookup across prompts is `gm search "<topic>" --json` — do NOT grep the ckfs or open memory files for context; all four reports are db rows and the stubs carry their state.

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Run / Resume** (`/gm_bot_rpi 3` or `/gm_bot_rpi 3 ...`): `gm prompt list --json`, find the stub with `seq: 3`, then `gm prompt get --prompt-uuid U --json`. Resume by status (lifecycle v2): `draft` → Phase 2, `clarifying` → Phase 3 (`gm clarify get` shows where it stalled), `architecting` → Phase 4, `implementing` → Phase 5, `reviewing` → Phase 6, `done` → complete. A bare seq (no continuation) runs an externally-authored draft (e.g. from the GMVibes editor) as written; `command` is create-time-only in the db — if empty, note the executing tier in the clarification's `--backstory-note`.
- **New** (`/gm_bot_rpi auth-refactor ...`): create the prompt row (below), proceed.
- **No args**: AskUserQuestion for name + content.

---

## Prompt Creation (New Prompt)

```bash
gm prompt create --name {name} \
  --detail "<the entire passed prompt, verbatim>" \
  --backstory "<session row's backstory, verbatim; omit if empty>" \
  --command /gm_bot_rpi --json
```

Capture `uuid`, `seq`, `version` (0 on create) **and
`ckfs_relative_storage_path`** from the JSON. Then create the memory dir at
the RETURNED path — the db value is the authority and the memory watcher
matches it by exact case-sensitive equality:

```bash
mkdir -p "$GMCC_CKFS_ROOT/<ckfs_relative_storage_path from the response>/memory"
```

(`$GMCC_CKFS_ROOT` unset? `gm paths --json | jq -r .ckfs_root`.) NEVER
re-derive `{seq}_{name}` yourself: the daemon slugs the name, so a hand-built
path can diverge and silently break memory-change events.

**STAY TRUE — do NOT split, infer, or author `backstory`/`goal`/`detail`.**
The entire passed prompt is `--detail`, **verbatim**. `goal` is omitted
(empty — human input only; Clarify fills it later). `backstory` is the
session row's value verbatim (`gm session get --json`). Never split a blob
into goal vs detail, never paraphrase, never invent an outcome.

The daemon allocates `seq` atomically and seeds the prompt's kbite list
from the session's active kbites.

---

## Phase 1: KBite Loading (New Prompt Only)

KBites are **inherited, not auto-detected** — already seeded into the prompt
row's active list at create time. No trigger matching, no kbite picker.

1. Read the inherited kbite list from `gm prompt get --prompt-uuid U --json`
   (`kbite_codes`).
2. **Explicit add only.** If the user's prompt text explicitly asks to add a
   kbite, register it (`gm kbite add --code C --scope prompt --owner-uuid U`).
   Never add one on your own.
3. For each inherited/added kbite: read the purpose at the kbite root
   (`{kbite_root}/{name}/KBITE_PURPOSE.md`, kbite_root from
   `gm paths --json`), get the resource/file-stub/keyword
   overview (`gm kbite get --code {name} --json`), rank relevant files
   (`gm kbite search "<topic>" --json` — bm25 relevance-ordered; `--code`
   scopes to one kbite), read the `file_summary` brief on every hit, pull the
   full content of every file whose brief is relevant — typically 5-10, not a
   fixed top-N cap (`gm kbite file-get --file-uuid U --json`) — and compile a
   **kbite context summary** (key learnings, takeaways, patterns).
4. Keep the summary in primary context — it is passed to every subagent spawn.

### Phase 1b: DOPE Dump

`gm dope list --session-uuid U` — if the session carries a SESSION_BASE
scope, `gm dope get --session-uuid U --json` and hold the tree in primary
context: it is **force-injected into every explore spawn** as a
`## Domain Model (DOPE)` block (explorers do not choose whether to load
it); architects get the fetch command and load on demand. The dump is
always the persistence layer's source of truth (boot-synced from
`.gmcc`). No scope → note it and move on. Full protocol:
`skills/gmcc/ref/bot_workflows.md`.

---

## Phase 2: Implementation Overview (Explore Subagent)

Spawn 1 explore subagent via Task tool. The subagent does its work in its own context window and returns a FINDING-SHAPED report as its final message (key files + findings with kind/title/body/self-rated 0-999 rating — see the explorer prompt file). The subagent cannot run gm (read-only sandbox), so the PRIMARY holds the pen: it transcribes the report into db rows (see `skills/gmcc/ref/bot_workflows.md`).

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

    ## Task Context
    **Exploration Target**: {prompt row's goal + detail}
    **Repository**: Explore from the current working directory
    **Branch**: {session code from gm session get}

    ## KBite Knowledge
    {kbite context summary}

    ## Domain Model (DOPE)
    {dope dump — the session's SESSION_BASE tree from gm dope get, force-injected; it IS the persistence layer. Omit the section only when the session has no dope scope, and say so.}

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

Read the returned report into the primary context and transcribe it db-natively — never write it to a file:

```bash
gm explore open --prompt-uuid U --json                  # explicit; works at draft
gm explore key-file-add --summary-uuid S --file-path <path>            # per key file
gm explore finding-add --summary-uuid S --kind <kind> --title "..." \
  --body "..." --agent-name explorer --rating <subagent's self-rating>  # per finding
gm explore rank --summary-uuid S --rating <uuid>:<0-999> ...  # adjust ratings where you disagree
gm explore complete --summary-uuid S --expected-version V --overview "<your synthesis of the report>"
```

`complete` refuses unranked findings; the overview is writable only there (primary-agent-only by shape). Use the ranked findings to inform Clarify.

---

## Phase 3: Clarify (db-native)

The clarification is DB-NATIVE — no file mirror, no "grep-ability"
duplicate: the db rows ARE the record, `gm clarify get` is the render, and
`SUMMARY_ABSENT` means `gm clarify open`. Thread `--expected-version` on every transition (on
`VERSION_CONFLICT`, re-read and retry). `gm prompt set-status` is the ONLY
door that moves the prompt.

1. **Enter clarifying** (locks content; the daemon creates the summary):
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status clarifying --json
   gm clarify get --prompt-uuid U --json        # → summary uuid + version
   ```

2. **Goal + detail question suites.** Insert outcome questions (`--category goal`) and approach questions (`--category detail`) via `gm clarify ask`, informed by the exploration report.

3. **Seal, ask the user, record answers:**
   ```bash
   gm clarify seal   --summary-uuid S --expected-version {sv}
   gm clarify answer --clarification-uuid C --expected-version {cv} --answer "..." --source user|bot_inferred   # or --skip
   ```

5. **Finalize + advance** (the daemon copies the refined goal into `prompt.goal`; `detail` stays verbatim):
   ```bash
   gm clarify finalize --summary-uuid S --expected-version {sv} \
     --refined-goal "<acceptance criteria>" --refined-detail "<detail + answers + exploration findings, integrated>"
   gm prompt set-status --prompt-uuid U --expected-version {v} --status architecting --json
   ```

---

## Phase 4: Plan (Architect Subagent, db-native persistence)

Spawn 1 architect subagent. The returned architecture is persisted to the DB
after user approval — never to a file. The `gm arch` rows ARE the record,
`gm arch get` is the render, and `SUMMARY_ABSENT` means `gm arch open`.

```
Task tool:
  subagent_type: general-purpose
  model: opus
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

    ## Architecture Context
    **Goal**: {refined_goal from the clarification summary}
    **Detail**: {refined_detail from the clarification summary}

    ## Qualified Prompt
    {gm clarify get output: refined goal/detail + all Q/A rows}

    ## Exploration Findings
    {exploration report from Phase 2, in primary context}

    ## KBite Knowledge
    {kbite context summary}

    ## Domain Model (DOPE)
    The session's dope tree is the persistence layer's source of truth — load it on demand with `gm dope get --session-uuid {U} --json`. An architecture proposing new persistence is proposing dope changes.

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

Persist the architecture db-natively (the summary was created on entering `architecting`; `gm arch get` for its uuid):

1. **Persistence check FIRST (universal):** does the plan touch the persistence layer (schema/ORM classes)? Record those as `gm arch persist-add` + `gm arch field-add` rows — possibly zero — before anything else.
2. `gm arch summarize --body "<concept-level approach/components/flow/tradeoffs>"`; then `gm arch general-add` per non-persistence change (`--depth pseudo|draft|actual --code "..."`). Change rows record implementation changes only (test infra counts; never per-test-case rows).
3. `gm arch propose` → present to the user (AskUserQuestion above) → approved: `gm arch approve`; changes requested: `gm arch revise`, edit rows, re-propose.
4. `gm prompt set-status --prompt-uuid U --expected-version {v} --status implementing --json` (gate: architecture approved).

---

## Phase 5: Implement

1. Follow the approved architecture's build sequence.
2. Make edits with Read/Edit/Write.
3. After each file write, record it (run from inside the repo — git context is auto-detected):
   ```bash
   gm file-change add --path <repo-relative path> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
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
    **Task**: {refined_goal + refined_detail from the clarification summary}

    ## Qualified Prompt
    {gm clarify get output}

    ## Architecture
    {architecture doc from Phase 4}

    ## Files Changed
    {output of: gm file-change list --prompt-uuid U}

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

Transcribe the review report db-natively — never to a file: `gm review open --prompt-uuid U`, `gm review finding-add` per finding (with the subagent's self-rating and location fields), `gm review rank` to adjust, `gm review complete --overview "<synthesis>" --verdict approved|approved_with_nits|changes_requested`. As fixes land, record each outcome with `gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix` (works after complete; address every finding rated under 100).

---

## Phase 7: Feedback Integration

1. Present a complete summary: what was built, files modified, review findings addressed, known limitations.
2. Wait for user feedback. Iterate until satisfied.

There is no phase-history record — completion is represented by prompt
status `done` plus the clarification/architecture/exploration/review rows and file-change trail
(`gm prompt get`, `gm file-change list`).

```
Bot RPI Complete: prompt {seq} ({name})

**Session**: {session ckfs_relative_storage_path from gm session get --json}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Review Status**: {pass / pass_with_issues}

**Next**: continue with more prompts in this session, or start a new prompt with `/gm_bot_rpi <name> ...`.
```

---

## Error Handling

**Daemon unreachable (`gm` exit 2):**
```
[GMB] daemon unreachable — self-healing

bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh && gm context ensure
```
Retry the failed call once after the build; if still failing, surface `gm status` output to the user.

**VERSION_CONFLICT:** re-run `gm prompt get --prompt-uuid U --json`, take the fresh `version`, retry the mutation.

**Subagent spawn failure:**
```
[GMB] Subagent spawn failed for {phase}

Falling back to primary context for this phase.
```
Continue the phase in primary context as a fallback.

**Session paused:**
```
State preserved: prompt row (gm prompt get) + report rows (gm clarify/arch/explore/review get)

To resume: /gm_bot_rpi {seq} <continuation prompt>
```

**Task grows in scope:**
```
This task may benefit from full agent team treatment.

- Continue as /gm_bot_rpi
- Switch to /gm_bot_team
```
