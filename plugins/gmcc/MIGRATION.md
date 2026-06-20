# GMCC Migration Guide

## v5.5.0 to v6.0.0 — Projects / Instances / Sessions (HARD CUT)

**This release replaces the per-branch FAM (`fam/{branch}/`) with a three-tier `projects/instances/sessions` hierarchy. There is no migration tool — v5.5.0 FAM data is left untouched on disk and ignored by v6.** Use the new `/gm_cleanup` command to audit your `$GMCC_CKFS_ROOT` for legacy state and choose what to do with it.

### New on-disk layout

```
~/gmcc_ckfs/
├── README.md
├── kbites/                                  # unchanged from v5.5
│   ├── {kbite_name}/KBITE_PURPOSE.md
│   ├── digested/{kbite_name}/...
│   └── open/{kbite_name}/...
└── projects/                                # NEW
    ├── project_index.yaml                   # registry of all projects
    └── {project_name}/                      # project name = git repo dir basename
        ├── Project_Data.yaml
        └── instances/
            └── {slug_of_abs_path}/          # one entry per physical checkout of this repo
                ├── instance_data.yaml
                └── sessions/
                    └── {sanitized_branch}/  # one entry per git branch in this instance
                        ├── session_data.yaml
                        └── prompts/
                            ├── {id}_{name}.yaml             # draft
                            └── {id}_{name}_clarified.yaml   # clarified
```

### Removed concepts

- The terms **FAM** and **per-branch FAM** are gone. Their replacement is **session** (a branch within an instance).
- `GMCC_REPO_PATH`, `GMCC_FAM_PATH`, `GMCC_REPO_ID`, `GMCC_ACTIVE_BRANCH` env vars are removed (not renamed — they point at a structure that no longer exists).
- `ChangedFiles.md` as a file is gone. Changed-files info is now a structured `changed_files:` section inside `session_data.yaml` (entries: `file`, `timestamp`, `lines` ranges, `commit`).
- `thoughts/mem_{N}_{name}/` workflow directories are gone. The per-session `prompts/` directory replaces them, and bot workflows now author prompts (draft + clarified) only — intermediate exploration/architecture/review reports are no longer persisted to disk (they live in conversation context).
- `plugins/gmcc/ckfs_templates/` is gone. Replaced by `plugins/gmcc/templates/projects/` (mirrors the runtime tree).

### New env vars (exported by `detect_repo.sh`)

| Var | Value |
|-----|-------|
| `GMCC_PROJECTS` | `$GMCC_CKFS_ROOT/projects` |
| `GMCC_PROJECTS_INDEX` | `$GMCC_CKFS_ROOT/projects/project_index.yaml` |
| `GMCC_PROJECT_PATH` | `$GMCC_PROJECTS/{project_name}` |
| `GMCC_INSTANCE_PATH` | `$GMCC_PROJECT_PATH/instances/{instance_id}` |
| `GMCC_SESSION_PATH` | `$GMCC_INSTANCE_PATH/sessions/{branch}` |

`detect_repo.sh` now **lazily creates** project / instance / session directories on every SessionStart, copying from `plugins/gmcc/templates/projects/`. This means the layout is always valid when commands run.

### Migration steps

1. Update the plugin to v6.0.0.
2. Restart Claude Code (so the new `detect_repo.sh` runs and provisions the projects tree for your current repo).
3. Run `/gm_init --force` if you want a clean `~/gmcc_ckfs/` (else the new dirs simply land alongside the old `fam/` data).
4. Run `/gm_cleanup` to audit your CKFS for legacy state. The command walks `$GMCC_CKFS_ROOT`, surfaces non-compliant paths (old `fam/` dirs, orphan registry entries, missing required files), and prompts you per-finding for an action (archive / delete / keep / fix).
5. Re-source your shell or open a new terminal — `/gm_init` re-writes the `~/.zshrc` env block to include `GMCC_PROJECTS` and `GMCC_PROJECTS_INDEX`.

### Deferred schemas

`Project_Data.yaml`, `instance_data.yaml`, `session_data.yaml`, and `project_index.yaml` ship with **minimal placeholder fields**. Full schema design lands in a follow-up release.

---

## v5.3.x / v5.4.0 to v5.5.0 — Cleanups before the FAM rewrite

This release is a set of focused cleanups in preparation for the upcoming FAM rewrite (projects/instances/sessions). No FAM data needs migration yet.

### Changes

- **`KBITE_PURPOSE.md` moves to the kbite root.** New canonical location: `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md` (above the `digested/`+`open/` lifecycle split). The digested folder now holds only generated indexes and the resource tree.
- **`compact_recovery.md` is dropped.** It was referenced by skill docs but never actually written (no PreCompact hook existed). Context recovery after compaction relies on `ChangedFiles.md` + `thoughts/`.
- **`gmcc_plugin_template/` is removed.** `/gm_init` no longer creates `~/gmcc_ckfs/gmcc_plugin_template/`. Nothing read from it.
- **`/gm_init` now persists the full GMCC env block in `~/.zshrc`** (all four `GMCC_CKFS_ROOT` + `GMCC_KBITE*` vars), with a current-state check before writing.
- **`scripts/detect_repo.sh` is the single source of truth for env vars.** The per-skill env-var tables in `gmcc/SKILL.md` and `gmcc_boot/SKILL.md` now point at the script instead of duplicating the list.
- **`/gmcc_boot` diagnostics** now echo all set `GMCC_*` vars dynamically (via `env | grep`), so they can't drift from what the script actually exports.

### Migration steps

1. Update the plugin to v5.5.0.
2. Restart Claude Code (so `detect_repo.sh` runs).
3. Run `/gm_bot_v4_migrate_kbite` once. The command now also relocates `KBITE_PURPOSE.md` from `$GMCC_KBITE_DIGESTED/{name}/` to `$GMCC_KBITE/{name}/` (idempotent).
4. *(Optional)* Re-run `/gm_init` if you want it to write the updated env block into `~/.zshrc`. It checks first; if your existing block differs, it leaves it in place and prints the expected contents for you to reconcile manually.
5. *(Optional)* Delete `~/gmcc_ckfs/gmcc_plugin_template/` by hand — nothing references it anymore.

### What's coming next (v6.0.0)

The FAM (`$GMCC_FAM_PATH`) format is being rewritten end-to-end. New top-level concept: `_PROJECTS` env var → `ckfs/projects/{name}/Project_Data.yaml` → instances (`instance_data.yaml`) → sessions (`session_data.yaml`). Templates will live under `plugins/gmcc/templates/projects/`. That work is gated on a separate RPI session; v5.5.0 is the last release of the current FAM format.

---

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
