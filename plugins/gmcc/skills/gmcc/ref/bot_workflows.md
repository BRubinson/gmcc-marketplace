# Bot Workflow System Reference

**The single canonical lifecycle document.** Every tier command
(`/gm_bot`, `/gm_bot_rpi`, `/gm_bot_team`) holds ONLY its tier delta —
spawn mechanics and orchestration — and points here for everything
shared. Where a tier doc and this file disagree, this file wins.

## Workflow Tiers

| Command | Mode | Agent fan-out | Use Case |
|---------|------|---------------|----------|
| `/gm_bot` | Lightweight | Minimal — gmcc agents spawned per phase as needed | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | One gmcc agent per phase (Task tool) | Medium complexity |
| `/gm_bot_team` | Agent Teams | 4 teammates per phase, one per methodology | Complex features, thorough exploration |

The lifecycle, the pen contract, and the record shapes are IDENTICAL in
every tier — tiers differ only in how many agents run a phase and how
they are spawned.

## Session + Prompt Model (v16)

All bot workflows operate inside the **current session** — resolved from
`$PWD` + the active git branch and registered in the daemon db by
`gm context ensure` at SessionStart (which also creates the session's
artifact home under `$GMCC_CKFS_ROOT`). All prompt/session DATA lives on
db rows accessed through the `gm` CLI (see `skills/gmcc_daemon/SKILL.md`).
EVERY bot report is db-native: clarification (`gm clarify`), architecture
(`gm arch`), exploration (`gm explore`), review (`gm review`), and the
phase briefings (`gm briefing`). The prompt folder on disk still exists —

```
$GMCC_CKFS_ROOT/{session ckfs_relative_storage_path}/prompts/{seq}_{name}/
    memory/                          # usually EMPTY now — reports live in the db
```

— the mkdir step stays (it is where any prompt-scoped scratch file lands),
but a normal run writes no memory files at all.

A bot run does NOT create a new session — it adds a new **prompt row** to
the existing session. The canonical lifecycle every tier follows:

1. **State load** — `gm session get --json` (session row + prompt stubs) —
   never read yamls. For cross-prompt context use
   `gm prompt list --with-reports --json` (one call: every prompt's
   clarification/architecture stub) and `gm search "<topic>" --json` — never
   glob/head/cat `memory/*.md` files for context. `gm context ensure` is
   idempotent and may be re-run if the db has no session yet (e.g. daemon
   was down at SessionStart).
2. **Create** —
   ```bash
   gm prompt create --name {name} \
     --detail "<the entire passed prompt, verbatim>" \
     --backstory "<session row's backstory, verbatim>" \
     --command /gm_bot{,_rpi,_team} --json
   ```
   (`--detail-file` for long content — prefer the file-input flags over
   giant argv everywhere they exist.) Capture `uuid`, `seq`, `version`
   (0 on create), and `ckfs_relative_storage_path` from the JSON. STAY
   TRUE (see Prompt Style). Then mkdir the memory dir at the RETURNED
   storage path (relative to `gm paths` → ckfs_root) — the daemon slugs
   the name and the memory watcher matches the stored path by exact
   case-sensitive equality, so NEVER re-derive `{seq}_{name}` yourself.
3. **Brief** — `gm briefing open --prompt-uuid U --step initial --json`,
   then spawn `gmcc:doper` to fill it (see The Briefing Protocol). Wait
   for it before spawning explorers.
4. **Explore (agents hold the pen)** — `gm explore open --prompt-uuid U`
   (explicit only; the prompt is still `draft` here and never
   auto-creates one), then spawn `gmcc:code-explorer` agent(s) — the tier
   decides how many — passing ONLY the summary uuid, the methodology
   name, and the exploration target. The agents pull their briefing,
   write `gm explore key-file-add` / `finding-add` rows themselves with
   `--agent-name <methodology>` and self-ratings, and return short
   receipts. Then spawn `gmcc:finding-reranker` with the summary uuid for
   the one calibrated `gm explore rank` batch. Finally the primary reads
   the ranked record (`gm explore get`) and seals it:
   `gm explore complete --overview "<narrative>"` — complete REFUSES
   while any finding is unranked, and the overview is writable ONLY here.
   Re-runs: `gm explore reopen` → update → re-complete (last-run-wins).
5. **Clarify (db-native)** — `gm prompt set-status ... --status clarifying`
   (locks content; the daemon creates the clarification summary), then:
   the goal + detail question suites → `gm clarify ask --category
   goal|detail`; `gm clarify seal`;
   AskUserQuestion → `gm clarify answer` (or `--skip`); finally
   `gm clarify finalize --refined-goal "<acceptance criteria>"
   --refined-detail "<detail + answers integrated>"` — the daemon copies the
   refined goal into `prompt.goal` (`detail` stays the verbatim original) —
   then `gm prompt set-status ... --status architecting` (gate: summary
   complete). Wrong answer later: `gm clarify reopen` → re-answer →
   re-finalize. After finalize, brief again:
   `gm briefing open --prompt-uuid U --step pre_architecture` + a fresh
   `gmcc:doper` spawn.
6. **Plan (db-native)** — entering `architecting` created the architecture
   summary. Spawn `gmcc:code-architect` agent(s) (proposal-only — they do
   NOT write rows; their final message is the deliverable). The primary
   synthesizes, then persists: persistence check FIRST (does the plan
   touch schema/ORM classes? record `gm arch persist-add` + `field-add`
   rows, possibly zero), then `gm arch summarize --body-file <path>` +
   `gm arch general-add` per non-persistence change (`--code-file` for
   real code); `gm arch propose` → user approval → `gm arch approve` (or
   `revise`) → `gm prompt set-status ... --status implementing` (gate:
   architecture approved). This transition also claims the prompt for
   this Claude instance (see Activation Registry).
7. **Implement** — persistence changes FIRST, always. Edit/Write file
   changes are recorded AUTOMATICALLY by the plugin's PostToolUse hook
   (`gm file-change add --auto-attribute`, resolved through the
   activation registry) — no manual bookkeeping per edit. The residual
   manual case is Bash-driven writes (git mv, codegen, heredocs): record
   those yourself with `gm file-change add --path <repo-relative>
   --kind edit|create|delete|rename --prompt-uuid U`. `gm arch get`
   shows per-row implementation state, unplanned drift, and the
   persistence-first audit at any point — it sees only attributed
   changes.
8. **Review (agents hold the pen)** — `gm prompt set-status ... --status
   reviewing` (or skip `implementing → done` directly — prompt status
   never creates or gates the review summary). `gm review open
   --prompt-uuid U`, spawn `gmcc:code-quality-reviewer` agent(s) with the
   summary uuid + methodology — they write `gm review finding-add` rows
   themselves — then `gmcc:finding-reranker` with the summary uuid, then
   the primary completes: `gm review complete --overview "<narrative>"
   --verdict approved|approved_with_nits|changes_requested` (refuses
   unranked findings; overview + verdict writable ONLY here). The fix
   loop then records outcomes per finding — `gm review resolve
   --finding-uuid F --status fixed|accepted|wont_fix` — which works AFTER
   complete by design; every finding under rating 100 gets a resolution.
   Finish with `--status done` (releases the activation claim). There is
   NO phase-history step: completion is status `done` + the
   clarification/architecture/exploration/review rows (+
   `gm file-change list` for the change trail).

### `--expected-version` threading (every mutation)

Mutations are guarded by optimistic concurrency. Always capture
`.version` from the `--json` of the previous `create`/`get`/mutation and
pass it as `--expected-version`. On `VERSION_CONFLICT`, re-run the
matching `get`, take the fresh `.version`, retry. Transitions are
forward-only (`INVALID_TRANSITION`), content edits draft-only
(`CONTENT_LOCKED`).

`SUMMARY_ABSENT` means the target exists but that summary was never
opened — open it (`gm clarify/arch/explore/review/briefing open`; for
dope, `gm dope init`). It is never a signal to go read a file.

## Activation Registry

`gm prompt set-status --status implementing` claims a
**prompt_activation row for the CALLING Claude instance** (client key
resolved from process ancestry by gm automatically); `--status done`
releases the prompt's claim. This is a registry, NOT a session-wide
pointer: several prompts stay active on one session concurrently (one
per Claude instance). Manual override:
`gm session update --active-prompt-uuid U | --clear-active-prompt`.

Two resolvers walk the registry the same way — the caller's own claim →
the session's single claim → nothing (briefing resolution additionally
falls through to the session's task row):

- `gm file-change add --auto-attribute` (the PostToolUse hook's flag)
- `gm briefing get --step S` (the zero-uuid deterministic form)

## The Briefing Protocol (doper)

Briefings replace hand-assembled context injection. The db entity is
`agent_briefing`, one per (owner, step), steps `initial` and
`pre_architecture`; states `building → ready`.

1. **Primary opens**: `gm briefing open --prompt-uuid U --step S --json`
   (`--session-uuid` alone for a `/gm_task`-owned briefing). Open on an
   existing (owner, step) RESETS it to `building` — a step's briefing is
   always its CURRENT briefing, so re-open per phase. A prompt-owned open
   ALSO claims the activation for the calling Claude instance — briefings
   are consumed in the draft/architecting phases, long before set-status
   implementing would claim, and the claim is what makes every downstream
   zero-uuid pull deterministic.
2. **Primary spawns `gmcc:doper`** with a spawn prompt of exactly: the
   owner uuid, the step, and a one-line topic. The doper's whole protocol
   lives in its agent def: it SEARCHES (`gm dope search`, targeted
   `gm dope get --code`, `gm kbite search` → `file-get`) — full-tree
   dumps are FORBIDDEN — and completes the briefing
   (`gm briefing complete ... --body-file P [--dope-ref DOT.PATH]...
   [--kbite-ref FILE_UUID]...`; the daemon stamps the dope revision and
   denormalizes kbite briefs).
3. **Downstream agents pull**: every `gmcc:*` agent spawn gets a
   SubagentStart hook stub naming the exact pull command; the agent runs
   `gm briefing get --step S` — the zero-uuid form resolves
   deterministically (session from cwd, Claude instance from process
   ancestry, own activation claim → single session claim → task row).
   Spawn templates do NOT carry kbite summaries, dope dumps, or
   cheatsheets — ever. Two scoping exceptions: TEAMMATES are separate
   Claude processes holding no claim, so their spawn line uses the
   explicit `gm briefing get --prompt-uuid U --step S` form; and the
   PRIMARY pulls its own task briefings by `--briefing-uuid` (it printed
   the uuid at open, and its lingering prompt claim would shadow the
   zero-uuid task fallback).
4. **Staleness is computed at read**, never at write: `gm briefing get`
   reports revision drift and ghost dot-paths as warnings (never blocks).
   Dope trees are mutable mid-prompt (GMVibes edits), which is exactly
   why briefings are re-opened per phase instead of cached across phases.

## DOPE — search-first

**DOPE = Domain Optimized Project Essence** — the session's domain model
and always the PERSISTENCE LAYER's source of truth. Boot seeds it from
the repo's `.gmcc` tree (`gm context ensure` / `gm dope sync`), so it is
populated from the first prompt of a fresh branch.

Nothing force-injects dope anymore. The doper distills what the phase
needs into the briefing (with `--dope-ref` dot-paths); any agent that
needs more searches on demand: `gm dope search session "<query>"` (FTS5,
hits carry the dot-path) + targeted `gm dope get --code <scope>`.
Full-tree `gm dope get` dumps into prompts or briefings are forbidden.
An architecture proposing new persistence is proposing dope changes —
architects must say so. No dope scope on the session → normal; never
init one for briefing purposes.

## KBites

Kbites are **inherited, not auto-detected** — the prompt's active list is
`kbite_codes` on `gm prompt get`; kbites are added only on explicit user
request (`gm kbite add`). Discovery is search-first and flows through the
briefing: the doper runs `gm kbite search` (bm25; `--code` scopes; read
the `file_summary` brief on every hit) and `gm kbite file-get` on the
5-10 genuinely relevant files, then cites them as `--kbite-ref` rows.
Agents needing more depth run the same two verbs themselves.

## GM Cheatsheet (two-tier)

SessionStart injects the COMPACT CORE (`gm cheatsheet`): family index +
agent pen verbs + invariants, ~5KB, compiled into the binary. It is NOT
the full surface — exact signatures for every verb are
`gm cheatsheet --full`. Consult the sheet instead of `gm ... --help`
roundtrips; never guess flags. Spawned `gmcc:*` agents receive the core
automatically via the SubagentStart hook, and teammates are full sessions
(SessionStart feeds them) — never paste cheatsheets into spawn prompts.

## Prompt Style

Prompt content is the `backstory`/`goal`/`detail` triple on the prompt row.

| Field | Meaning |
|-------|---------|
| `backstory` | **Human input.** Inherited verbatim from the session row's `backstory` at create time (empty `""` unless set). May diverge per prompt. |
| `goal` | **Human input.** The desired outcome / acceptance criteria. Empty (`""`) at create time; `gm clarify finalize` copies the refined goal into it daemon-side (the ONE content write past draft). |
| `detail` | **Human input.** How to accomplish the goal — the passed prompt verbatim, never modified. |

**STAY TRUE — never split, infer, or author `backstory`/`goal`/`detail`.**
When creating a NEW prompt from a passed argument, the entire passed prompt
goes to `--detail` **verbatim**; `goal` is omitted (empty); `backstory` is
the session's, verbatim. Never split a blob into goal vs detail and never
invent an outcome — the Clarify phase fleshes out the goal later via human
Q&A, and the only content write past draft is the daemon-side refined-goal
copy performed by `gm clarify finalize`.

### Clarify phase — split suites

The bot runs **two separate clarification suites** — one for `goal`
(outcome/acceptance criteria, `--category goal`) and one for `detail`
(approach/edge cases, `--category detail`).

### The clarification rows — the clarify record

Db-native (`gm clarify get` renders it): one row per Q/A with category,
status (open/answered/skipped), and answer source (user/bot_inferred); the
summary carries `refined_goal` (acceptance criteria) and `refined_detail`
(detail + answers integrated — the from-Clarify source of truth) plus a
`backstory_note` (executing tier, team-consensus notes). The row's `detail`
is never modified. **Never mirror a report to a file**: no qualified.md, no
architecture.md, no "grep-ability" duplicates — the db rows ARE the record
and `gm search` is the search surface.

## Who Holds the Pen

**Agents hold the pen in EVERY tier.** Spawned `gmcc:code-explorer` /
`gmcc:code-quality-reviewer` agents (Task subagents and teammates alike)
write their finding/key-file rows directly — `--agent-name` is the
lowercase methodology (conservative/aggressive/pragmatic/alternative;
the daemon normalizes to lowercase at write) — with self-ratings, and
close with a short receipt, never a report. The full pen contract,
methodology modes, and rating rules live IN the agent defs
(`plugins/gmcc/agents/`); spawn prompts carry ONLY task-specific content
(uuids, methodology, goal/topic).

The primary keeps exactly four things: **rank** (delegated to one
`gmcc:finding-reranker` spawn per summary — its def carries the whole
protocol), **complete/overview**, **verdict** (review), and **resolve**
(the fix loop). `gmcc:code-architect` is the exception that proves the
rule: proposal-only, no db rows — architecture rows are the primary's
cross-methodology synthesis.

**finding_rating (0–999)**: 0 = absolute critical, 999 = always-false-
positive tombstone; the read threshold is 100 (gets return full rows under
it — plus every unranked row — and stubs above; exactly one of `--full` /
`--max-rating N` / `--rating-range A:B` widens the window). Re-runs
supersede by re-ranking (999 tombstones), never deletion.

## Agent System

Native plugin agents in `plugins/gmcc/agents/` — spawn via
`subagent_type: "gmcc:<name>"`. Each def carries its own contract; the
SubagentStart hook provisions cheatsheet core + briefing stub.

| Agent | Pen | Purpose |
|-------|-----|---------|
| `gmcc:code-explorer` | writes explore rows | Deep codebase analysis |
| `gmcc:code-architect` | proposal-only | Architecture design |
| `gmcc:code-quality-reviewer` | writes review rows | Code review |
| `gmcc:finding-reranker` | rank batch only | Calibrated 0-999 re-rank of one summary |
| `gmcc:doper` | writes the briefing | Search-first context acquisition |

## Resume Logic

To resume an in-progress prompt, invoke with the prompt seq as the first argument:

```
/gm_bot 3 continue with the login endpoint
         ^prompt seq  ^continuation
```

The bot:
1. `gm prompt list --json`, finds the stub with `seq: 3`, then
   `gm prompt get --prompt-uuid U --json` for full content + artifacts.
2. Resumes by status (lifecycle v2): `draft` → Explore; `clarifying` →
   Clarify (`gm clarify get` shows the summary state + open questions);
   `architecting` → Plan (`gm arch get`); `implementing` → Implement
   (`gm arch get` is the plan + implementation state); `reviewing` →
   Review; `done` → complete (new work = new prompt). On resume, re-open
   the phase's briefing (open RESETS — staleness is computed at read
   anyway) before spawning agents.
3. A bare seq (no continuation) runs an externally-authored draft (e.g.
   from the GMVibes editor) as written. `command` is create-time-only in
   the db — if the row's `command` is empty, record the executing tier in
   the clarification's `--backstory-note`.
4. If seq not found, errors.

### New-Prompt Mode

If the first argument is non-numeric, it's treated as a slug name for a new prompt:

```
/gm_bot auth-refactor implement OAuth2 flow
         ^name         ^prompt content
```

## Report Records (all db-native)

Every phase record is db rows, searchable via `gm search`, rendered by its
`get` verb:

| Record | Verbs | Rows |
|--------|-------|------|
| Clarification | `gm clarify ...` | summary (refined goal/detail/backstory note) + Q/A rows |
| Architecture | `gm arch ...` | summary body + persistence/field/general change rows |
| Exploration | `gm explore ...` | summary overview + key-file set + rated findings |
| Review | `gm review ...` | summary overview/verdict + rated findings with resolutions |
| Briefing | `gm briefing ...` | per-(owner, step) body + dope/kbite refs (not a report — phase input) |

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_init` | Initialize GM-CDE system (creates `~/gmcc_ckfs/`, builds the daemon, `gm setup`) |
| `/gm_bot` | Lightweight bot workflow |
| `/gm_bot_rpi` | Subagent Research/Plan/Implement workflow |
| `/gm_bot_team` | Agent team workflow (requires agent teams enabled) |
| `/gm_task` | Load session context (via gm reads) and just do the task; read-only — no db writes unless you explicitly ask for a retroactive write-back |
| `/gmcc_daemon` | Daemon build/status/lifecycle |
| `/gmcc_environment_cleanup` | Audit the environment (db-vs-disk drift, daemon health, archive hygiene), interactively resolve |
| `/gmcc_session_cleanup` | Audit only the current session: memory/ folders vs db rows, artifact + file-change drift |
| `/gm_crunch_open_maw` | Create maw for collecting kbite crunchables |
| `/gm_crunch_chew` | Process crunchables into analyzed knowledge |
| `/gm_crunch_digest` | Finalize kbite from chewed resources |
| `/gm_kbite_relate` | Define relationship between kbites |

## Error Recovery

If the daemon/db is unreachable (`gm` exit code 2):
1. `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` (self-heal rule in `skills/gmcc_daemon/SKILL.md`)
2. Re-run `gm context ensure`
3. If the ckfs file tree is missing, run `/gm_init` and restart Claude Code so the SessionStart boot re-runs (env re-emitted via `gm context env`)

If `$GMCC_BOOTED` is unset at command time, the SessionStart hook didn't run. Restart Claude Code.
