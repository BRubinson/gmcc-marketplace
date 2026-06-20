# Bot Workflow System Reference (v6.0.0)

Read this file when executing bot workflow commands.

## Workflow Tiers

| Command | Mode | Agents | Use Case |
|---------|------|--------|----------|
| `/gm_bot` | Lightweight | None (primary context) | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | 1 per phase (explore, architect, review) | Medium complexity |
| `/gm_bot_team` | Agent Teams | Teammates per phase (true agent teams) | Complex features, thorough exploration |

## Session + Prompt Model (v6.0.0)

All bot workflows operate inside the **current session** — automatically resolved by `detect_repo.sh` from `$PWD` + active git branch, exported as `$GMCC_SESSION_PATH`.

A bot run does NOT create a new session — it adds a new **prompt** to the existing session:

1. On invocation, the bot reads `$GMCC_SESSION_PATH/session_data.yaml`.
2. It picks the next prompt id (max existing id + 1, or 1 if none).
3. It writes a draft prompt to `$GMCC_SESSION_PATH/prompts/{id}_{name}.yaml` with the user's raw input + invocation metadata.
4. It appends an entry to `session_data.yaml`'s `prompts:` list with `status: draft`.
5. After the Clarify phase, it writes `$GMCC_SESSION_PATH/prompts/{id}_{name}_clarified.yaml` and flips the session_data entry to `status: clarified`.
6. Implementation runs. Each file edit appends to `session_data.yaml`'s `changed_files:` list with file, timestamp, line ranges, and commit ref.

### Resume Logic

To resume an in-progress prompt, invoke with the prompt id as the first argument:

```
/gm_bot 3 continue with the login endpoint
         ^prompt id  ^continuation
```

The bot:
1. Reads `session_data.yaml`, finds prompt with `id: 3`.
2. If `status: clarified`, reads the clarified file and proceeds to Implement.
3. If `status: draft`, reads the draft and resumes at Clarify.
4. If id not found, errors.

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

## Intermediate Artifacts Are Not Persisted (v6.0.0)

Exploration reports, architecture documents, and review reports from `/gm_bot_rpi` and `/gm_bot_team` live **only in conversation context**. They are not written to disk. This is a deliberate simplification for v6.0.0; if a workflow needs to communicate state to the user, it does so via chat output rather than a saved file.

The clarified prompt is the canonical persisted artifact. If you need to recreate exploration findings later, run the workflow again — the codebase is the ground truth.

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
