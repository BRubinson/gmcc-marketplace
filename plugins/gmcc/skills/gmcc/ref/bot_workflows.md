# Bot Workflow System Reference

<!-- [FIX #2] Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when executing bot workflow commands. -->

## Workflow Tiers

| Command | Mode | Agents | Use Case |
|---------|------|--------|----------|
| `/gm_bot` | Lightweight | None (primary context) | Quick tasks, small changes |
| `/gm_bot_rpi` | Subagent RPI | 1 per phase (explore, architect, review) | Medium complexity |
| `/gm_bot_team` | Agent Teams | Teammates per phase (true agent teams) | Complex features, thorough exploration |

## Memory System

All bot workflows use organized memory folders at `$GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/`.

- **New memory**: Provide a mem-name as the first argument to start fresh
- **Resume**: Provide an index number to load existing memory and continue
- Each workflow writes specific artifacts to the mem folder

## KBite Integration

All bot workflows load kbites during initialization:
1. List available kbites from `$GMCC_CKFS_ROOT/kbites/`
2. Ask user to select relevant kbites
3. Load chewed files for selected kbites
4. Pass kbite context to all spawned agents

## Agent System

Agents are specialized personas defined in `$GMCC_PLUGIN_ROOT/prompts/`:

| Agent | Prompt File | Purpose |
|-------|-------------|---------|
| Code Explorer | `gmcc_agent_code_explorer.prompt.md` | Deep codebase analysis |
| Code Architect | `gmcc_agent_code_architect.prompt.md` | Architecture design |
| Code Reviewer | `gmcc_agent_code_quality_reviewer.prompt.md` | Code review |
| KBite Chew | `gmcc_agent_kbite_crunch_chew.prompt.md` | Analyze crunchables |

## GMCC Syntax Reference

| Type | Syntax | Example |
|------|--------|---------|
| Agent | `gmcc:agent:{name}(params)` | `gmcc:agent:code_explorer(target: "src/")` |

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_init` | Initialize GM-CDE system (creates ~/gmcc_ckfs/) |
| `/gm_repo_init` | Initialize GM-CDE for current repository |
| `/gm_load_branch` | Load/create FAM for current branch |
| `/gm_fam_sync` | Sync FAM with current changes |
| `/gm_fam_fmt` | Format FAM Purpose.md |
| `/gm_merge_branch` | Prepare merge and update indexes |
| `/gm_bot` | Lightweight bot workflow (primary context) |
| `/gm_bot_rpi` | Subagent Research/Plan/Implement workflow |
| `/gm_bot_team` | Agent team workflow (requires agent teams enabled) |
| `/gm_execute_remaining` | Execute pending tasks |
| `/gm_famalogue` | Compile thoughts to famalouge |
| `/gm_crunch_open_maw` | Create maw for collecting kbite crunchables |
| `/gm_crunch_chew` | Process crunchables into analyzed knowledge |
| `/gm_crunch_digest` | Finalize kbite from chewed resources |
| `/gm_kbite_relate` | Define relationship between kbites |

## Error Recovery

If ckfs is missing or corrupted:
1. Suggest running `/gm_init`
2. Do not proceed with GM-CDE commands until initialized

If FAM is missing for branch:
1. Automatically trigger FAM creation
2. Prompt user for Purpose.md content

If ACTIVE_BRANCH is stale:
1. Detect git branch mismatch
2. Prompt user to run `/gm_load_branch`
