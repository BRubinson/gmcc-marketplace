---
name: gm_bot_rpi
description: Subagent Research/Plan/Implement workflow. Spawns the native gmcc agents (code-explorer, code-architect, code-quality-reviewer, finding-reranker, doper) per phase; spawned agents write their own db rows. Authors prompts into the current session over the daemon.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement)

You are executing an enhanced development workflow that spawns the native
gmcc agents for Research, Planning, and Review phases. Same
prompt-into-session model as `/gm_bot`. This file is the canonical
orchestration walkthrough for subagent tiers — `gm_bot_team.md` documents
only what differs for real agent teams.

All persistence goes through the `gm` CLI (bare `gm` — it is on the session
PATH) — see `skills/gmcc_daemon/SKILL.md` for the subcommand reference and
`skills/gmcc/ref/bot_workflows.md` for the canonical lifecycle (state
machine, rating polarity, SUMMARY_ABSENT / version-conflict rules,
doper/briefing protocol, pen contract). Never read or write ckfs yamls.

SessionStart injects the compact `gm cheatsheet` core (family index + agent
pen verbs + invariants). For exact signatures run `gm cheatsheet --full` —
never `gm ... --help` roundtrips, never guess flags.

**Pen contract.** Spawned explorers and reviewers hold their own pen: they
write `gm explore key-file-add` / `finding-add` and `gm review finding-add`
rows directly, self-rated, with `--agent-name <methodology>`. The primary
keeps ONLY rank (delegated to `gmcc:finding-reranker`), `complete` (overview,
review verdict), and `resolve`. There is no transcription step and no
report-as-text format — spawned agents close with short receipts.

**Spawn prompts are task-only.** Identity, pen contract, methodology
definitions, and rating rules live in the agent defs
(`plugins/gmcc/agents/`); the SubagentStart hook provisions every
`gmcc:*` spawn with the compact cheatsheet core and a briefing stub naming
the exact pull command. Spawn prompts therefore carry ONLY task specifics
(uuids, methodology name, topic) — never kbite summaries, dope dumps, or
cheatsheets.

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

Current session state (inlined at invocation):

!`gm session get --json`
!`gm prompt list --with-reports --json`
!`gm dope list --json`

The session row carries backstory + prompt stubs + change summary; each
prompt stub carries its clarification/architecture/exploration/review state
(a null report means that summary was never opened); the dope list shows the
session's scopes. Topic lookup across prompts is `gm search "<topic>" --json`
— do NOT grep the ckfs or open memory files for context. If the inlined
calls errored with exit 2 (daemon unreachable), self-heal:
`bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`,
then re-run them.

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Run / Resume** (`/gm_bot_rpi 3` or `/gm_bot_rpi 3 ...`): find the stub with `seq: 3` in the inlined prompt list, then `gm prompt get --prompt-uuid U --json`. Resume by status (lifecycle v2): `draft` → Phase 2, `clarifying` → Phase 3 (`gm clarify get` shows where it stalled), `architecting` → Phase 4, `implementing` → Phase 5, `reviewing` → Phase 6, `done` → complete. A bare seq (no continuation) runs an externally-authored draft (e.g. from the GMVibes editor) as written; `command` is create-time-only in the db — if empty, note the executing tier in the clarification's `--backstory-note`.
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

(For a very long passed prompt, write it to a scratch file and pass
`--detail-file` instead — still verbatim.)

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
session row's value verbatim. Never split a blob into goal vs detail, never
paraphrase, never invent an outcome. Full rules:
`skills/gmcc/ref/bot_workflows.md`.

The daemon allocates `seq` atomically and seeds the prompt's kbite list
from the session's active kbites.

---

## Phase 1: Initial Briefing (doper)

Kbites are **inherited, not auto-detected** — seeded into the prompt row at
create time. Add one only on explicit user request
(`gm kbite add --code C --scope prompt --owner-uuid U`); never on your own.

Context assembly is delegated to the doper — the primary does NOT load
kbite content or dope trees itself:

```bash
gm briefing open --prompt-uuid U --step initial --json     # → briefing uuid
```

```
Task tool:
  subagent_type: gmcc:doper
  prompt: |
    Owner prompt uuid: {U}
    Step: initial
    Topic: {one line — what this prompt is about}
```

The doper searches the dope tree and kbites (full-tree dumps are forbidden)
and completes the `agent_briefing` row. Downstream agents pull it themselves
at spawn — their SubagentStart stub names the exact `gm briefing get`
command. Gate: the spawn's very next tool call is
`gm briefing get --prompt-uuid U --step initial --wait --json`; exit 0 is
the only green light for Phase 2 spawns — no interleaved work of any kind
(hard-stop + dead-doper rules: The Briefing Protocol, `bot_workflows.md`).

Resuming: `gm briefing list --prompt-uuid U` shows what exists; `open` on an
existing (owner, step) RESETS it to building — do that only when the
briefing should be rebuilt.

---

## Phase 2: Explore (explorer agents + reranker)

Open the summary, then spawn one `gmcc:code-explorer` per methodology in a
single parallel batch:

```bash
gm explore open --prompt-uuid U --json     # explicit; works at draft → summary uuid S
```

```
Task tool (4 spawns, one parallel batch):
  subagent_type: gmcc:code-explorer
  prompt: |
    Exploration summary uuid: {S}
    Methodology: {conservative | aggressive | pragmatic | alternative}
    Target: {prompt row's goal + detail, one short paragraph}
```

That is the entire spawn prompt. Each explorer pulls the initial briefing,
explores under its methodology, and writes its own key-file and finding rows
(self-rated, `--agent-name <methodology>`, lowercase). Closing messages are
receipts, not reports.

When all four have returned, spawn the calibration pass:

```
Task tool:
  subagent_type: gmcc:finding-reranker
  prompt: |
    Re-rank the EXPLORATION findings for prompt uuid {U} (summary uuid {S}).
```

The reranker's whole protocol lives in its agent def; it applies one atomic
`gm explore rank` batch and tombstones cross-persona duplicates at 999.

Then the primary completes: `gm explore get --prompt-uuid U --json` (sub-100
findings arrive in full), synthesize, and

```bash
gm explore complete --summary-uuid S --expected-version V \
  (--overview "<your synthesis>" | --overview-file <scratch path>)
```

`complete` refuses unranked findings (if any slipped past the reranker, rank
them yourself); the overview is writable only here. Use the ranked findings
to inform Clarify.

---

## Phase 3: Clarify (db-native)

The db rows ARE the record, `gm clarify get` is the render, `SUMMARY_ABSENT`
means `gm clarify open`. Thread `--expected-version` on every transition (on
`VERSION_CONFLICT`, re-read and retry). `gm prompt set-status` is the ONLY
door that moves the prompt. Full rules: `skills/gmcc/ref/bot_workflows.md`.

1. **Enter clarifying** (locks content; the daemon creates the summary):
   ```bash
   gm prompt set-status --prompt-uuid U --expected-version {v} --status clarifying --json
   gm clarify get --prompt-uuid U --json        # → summary uuid + version
   ```

2. **Goal + detail question suites.** Insert outcome questions (`--category goal`) and approach questions (`--category detail`) via `gm clarify ask`, informed by the ranked exploration findings.

3. **Seal, ask the user, record answers:**
   ```bash
   gm clarify seal   --summary-uuid S --expected-version {sv}
   gm clarify answer --clarification-uuid C --expected-version {cv} --answer "..." --source user|bot_inferred   # or --skip; long answers: --answer-file
   ```

4. **Finalize + advance** (the daemon copies the refined goal into `prompt.goal`; `detail` stays verbatim):
   ```bash
   gm clarify finalize --summary-uuid S --expected-version {sv} \
     --refined-goal "<acceptance criteria>" --refined-detail "<detail + answers + exploration findings, integrated>"
   gm prompt set-status --prompt-uuid U --expected-version {v} --status architecting --json
   ```
   (Long refined text: `--refined-goal-file` / `--refined-detail-file`.)

### Phase 3b: Pre-Architecture Briefing (doper)

Same shape as Phase 1, second step:

```bash
gm briefing open --prompt-uuid U --step pre_architecture --json
```

Spawn `gmcc:doper` (owner prompt uuid, step `pre_architecture`, one-line
topic). It folds in the clarification outcome and exploration overview as
distilled prose + pointers. Same gate: immediately run
`gm briefing get --prompt-uuid U --step pre_architecture --wait --json` —
exit 0 before any Phase 4 spawn.

---

## Phase 4: Plan (architect agents, db-native persistence)

Spawn one `gmcc:code-architect` per methodology in a single parallel batch:

```
Task tool (4 spawns, one parallel batch):
  subagent_type: gmcc:code-architect
  prompt: |
    Prompt uuid: {U}
    Methodology: {conservative | aggressive | pragmatic | alternative}
    Goal: {refined_goal, one line}
```

Architects do NOT write db rows — each pulls the pre_architecture briefing,
grounds itself with `gm clarify get` / `gm explore get` reads, and returns a
proposal as its final message. The architecture rows are the PRIMARY's
synthesis across all four proposals.

Present the synthesized architecture to the user via AskUserQuestion:
```
Architecture design complete. Review the plan:

{brief summary}

How would you like to proceed?
- Approve and implement - Start building
- Modify - I have changes to the architecture
- Reject and redesign - Start architecture over
```

Persist db-natively (entering `architecting` created the summary;
`gm arch get` for its uuid):

1. **Persistence check FIRST (universal):** does the plan touch the persistence layer (schema/ORM classes)? Record those as `gm arch persist-add` + `gm arch field-add` rows — possibly zero — before anything else.
2. `gm arch summarize (--body "<concept-level approach/components/flow/tradeoffs>" | --body-file P)`; then `gm arch general-add` per non-persistence change (`--depth pseudo|draft|actual`, `--code "..."` or `--code-file P` for big blocks). Change rows record implementation changes only (test infra counts; never per-test-case rows).
3. `gm arch propose` → present to the user (AskUserQuestion above) → approved: `gm arch approve`; changes requested: `gm arch revise`, edit rows, re-propose.
4. `gm prompt set-status --prompt-uuid U --expected-version {v} --status implementing --json` (gate: architecture approved). This claims the prompt_activation row for this Claude instance — file-change auto-attribution rides on it.

---

## Phase 5: Implement

1. Follow the approved architecture's build sequence — persistence changes first, always.
2. Make edits with Read/Edit/Write. File-change bookkeeping is **automatic**: the plugin's PostToolUse hook records every Edit/Write via `gm file-change add --auto-attribute` against the activation claim. The residual manual case is repo files changed through Bash (scripts, generators, `git mv`) — record those yourself:
   ```bash
   gm file-change add --path <repo-relative> --kind edit|create|delete|rename --auto-attribute
   ```
3. `gm arch get --prompt-uuid U` at any point shows implementation state per change row, unplanned drift, and the persistence-first audit.

---

## Phase 6: Review (reviewer agents + reranker)

Open the summary, then spawn one `gmcc:code-quality-reviewer` per
methodology in a single parallel batch:

```bash
gm review open --prompt-uuid U --json      # → summary uuid R
```

```
Task tool (4 spawns, one parallel batch):
  subagent_type: gmcc:code-quality-reviewer
  prompt: |
    Review summary uuid: {R}
    Prompt uuid: {U}
    Methodology: {conservative | aggressive | pragmatic | alternative}
    Task: {refined_goal, one line}
```

Reviewers read the actual changes (`gm file-change list --prompt-uuid U`,
`gm arch get`) and write their own `gm review finding-add` rows — self-rated,
file/line-anchored, `--agent-name <methodology>`.

When all four have returned, spawn `gmcc:finding-reranker` with the summary
uuid (same one-line prompt as Phase 2, REVIEW findings).

Then the primary completes with the verdict reflecting the pre-fix state:

```bash
gm review complete --summary-uuid R --expected-version V \
  (--overview "<synthesis>" | --overview-file P) \
  --verdict approved|approved_with_nits|changes_requested
```

Present findings via AskUserQuestion:
```
Code review complete. {summary}

How would you like to handle the findings?
- Fix all issues
- Fix critical only
- Proceed as-is
```

Run the fix loop (back to Phase 5 for the fix subset) — it runs
post-complete by design. Record each outcome:
`gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix`
(address every finding rated under 100).

---

## Phase 7: Feedback Integration

1. Present a complete summary: what was built, files modified, review findings addressed, known limitations.
2. Wait for user feedback. Iterate until satisfied. When done:
   `gm prompt set-status ... --status done` (releases the prompt's activation claim).

There is no phase-history record — completion is prompt status `done` plus
the clarification/architecture/exploration/review rows and file-change trail
(`gm prompt get`, `gm file-change list`).

```
Bot RPI Complete: prompt {seq} ({name})

**Session**: {session ckfs_relative_storage_path from gm session get --json}
**Files Modified**: {count from gm file-change list --prompt-uuid U}
**Review Status**: {verdict from gm review get}

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
Continue the phase in primary context: the primary holds the pen itself
(`/gm_bot` flow — write, self-rate, and rank the rows directly).

**Session paused:**
```
State preserved: prompt row (gm prompt get) + report rows (gm clarify/arch/explore/review get) + briefings (gm briefing list)

To resume: /gm_bot_rpi {seq} <continuation prompt>
```

**Task grows in scope:**
```
This task may benefit from full agent team treatment.

- Continue as /gm_bot_rpi
- Switch to /gm_bot_team
```
