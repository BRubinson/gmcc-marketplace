# GMCC Migration Guide

## v5.2.x to v5.3.0 — KBite Layout Refactor

### What changed

The per-FAM maw is gone. All kbite state now lives under `$GMCC_CKFS_ROOT/kbites/` with two top-level subfolders, each containing one entry per kbite:

```
$GMCC_CKFS_ROOT/kbites/
├── digested/{kbite_name}/...      # persisted active index
└── open/{kbite_name}/...          # in-progress maw (one per kbite, system-wide)
```

| Old path | New path |
|----------|----------|
| `$GMCC_CKFS_ROOT/kbites/{name}/KBITE_*.md` | `$GMCC_CKFS_ROOT/kbites/digested/{name}/KBITE_*.md` |
| `$GMCC_CKFS_ROOT/kbites/{name}/primary/...` | `$GMCC_CKFS_ROOT/kbites/digested/{name}/primary/...` |
| `$GMCC_CKFS_ROOT/kbites/{name}/secondary/...` | `$GMCC_CKFS_ROOT/kbites/digested/{name}/secondary/...` |
| `$GMCC_FAM_PATH/maw/{name}/...` | `$GMCC_CKFS_ROOT/kbites/open/{name}/...` |

### New env vars

`detect_repo.sh` now exports three additional vars on every session start:

| Var | Value |
|-----|-------|
| `GMCC_KBITE` | `$GMCC_CKFS_ROOT/kbites` |
| `GMCC_KBITE_DIGESTED` | `$GMCC_CKFS_ROOT/kbites/digested` |
| `GMCC_KBITE_OPEN` | `$GMCC_CKFS_ROOT/kbites/open` |

Add the same exports to the `gmcc env` block in `~/.zshrc`:

```bash
# >>> gmcc env >>>
export GMCC_CKFS_ROOT="$HOME/gmcc_ckfs"
export GMCC_KBITE="$GMCC_CKFS_ROOT/kbites"
export GMCC_KBITE_DIGESTED="$GMCC_CKFS_ROOT/kbites/digested"
export GMCC_KBITE_OPEN="$GMCC_CKFS_ROOT/kbites/open"
# <<< gmcc env <<<
```

### Migration steps

1. Update the plugin to v5.3.0.
2. Restart Claude Code (so `detect_repo.sh` exports the new env vars).
3. Run `/gm_bot_v4_migrate_kbite` once. The command:
   - Moves each existing `kbites/{name}/{KBITE_*.md, primary/, secondary/}` into `kbites/digested/{name}/`.
   - Moves each legacy `$GMCC_CKFS_ROOT/{repo}/fam/{branch}/maw/{kbite}/` into `$GMCC_KBITE_OPEN/{kbite}/`.
   - Is idempotent — re-running on an already-migrated kbite is a no-op.

---

## v4.x to v5.0.0

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
