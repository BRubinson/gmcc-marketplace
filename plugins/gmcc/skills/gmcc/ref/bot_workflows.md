# Bot Workflow System Reference (v16.3.0)

Read this file when executing bot workflow commands.

## Workflow Tiers

| Command | Mode | Agents | Use Case |
|---------|------|--------|----------|
| `/gm_bot` | Lightweight | None (primary context) | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | 1 per phase (explore, architect, review) | Medium complexity |
| `/gm_bot_team` | Agent Teams | Teammates per phase (true agent teams) | Complex features, thorough exploration |

## Session + Prompt Model (v16)

All bot workflows operate inside the **current session** — resolved by
`detect_repo.sh` from `$PWD` + active git branch (env: `$GMCC_SESSION_PATH`
for the file home) and registered in the daemon db by `gm context ensure`
at SessionStart. All prompt/session DATA lives on db rows accessed through
the `gm` CLI (see `skills/gmcc_daemon/SKILL.md`); the prompt folder on disk
holds ONLY phase artifacts:

```
$GMCC_SESSION_PATH/prompts/{seq}_{name}/
    memory/
        explore.md                   # exploration report (Phase 2)
        qualified.md                 # clarify output (Phase 3)
        architecture.md              # approved architecture (Phase 4)
        review.md                    # review report (Phase 6)
```

A bot run does NOT create a new session — it adds a new **prompt row** to
the existing session. The canonical lifecycle every tier follows:

1. **State load** — `gm session get --json` (session row + prompt stubs) —
   never read yamls. `gm context ensure` is idempotent and may be re-run if
   the db has no session yet (e.g. daemon was down at SessionStart).
2. **Create** —
   ```bash
   ~/gmcc/bin/gm prompt create --name {name} \
     --detail "<the entire passed prompt, verbatim>" \
     --backstory "<session row's backstory, verbatim>" \
     --command /gm_bot{,_rpi,_team} --json
   ```
   Capture `uuid`, `seq`, and `version` (0 on create) from the JSON.
   STAY TRUE (see Prompt Style). Then
   `mkdir -p "$GMCC_SESSION_PATH/prompts/{seq}_{name}/memory"`.
3. **Explore** — write `memory/explore.md`, then
   `gm artifact add --prompt-uuid U --file-path <abs> --kind explore --note "<one sentence>"`.
4. **Clarify** — while the prompt is still `draft` (content unlocked):
   YEET-type detection, then the two clarification suites; write
   `memory/qualified.md` and register it (`--kind qualified`); then
   ```bash
   gm prompt update-content --prompt-uuid U --expected-version {v} --goal "<refined_goal>" --json   # → v+1
   gm prompt set-status     --prompt-uuid U --expected-version {v+1} --status clarifying --json     # → v+2 (locks content)
   gm prompt set-status     --prompt-uuid U --expected-version {v+2} --status clarified  --json     # → v+3
   ```
   Goal only — `detail` stays the verbatim original; `refined_detail`
   lives in `qualified.md` (the from-Clarify source of truth).
5. **Plan** — after user approval, write `memory/architecture.md` +
   `gm artifact add --kind architecture`.
6. **Implement** — after each Edit/Write to a tracked file:
   ```bash
   gm file-change add --path <repo-relative> --kind edit|create|delete|rename \
     [--range start:end]... [--content "<short note>"] --prompt-uuid U
   ```
7. **Review** — write `memory/review.md` + `gm artifact add --kind review`.
   There is NO phase-history step: completion is represented by status
   `clarified` + registered artifacts (+ `gm file-change list` for the
   change trail).

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
2. If status `clarified`, reads `memory/qualified.md` (+ architecture if
   present) and proceeds to Plan/Implement.
3. If status `clarifying`, re-enters Clarify from where it stalled
   (content is locked — clarify output goes to `qualified.md` only).
4. If status `draft`, proceeds to Phase 2 on the row's verbatim content.
   A bare seq (no continuation) runs an externally-authored draft (e.g.
   from the GMVibes editor) as written. Note: `command` is create-time-only
   in the db (no gm write path) — if the row's `command` is empty, record
   the executing command in `qualified.md`'s header during Clarify instead.
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
| `goal` | **Human input.** The desired outcome / acceptance criteria. Empty (`""`) at create time; filled with `refined_goal` at the end of Clarify (the ONE bot write to content). |
| `detail` | **Human input.** How to accomplish the goal — the passed prompt verbatim, never modified. |

**STAY TRUE — never split, infer, or author `backstory`/`goal`/`detail`.**
When creating a NEW prompt from a passed argument, the entire passed prompt
goes to `--detail` **verbatim**; `goal` is omitted (empty); `backstory` is
the session's, verbatim. Never split a blob into goal vs detail and never
invent an outcome — the Clarify phase fleshes out the goal later via human
Q&A, and the only content write-back is `--goal "<refined_goal>"` before
the status locks.

### Clarify phase — detection first, then split suites

When Clarify begins, the **first** action is **YEET-type detection** over
the prompt row's `goal` + `detail`:

- **Declared** types — named explicitly in the prose (e.g. "a new yeet type for X").
- **Inferred** types — data shapes described structurally without naming a type.

Each detection is resolved confidently (to an existing struct/enum, a new
type to create, or a clear action) or — when it cannot be — the user is
asked via AskUserQuestion to clarify the intended typing behavior. Every
detection is recorded in `qualified.md`'s `detected_yeet_types` section
(with `source:` and `confidence:`).

The bot then runs **two separate clarification suites** — one for `goal`
(outcome/acceptance criteria) and one for `detail` (approach/edge cases).

### `memory/qualified.md` — the clarify artifact

Markdown, registered via `gm artifact add --kind qualified`. Sections:
the through-`backstory` note, `goal_clarifications` / `detail_clarifications`
(Q/A), `refined_goal`, `refined_detail`, `detected_yeet_types`, `key_files`,
`patterns_to_follow`, `constraints` (+ team tier adds per-clarification
`rating` and key-file `consensus`). It is the single source of truth from
Clarify onward; the row's `detail` is never modified.

## KBite Integration

Kbites are **inherited, not auto-detected** — read the prompt's active
list from `gm prompt get` (`kbite_codes`). Kbites are added only on
explicit user request. For each active kbite: read
`$GMCC_KBITE/{name}/KBITE_PURPOSE.md`, get the db overview
(`gm kbite get --code {name}`), rank relevant files (`gm kbite search`),
pull the top files' content (`gm kbite file-get`), compile a kbite
context summary, and pass it to all spawned agents.

## Intermediate Artifacts Persisted to `prompts/{seq}_{name}/memory/`

All three bots persist their per-phase artifacts to the `memory/` subdir
and register each with `gm artifact add` (upsert on
`(prompt_uuid, file_path)`; re-running a phase overwrites the file —
last-run-wins — and refreshes the note):

| File | Kind | Written by | Source |
|------|------|------------|--------|
| `explore.md` | `explore` | Phase 2 | `/gm_bot_rpi`: verbatim subagent report. `/gm_bot_team`: synthesized 4-methodology report (teammate originals are NOT persisted). `/gm_bot`: condensed primary-context exploration notes. |
| `qualified.md` | `qualified` | Phase 3 | All tiers: the clarify artifact (see Prompt Style). |
| `architecture.md` | `architecture` | Phase 4 (after user approval) | `/gm_bot_rpi`: verbatim architect subagent output. `/gm_bot_team`: synthesized unified architecture. `/gm_bot`: the approved plan from EnterPlanMode. |
| `review.md` | `review` | Phase 6 | `/gm_bot_rpi`: verbatim reviewer subagent report. `/gm_bot_team`: synthesized 4-methodology review. `/gm_bot`: a brief primary-context review note. |

These memory files survive across sessions, give the user something to
grep, and provide context if a prompt is resumed days later; the db keeps
the pointer + caption (`gm artifact list`).

## Agent System

Agents are specialized personas defined in `$GMCC_PLUGIN_ROOT/prompts/`:

| Agent | Prompt File | Purpose |
|-------|-------------|---------|
| Code Explorer | `gmcc_agent_code_explorer.prompt.md` | Deep codebase analysis |
| Code Architect | `gmcc_agent_code_architect.prompt.md` | Architecture design |
| Code Reviewer | `gmcc_agent_code_quality_reviewer.prompt.md` | Code review |
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
| `/import_legacy_yaml_gmcc` | Import legacy ckfs yaml prompts into the db (inert until invoked) |
| `/archive_legacy_yaml_gmcc` | Move imported legacy prompt folders to `_archive/cold_storage/` |
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
3. If the ckfs file tree is missing, run `/gm_init` and restart Claude Code so `detect_repo.sh` re-exports the env

If `$GMCC_SESSION_PATH` is missing at command time, the SessionStart hook didn't run. Restart Claude Code.
