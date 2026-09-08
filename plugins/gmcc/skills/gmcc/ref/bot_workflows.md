# Bot Workflow System Reference

Read this file when executing bot workflow commands.

## Workflow Tiers

| Command | Mode | Agents | Use Case |
|---------|------|--------|----------|
| `/gm_bot` | Lightweight | None (primary context) | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | 1 per phase (explore, architect, review) | Medium complexity |
| `/gm_bot_team` | Agent Teams | Teammates per phase (true agent teams) | Complex features, thorough exploration |

## Session + Prompt Model (v16)

All bot workflows operate inside the **current session** — resolved from
`$PWD` + the active git branch and registered in the daemon db by
`gm context ensure` at SessionStart (which also creates the session's
artifact home under `$GMCC_CKFS_ROOT`). All prompt/session DATA lives on db rows accessed through
the `gm` CLI (see `skills/gmcc_daemon/SKILL.md`). Since v19 (m0004) EVERY
bot report is db-native: clarification (`gm clarify`), architecture
(`gm arch`), exploration (`gm explore`), and review (`gm review`). The
prompt folder on disk still exists —

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
   Capture `uuid`, `seq`, `version` (0 on create), and
   `ckfs_relative_storage_path` from the JSON. STAY TRUE (see Prompt Style).
   Then mkdir the memory dir at the RETURNED storage path (relative to
   `gm paths` → ckfs_root) — the daemon slugs the name and the memory
   watcher matches the stored path by exact case-sensitive equality, so
   NEVER re-derive `{seq}_{name}` yourself.
3. **Explore (db-native)** — `gm explore open --prompt-uuid U` (explicit
   only; the prompt is still `draft` here and never auto-creates one), then
   per discovery: `gm explore key-file-add` (deduped set) and
   `gm explore finding-add --kind ... --title ... --body ... --agent-name
   ...` (rating optional at insert). Rank before handoff:
   `gm explore rank --summary-uuid S --rating <uuid>:<0-999> ...` (atomic
   batch; 0 = critical … 999 = tombstone, read threshold 100). Finally
   `gm explore complete --overview "<narrative>"` — complete REFUSES while
   any finding is unranked, and the overview is writable ONLY here (the
   primary agent writes it after reading the ranked findings). Re-runs:
   `gm explore reopen` → update → re-complete (last-run-wins).
4. **Clarify (db-native)** — `gm prompt set-status ... --status clarifying`
   (locks content; the daemon creates the clarification summary), then:
   the goal + detail question suites → `gm clarify ask --category
   goal|detail`; `gm clarify seal`;
   AskUserQuestion → `gm clarify answer` (or `--skip`); finally
   `gm clarify finalize --refined-goal "<acceptance criteria>"
   --refined-detail "<detail + answers integrated>"` — the daemon copies the
   refined goal into `prompt.goal` (`detail` stays the verbatim original) —
   then `gm prompt set-status ... --status architecting` (gate: summary
   complete). Wrong answer later: `gm clarify reopen` → re-answer →
   re-finalize.
5. **Plan (db-native)** — entering `architecting` created the architecture
   summary. Persistence check FIRST (does the plan touch schema/ORM classes?
   record `gm arch persist-add` + `field-add` rows, possibly zero), then
   `gm arch summarize --body "<concept-level>"` + `gm arch general-add` per
   non-persistence change; `gm arch propose` → user approval →
   `gm arch approve` (or `revise`) → `gm prompt set-status ... --status
   implementing` (gate: architecture approved).
6. **Implement** — persistence changes FIRST, always. After each Edit/Write
   to a tracked file (**always with `--prompt-uuid`** — the `gm arch get`
   comparison sees only attributed changes):
   ```bash
   gm file-change add --path <repo-relative> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```
   `--content` requires EXACTLY ONE `--range` (the daemon rejects the pair
   otherwise); omit both to record the file as touched without line detail.
   `gm arch get` shows per-row implementation state, unplanned drift, and
   the persistence-first audit at any point.
7. **Review (db-native)** — `gm prompt set-status ... --status reviewing`
   (or skip `implementing → done` directly — prompt status never creates or
   gates the review summary). `gm review open --prompt-uuid U`, then
   `gm review finding-add` per finding (kind/title/body, optional
   --file-path/--line-start/--line-end, --agent-name), `gm review rank`
   (same batch contract as explore), and `gm review complete --overview
   "<narrative>" --verdict approved|approved_with_nits|changes_requested`
   (refuses unranked findings; overview + verdict writable ONLY here). The
   fix loop then records outcomes per finding — `gm review resolve
   --finding-uuid F --status fixed|accepted|wont_fix` — which works AFTER
   complete by design; every finding under rating 100 gets a resolution.
   Finish with `--status done`. There is NO phase-history step: completion
   is status `done` + the clarification/architecture/exploration/review
   rows (+ `gm file-change list` for the change trail).

### `--expected-version` threading (every mutation)

`update-content` / `set-status` / `session update` are guarded by
optimistic concurrency. Always capture `.version` from the `--json` of the
previous `create`/`get`/mutation and pass it as `--expected-version`. On
`VERSION_CONFLICT`, re-run `gm prompt get` and retry with the fresh
version. Transitions are forward-only (`INVALID_TRANSITION`), content
edits draft-only (`CONTENT_LOCKED`).

### Resume Logic

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
   Review; `done` → complete (new work = new prompt).
3. `SUMMARY_ABSENT` means the prompt exists but that summary was never
   opened — open it (`gm clarify/arch/explore/review open`). It is never a
   signal to go read a file.
4. A bare seq (no continuation) runs an externally-authored draft (e.g.
   from the GMVibes editor) as written. `command` is create-time-only in
   the db — if the row's `command` is empty, record the executing tier in
   the clarification's `--backstory-note`.
5. If seq not found, errors.

### New-Prompt Mode

If the first argument is non-numeric, it's treated as a slug name for a new prompt:

```
/gm_bot auth-refactor implement OAuth2 flow
         ^name         ^prompt content
```

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

The bot then runs **two separate clarification suites** — one for `goal`
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

## KBite Integration

Kbites are **inherited, not auto-detected** — read the prompt's active
list from `gm prompt get` (`kbite_codes`). Kbites are added only on
explicit user request. For each active kbite: read
`{kbite_root}/{name}/KBITE_PURPOSE.md` (root from `gm paths --json`), get
the db overview (`gm kbite get --code {name}`), then `gm kbite search`
(bm25 relevance-ordered; `--code` scopes to one kbite). Read the
`file_summary` brief on every hit and pull the full content of every file
whose brief is relevant (`gm kbite file-get`) — typically 5-10 files, not
a fixed top-N cap. Compile a kbite context summary and pass it to all
spawned agents.

## DOPE Dump Injection (explore agents)

**DOPE = Domain Optimized Project Essence** — the session's domain model
and always the PERSISTENCE LAYER's source of truth. Boot seeds it from the
repo's `.gmcc` tree (`gm context ensure` / `gm dope sync`), so it is
populated from the first prompt of a fresh branch.

Before spawning explore agents, every tier runs
`gm dope list --session-uuid U`. If the session carries a SESSION_INSTANCE
scope, fetch the tree (`gm dope get --session-uuid U --json`) and
**force-inject** it into EVERY explore spawn as a `## Domain Model (DOPE)`
block, exactly like the kbite context summary — explorers do not choose
whether to load it. Architect agents get the *command*
(`gm dope get --session-uuid U --json`), not the dump, and load on demand.
An architecture proposing new persistence is proposing dope changes — say
so in the block. No scope → note "no dope scope" and move on; never init
one for this purpose.

Caveat for the coming UI-doping flow: dope trees will become mutable
mid-prompt (user edits in GMVibes), so re-fetch per phase rather than
caching one dump across phases — and future UI-focused doping may need a
more careful, view-scoped dump for UI-based tasks.

## GM Cheatsheet (state load)

The exact gm verb surface is in context from SessionStart: `gmcc_session_startup.sh`
prints `gm cheatsheet` (one signature line per verb + invariants, compiled
into the binary so it cannot drift from installed capabilities). Consult it
instead of `gm ... --help` roundtrips. Subagent tiers must paste the verbatim
`gm cheatsheet` output into every worker/teammate prompt — spawned agents do
not inherit SessionStart context.

## Report Records (all db-native since v19/m0004)

Every phase record is db rows, searchable via `gm search`, rendered by its
`get` verb:

| Record | Verbs | Rows |
|--------|-------|------|
| Clarification | `gm clarify ...` | summary (refined goal/detail/backstory note) + Q/A rows |
| Architecture | `gm arch ...` | summary body + persistence/field/general change rows |
| Exploration | `gm explore ...` | summary overview + key-file set + rated findings |
| Review | `gm review ...` | summary overview/verdict + rated findings with resolutions |

**Who holds the pen per tier** (exploration/review): `/gm_bot_team`
teammates are full sessions — they run the finding/key-file verbs
themselves, self-reporting their persona as `--agent-name`, and team mode
adds a re-rank pass (`gmcc_agent_finding_reranker.prompt.md`, opus) before
the primary reads and completes. `/gm_bot` and `/gm_bot_rpi` subagents
return finding-shaped reports as text and the PRIMARY transcribes them into
rows. In every tier the primary alone writes the overview (and review
verdict) via `complete`, after ranking.

**finding_rating (0–999)**: 0 = absolute critical, 999 = always-false-
positive tombstone; the read threshold is 100 (gets return full rows under
it — plus every unranked row — and stubs above; exactly one of `--full` /
`--max-rating N` / `--rating-range A:B` widens the window). Re-runs
supersede by re-ranking (999 tombstones), never deletion.

## Agent System

Agents are specialized personas defined in `$GMCC_PLUGIN_ROOT/prompts/`:

| Agent | Prompt File | Purpose |
|-------|-------------|---------|
| Code Explorer | `gmcc_agent_code_explorer.prompt.md` | Deep codebase analysis |
| Code Architect | `gmcc_agent_code_architect.prompt.md` | Architecture design |
| Code Reviewer | `gmcc_agent_code_quality_reviewer.prompt.md` | Code review |
| Finding Re-Ranker | `gmcc_agent_finding_reranker.prompt.md` | Team-mode batch re-rank of exploration/review findings (opus) |
| KBite Chew | `gmcc_agent_kbite_crunch_chew.prompt.md` | Analyze crunchables |

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_init` | Initialize GM-CDE system (creates `~/gmcc_ckfs/`, builds the daemon, `gm setup`) |
| `/gm_bot` | Lightweight bot workflow (primary context) |
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
