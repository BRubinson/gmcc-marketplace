# GMCC Migration Guide: v4.x to v5.0.0

## Breaking Changes

### Commands Replaced

| v4.x Command | v5.0.0 Command | Notes |
|-------------|----------------|-------|
| `/gm_feature_dev` | `/gm_bot_team` | Full agent team workflow (true agent teams) |
| `/gm_task` | `/gm_bot_rpi` | Subagent Research/Plan/Implement |
| `/gm_new_macro` | Removed | Skills replace macros directly |
| `/gm_evolve` | Removed | Edit marketplace repo directly |

### New Command

| Command | Description |
|---------|-------------|
| `/gm_bot` | Lightweight primary-context workflow (no subagents) |

### Systems Removed

- **Macro system** (`gmcc_macro` skill, `gmcc_macro_workflow_eclair` skill) - Eliminated. Skills and commands serve this purpose natively.
- **ECLAIR workflow** - Concepts absorbed into the three bot workflow commands.
- **`eclair_stop_check.sh` hook** - Stop hook removed.

### Memory System Change

| v4.x | v5.0.0 |
|------|--------|
| `ECLAIR_STATE_{session}.md` | `thoughts/mem_{index}_{name}/session_meta.md` |
| `ECLAIR_BRAIN.md` | No longer auto-maintained |
| Raw `thoughts/{timestamp}_{topic}.md` | Legacy format still supported, but bot workflows use mem folders |

## Migration Steps

1. Update the GMCC plugin to v5.0.0
2. Replace `/gm_feature_dev` usage with `/gm_bot_team`
3. Replace `/gm_task` usage with `/gm_bot_rpi`
4. Use `/gm_bot` for lightweight tasks
5. Existing ECLAIR sessions cannot be resumed - start fresh bot workflows
6. Existing `ECLAIR_STATE_*` and `ECLAIR_BRAIN.md` files can be referenced manually but are not consumed by v5

## Argument Format Change

All three bot commands use the same argument format:

```
/gm_bot <mem-name> <task description>     # New memory set
/gm_bot <index> <continuation prompt>     # Resume existing
```

## State Values Change

GMB_STATE.json `task` values updated:
- `feature-dev` → `bot-team`
- `quick-task` → `bot-rpi`
- New: `bot` (for /gm_bot)
- Removed: `macro-eclair`, `gm-evolve`
