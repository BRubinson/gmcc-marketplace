# Bot Workflow System Reference (v13.0.0)

Read this file when executing bot workflow commands.

## Workflow Tiers

| Command | Mode | Agents | Use Case |
|---------|------|--------|----------|
| `/gm_bot` | Lightweight | None (primary context) | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | 1 per phase (explore, architect, review) | Medium complexity |
| `/gm_bot_team` | Agent Teams | Teammates per phase (true agent teams) | Complex features, thorough exploration |

## Session + Prompt Model (v10.0.0)

All bot workflows operate inside the **current session** — automatically resolved by `detect_repo.sh` from `$PWD` + active git branch, exported as `$GMCC_SESSION_PATH`.

A bot run does NOT create a new session — it adds a new **prompt** to the existing session. Each prompt is a FOLDER under `$GMCC_SESSION_PATH/prompts/`:

```
$GMCC_SESSION_PATH/prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index/status, version: 3)
    {id}_{name}_initial.yaml        # gmcc_initial_prompt_file: detail (verbatim) + empty goal/backstory + kbite context
    {id}_{name}_clarified.yaml      # gmcc_clarified_prompt_file (absent until Clarified)
    memory/
        explore.md                   # exploration report (Phase 2)
        architecture.md              # approved architecture (Phase 4)
        review.md                    # review report (Phase 6)
```

Both content files keep the `.yaml` suffix but carry `yeet:` + `yeet_type:`
headers (v11.0.0) so `/gm_compile` validates them. See the Prompt Style section
below.

1. On invocation, the bot reads `$GMCC_SESSION_PATH/session_data.gmcc.yaml`.
2. It picks the next prompt id (max existing id + 1, or 1 if none).
3. It creates `prompts/{id}_{name}/` with the `memory/` subdir, writes `{id}_{name}_data.gmcc.yaml` (conforms to `gmcc_prompt_data_file`, `version: 3`, `prompt_status: Draft`, kbite seeded from `session_data.kbite`) and `{id}_{name}_initial.yaml` (conforms to `gmcc_initial_prompt_file`; the passed prompt is written **verbatim** to `detail`, `goal` left empty `""`, `backstory` inherited verbatim from `session_data.backstory` — all three are human-input only, never split or authored).
4. It appends a lightweight stub to `session_data.gmcc.yaml`'s `prompts:` list (conforms to `gmcc_session_data_file_prompt_files_entry`): `id`, `name`, `status: Draft`, `path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml`.
5. The Clarify phase flips `prompt_status` to `Clarifying`. Its **first** step is YEET-type detection over the initial prompt (see Prompt Style below); it then runs **separate** goal and detail clarification suites, and on completion writes `{id}_{name}_clarified.yaml` (conforms to `gmcc_clarified_prompt_file`), sets `clarified_prompt_path`, flips `prompt_status` to `Clarified`, and updates the session_data stub.
6. Implementation runs. Each file edit appends to `session_data.gmcc.yaml`'s `changed_files:` list (conforms to `gmcc_session_data_file_changed_files_entry`): `file`, `timestamp`, `lines`, `commit`, `note`.

### Resume Logic

To resume an in-progress prompt, invoke with the prompt id as the first argument:

```
/gm_bot 3 continue with the login endpoint
         ^prompt id  ^continuation
```

The bot:
1. Reads `session_data.gmcc.yaml`, finds the stub with `id: 3`, follows `path:` to read `{id}_{name}_data.gmcc.yaml`.
2. If `prompt_status: Clarified`, reads the clarified file and proceeds to Plan/Implement.
3. If `prompt_status: Clarifying`, re-enters Clarify from where it stalled.
4. If `prompt_status: Draft`, reads the initial file and proceeds to Phase 2.
5. If id not found, errors.

### New-Prompt Mode

If the first argument is non-numeric, it's treated as a slug name for a new prompt:

```
/gm_bot auth-refactor implement OAuth2 flow
         ^name         ^prompt content
```

## Prompt Style (v11.0.0)

Prompt content is split into named components across two typed files. Both keep
the `.yaml` suffix and carry `yeet:` + `yeet_type:` headers for `/gm_compile`.

### Initial file — `gmcc_initial_prompt_file`

| Field | Meaning |
|-------|---------|
| `backstory` | **Human input.** Inherited verbatim from the session's `backstory:` at draft-create time (empty `""` unless a session backstory was set). May diverge per prompt. A future editor lets humans write it. |
| `goal` | **Human input.** The generally desired outcome / acceptance criteria. Left empty (`""`) at create time. |
| `detail` | **Human input.** How to accomplish the goal — the specifics. |
| `kbites_loaded` (+ `kbite_context_summary?`) | KBites loaded in Phase 1; summary is subagent/team-only. |

**STAY TRUE — never split, infer, or author `backstory`/`goal`/`detail`.** These
three are human-authored only (an editor is coming). When creating a NEW prompt
from a passed argument, the entire passed prompt is assumed to be `detail` and is
written there **verbatim**; `goal` is left empty (`""`); `backstory` is inherited
from the session (`""` if unset). Never split a blob into goal vs detail and never
invent an outcome — the Clarify phase fleshes out the goal later via human Q&A.

### Clarify phase — detection first, then split suites

When `prompt_status` moves to `Clarifying`, the **first** action is **YEET-type
detection** over the initial prompt's `goal` + `detail`:

- **Declared** types — named explicitly in the prose (e.g. "a new yeet type for X").
- **Inferred** types — data shapes described structurally without naming a type.

Each detection is resolved confidently (to an existing struct/enum, a new type to
create, or a clear action) or — when it cannot be — the user is asked via
AskUserQuestion to clarify the intended typing behavior. Every detection is
recorded in the clarified file's `detected_yeet_types` (with `source:` and
`confidence:`).

The bot then runs **two separate clarification suites** — one for `goal`
(outcome/acceptance criteria) and one for `detail` (approach/edge cases) —
recorded under `goal_clarifications` and `detail_clarifications`.

### Clarified file — `gmcc_clarified_prompt_file`

Carries the through-`backstory`, the two clarification suites, `refined_goal` /
`refined_detail`, `detected_yeet_types`, `key_files`, `constraints`,
`kbites_loaded` (+ `patterns_to_follow` for subagent/team tiers; team adds
per-clarification `rating` and `key_files[].consensus`). It is the single source
of truth from Clarify onward; the initial file is never modified.

## KBite Integration

All bot workflows load kbites during initialization:
1. List available kbites from `$GMCC_KBITE_DIGESTED/`
2. For each, read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` for the one-line summary
3. Ask user to select relevant kbites
4. Load chewed files for selected kbites
5. Pass kbite context to all spawned agents

## Intermediate Artifacts Persisted to `prompts/{id}_{name}/memory/` (v10.0.0)

v10.0.0 **reverses** the earlier v6.0.0 "no persistence" policy. All three bots persist their per-phase artifacts to a `memory/` subdirectory inside the prompt folder:

| File | Written by | Source |
|------|------------|--------|
| `explore.md` | Phase 2 | `/gm_bot_rpi`: verbatim subagent report. `/gm_bot_team`: synthesized 4-methodology report (teammate originals are NOT persisted). `/gm_bot`: condensed primary-context exploration notes. |
| `architecture.md` | Phase 4 (after user approval) | `/gm_bot_rpi`: verbatim architect subagent output. `/gm_bot_team`: synthesized unified architecture (teammate originals are NOT persisted). `/gm_bot`: the approved plan from EnterPlanMode. |
| `review.md` | Phase 6 | `/gm_bot_rpi`: verbatim reviewer subagent report. `/gm_bot_team`: synthesized 4-methodology review. `/gm_bot`: a brief primary-context review note covering what was built, deferred, and known limitations. |

Re-running a phase overwrites the file (last-run-wins). The audit trail of phase completion is in `session_data.gmcc.yaml`'s `phase_history:`.

These memory files are intended to survive across sessions, give the user something to grep, and provide context if a prompt is resumed days later.

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
| `/gm_init` | Initialize GM-CDE system (creates `~/gmcc_ckfs/` + `projects/` + registry) |
| `/gm_bot` | Lightweight bot workflow (primary context) |
| `/gm_bot_rpi` | Subagent Research/Plan/Implement workflow |
| `/gm_bot_team` | Agent team workflow (requires agent teams enabled) |
| `/gm_task` | Load session context and just do the task; read-only — no ckfs writes unless you explicitly ask for a retroactive write-back |
| `/gmcc_environment_cleanup` | Audit the whole CKFS environment for non-compliant structure, interactively resolve |
| `/gmcc_session_cleanup` | Audit only the current session ($GMCC_SESSION_PATH): prompt-folder integrity, index-file consistency, changed_files/phase_history, schema drift |
| `/gm_crunch_open_maw` | Create maw for collecting kbite crunchables |
| `/gm_crunch_chew` | Process crunchables into analyzed knowledge |
| `/gm_crunch_digest` | Finalize kbite from chewed resources |
| `/gm_kbite_relate` | Define relationship between kbites |

## Error Recovery

If ckfs is missing or corrupted:
1. Run `/gm_init` to recreate the projects root + registry
2. Restart Claude Code so `detect_repo.sh` re-provisions the current project/instance/session
3. Use `/gmcc_environment_cleanup` to surface any remaining non-compliance

If `$GMCC_SESSION_PATH` is missing at command time, that means the SessionStart hook didn't run. Restart Claude Code.
