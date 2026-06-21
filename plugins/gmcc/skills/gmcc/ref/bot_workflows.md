# Bot Workflow System Reference (v10.0.0)

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
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index/status)
    {id}_{name}_initial.yaml        # raw user prompt + kbite context
    {id}_{name}_clarified.yaml      # absent until prompt_status = Clarified
    memory/
        explore.md                   # exploration report (Phase 2)
        architecture.md              # approved architecture (Phase 4)
        review.md                    # review report (Phase 6)
```

1. On invocation, the bot reads `$GMCC_SESSION_PATH/session_data.gmcc.yaml`.
2. It picks the next prompt id (max existing id + 1, or 1 if none).
3. It creates `prompts/{id}_{name}/` with the `memory/` subdir, writes `{id}_{name}_data.gmcc.yaml` (conforms to `gmcc_prompt_data_file`, `prompt_status: Draft`, kbite seeded from `session_data.kbite`) and `{id}_{name}_initial.yaml` (raw content).
4. It appends a lightweight stub to `session_data.gmcc.yaml`'s `prompts:` list (conforms to `gmcc_session_data_file_prompt_files_entry`): `id`, `name`, `status: Draft`, `path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml`.
5. The Clarify phase flips `prompt_status` to `Clarifying`, then on completion writes `{id}_{name}_clarified.yaml`, sets `clarified_prompt_path`, flips `prompt_status` to `Clarified`, and updates the session_data stub.
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
| `/gm_cleanup` | Audit CKFS for non-compliant structure, interactively resolve |
| `/gm_crunch_open_maw` | Create maw for collecting kbite crunchables |
| `/gm_crunch_chew` | Process crunchables into analyzed knowledge |
| `/gm_crunch_digest` | Finalize kbite from chewed resources |
| `/gm_kbite_relate` | Define relationship between kbites |

## Error Recovery

If ckfs is missing or corrupted:
1. Run `/gm_init` to recreate the projects root + registry
2. Restart Claude Code so `detect_repo.sh` re-provisions the current project/instance/session
3. Use `/gm_cleanup` to surface any remaining non-compliance

If `$GMCC_SESSION_PATH` is missing at command time, that means the SessionStart hook didn't run. Restart Claude Code.
