---
name: gm_bot_rpi
description: Subagent-based Research/Plan/Implement workflow. Spawns specialized GMCC subagents for exploration, architecture, and code review while keeping clarification and implementation in primary context. Authors prompts into the current session over the daemon.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement, v16.3.0)

You are executing an enhanced development workflow that leverages GMCC subagents for Research, Planning, and Review phases. Same prompt-into-session model as `/gm_bot`, with subagents added to Phases 2, 4, and 6. Subagent reports are persisted to `prompts/{seq}_{name}/memory/` and registered in the daemon db.

All persistence goes through the `gm` CLI (`~/gmcc/bin/gm`) — see `skills/gmcc_daemon/SKILL.md` for the full subcommand reference and `skills/gmcc/ref/bot_workflows.md` for the canonical lifecycle. Never read or write ckfs yamls.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook exports env, `mkdir`s `$GMCC_SESSION_PATH/prompts/`, and runs `gm context ensure`. Then:

1. `~/gmcc/bin/gm session get --json` for current session state (session row + prompt stubs + change summary). If this exits 2 (daemon unreachable), self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`, then retry.
2. Skim recent prompts' clarifications for context (`gm clarify get --prompt-uuid U`; legacy prompts keep `memory/qualified.md`).

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Run / Resume** (`/gm_bot_rpi 3` or `/gm_bot_rpi 3 ...`): `gm prompt list --json`, find the stub with `seq: 3`, then `gm prompt get --prompt-uuid U --json`. Resume by status (lifecycle v2): `draft` → Phase 2, `clarifying` → Phase 3 (`gm clarify get` shows where it stalled), `architecting` → Phase 4, `implementing` → Phase 5, `reviewing` → Phase 6, `done` → complete. Legacy pre-m0002 prompts have no clarify/arch rows — check `gm artifact list` instead; never fabricate rows. A bare seq (no continuation) runs an externally-authored draft (e.g. from the GMVibes editor) as written; `command` is create-time-only in the db — if empty, note the executing tier in the clarification's `--backstory-note`.
- **New** (`/gm_bot_rpi auth-refactor ...`): create the prompt row (below), proceed.
- **No args**: AskUserQuestion for name + content.

---

## Prompt Creation (New Prompt)

```bash
~/gmcc/bin/gm prompt create --name {name} \
  --detail "<the entire passed prompt, verbatim>" \
  --backstory "<session row's backstory, verbatim; omit if empty>" \
  --command /gm_bot_rpi --json
```

Capture `uuid`, `seq`, `version` (0 on create) from the JSON. Then:

```bash
mkdir -p "$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory"
```

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
   (`$GMCC_KBITE/{name}/KBITE_PURPOSE.md`), get the resource/file-stub/keyword
   overview (`gm kbite get --code {name} --json`), rank relevant files
   (`gm kbite search "<topic>" --json`), pull the top 3-5 files' full content
   (`gm kbite file-get --file-uuid U --json`), and compile a
   **kbite context summary** (key learnings, takeaways, patterns).
4. Keep the summary in primary context — it is passed to every subagent spawn.

---

## Phase 2: Implementation Overview (Explore Subagent)

Spawn 1 explore subagent via Task tool. The subagent does its work in its own context window; it returns a structured report as its final message. The primary context receives the report content **and persists it** to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/explore.md` (see `skills/gmcc/ref/bot_workflows.md`).

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

    ## Task Context
    **Exploration Target**: {prompt row's goal + detail}
    **Repository**: Explore from the current working directory
    **Branch**: $(basename $GMCC_SESSION_PATH)

    ## KBite Knowledge
    {kbite context summary}

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

Read the returned report into the primary context, write it verbatim to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/explore.md`, and register it:

```bash
gm artifact add --prompt-uuid U --file-path "$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/explore.md" \
  --kind explore --note "<one-sentence caption of the exploration>"
```

Use it to inform Clarify.

---

## Phase 3: Clarify (db-native)

The clarification is DB-NATIVE (no qualified.md — legacy path only). Thread
`--expected-version` on every transition (on `VERSION_CONFLICT`, re-read and
retry). `gm prompt set-status` is the ONLY door that moves the prompt.

1. **Enter clarifying** (locks content; the daemon creates the summary):
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status clarifying --json
   gm clarify get --prompt-uuid U --json        # → summary uuid + version
   ```

2. **YEET-type detection (FIRST clarify step).** Scan the prompt row's `goal` + `detail` (cross-referenced with the exploration report) for YEETS types — **declared** (named in prose) and **inferred** (shapes described without a name). Record each via `gm clarify ask --category yeet_type`, pre-answered (`--answer ... --source bot_inferred`) when confidently resolved, open otherwise (the open ones go to the user).

3. **Goal + detail question suites.** Insert outcome questions (`--category goal`) and approach questions (`--category detail`) via `gm clarify ask`, informed by the exploration report.

4. **Seal, ask the user, record answers:**
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
(`gm arch` rows — no architecture.md) after user approval.

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

Write the review report (verbatim from the subagent) to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/review.md` and register it (`gm artifact add --kind review --note "..."`).

---

## Phase 7: Feedback Integration

1. Present a complete summary: what was built, files modified, review findings addressed, known limitations.
2. Wait for user feedback. Iterate until satisfied.

There is no phase-history record — completion is represented by prompt
status `done` plus the clarification/architecture rows, registered artifacts, and file-change trail
(`gm prompt get`, `gm file-change list`).

```
Bot RPI Complete: prompt {seq} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
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
State preserved: prompt row (gm prompt get) + $GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/

To resume: /gm_bot_rpi {seq} <continuation prompt>
```

**Task grows in scope:**
```
This task may benefit from full agent team treatment.

- Continue as /gm_bot_rpi
- Switch to /gm_bot_team
```
