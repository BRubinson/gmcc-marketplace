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
2. Skim recent prompts' `memory/qualified.md` files under `$GMCC_SESSION_PATH/prompts/*/memory/` for context.

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Run / Resume** (`/gm_bot_rpi 3` or `/gm_bot_rpi 3 ...`): `gm prompt list --json`, find the stub with `seq: 3`, then `gm prompt get --prompt-uuid U --json`. Run from Phase 4 if `clarified`, re-enter Phase 3 if `clarifying`, jump to Phase 2 if `draft`. A bare seq (no continuation) runs an externally-authored draft (e.g. from the GMVibes editor) as written; `command` is create-time-only in the db — if empty, note the executing command in `qualified.md` during Clarify.
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

## Phase 3: Clarify

Runs while the prompt is still `draft` — content is unlocked until the first status transition.

1. **YEET-type detection (FIRST clarify step).** Scan the prompt row's `goal` + `detail` (cross-referenced with the exploration report) for YEETS types:
   - **Declared** — types named explicitly in the prose (e.g. "a new yeet type for X", a mentioned struct/enum).
   - **Inferred** — data shapes the prompt describes structurally without naming a type.

   Resolve each confidently (to an existing struct/enum, a new type to create, or a clear action). If you **cannot** resolve one confidently, you **must** AskUserQuestion to clarify the intended typing behavior. Record every detection in `qualified.md`'s `detected_yeet_types` section with `source:` + `confidence:` (empty section if none).

2. **Goal clarification suite.** Resolve what is underspecified about the *outcome* (acceptance criteria, scope boundaries, done definition), informed by the exploration report. AskUserQuestion → `goal_clarifications`.

3. **Detail clarification suite.** Resolve what is underspecified about the *approach* (uncertainties from exploration, edge cases, integration preferences). AskUserQuestion → `detail_clarifications`.

4. Write `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/qualified.md` — markdown with sections: backstory note, `goal_clarifications` / `detail_clarifications` (Q/A), `refined_goal`, `refined_detail` (initial detail + clarifications + exploration findings, integrated — the from-Clarify source of truth), `detected_yeet_types`, `key_files`, `patterns_to_follow`, `constraints`, `kbites_loaded`. Register it:
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

## Phase 4: Plan (Architect Subagent)

Spawn 1 architect subagent. The returned architecture is persisted to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/architecture.md` after user approval.

```
Task tool:
  subagent_type: general-purpose
  model: opus
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

    ## Architecture Context
    **Goal**: {refined_goal from qualified.md}
    **Detail**: {refined_detail from qualified.md}

    ## Qualified Prompt
    {full qualified.md contents}

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

Once approved, write the architecture (verbatim from the subagent) to `$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory/architecture.md` and register it (`gm artifact add --kind architecture --note "..."`).

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
    **Task**: {refined_goal + refined_detail from qualified.md}

    ## Qualified Prompt
    {qualified.md contents}

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
status `clarified` plus the registered artifacts and file-change trail
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
