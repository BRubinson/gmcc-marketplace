# GMCC Migration Guide

## v6.1.0 to v6.2.0 — `.yeet.md` → `.yeet.yaml` (pure YAML package format)

The YEETS type package file format is replaced end-to-end. The old `.yeet.md`
format (a markdown file with an embedded YAML body) is removed entirely — there
is no transition or dual-read period. All package files are now `.yeet.yaml`
(pure YAML, no markdown wrapper).

### Format changes

**Header / identity fields** — the old bolded-prose frontmatter block:

```
**Name**: Green Mountain Compiler Collection
**UUID**: 00000000-0000-0000-0000-000000000000
**Package**: gmcc
```

becomes top-level YAML keys:

```yaml
name: Green Mountain Compiler Collection
uuid: 00000000-0000-0000-0000-000000000000
package: gmcc
```

**Description** — the old `# Description` markdown heading + prose body becomes
a top-level `description: |` literal block scalar.

**Sections / types** — the old `# Types` / `## DEFAULT` / `### Enums` /
`### Structs` markdown heading hierarchy becomes a `sections:` YAML map keyed
by section name. `default:` (lowercase snake_case) is the required section.
Each section entry is a map with `description:`, `enums:`, and `structs:` keys:

```yaml
sections:
  default:
    description: ...
    enums: {}
    structs:
      my_struct:
        ...
```

**Imports** — bare `import {pkg}` markdown lines between the header and types
body become a top-level `yeet:` list:

```yaml
yeet: [other_pkg]
```

This unifies vocabulary with the existing `.gmcc.yaml` data-file convention
(which already used `yeet: [pkgs]`).

**New `yeet_version:` field** — an optional top-level key that selects the
grammar dialect. The current value is `"6.2"`. Omitting it falls back to the
latest known version.

**File marker** — every `.yeet.yaml` file begins with the comment:
`# YEETED — YEETS Type Package.`

### What did NOT change

Data structure is unchanged. Every struct, enum, field type, `Unwrap<T>`
composition keyword, nullability `?` suffix, `Enum<T>` / `Struct<T>` / `List<T>`
parametrics, nil-UUID bootstrap semantics for the `gmcc` package, and the
dual-import contract (`yeet:` in package files, `yeet:` in runtime yamls) all
carry over verbatim.

### Migration steps

1. Update the plugin to v6.2.0.
2. Rename `gmcc.yeet.md` → `gmcc.yeet.yaml` (and any other `.yeet.md` files in
   your CKFS or plugin tree). The content is the same data — only the container
   format changes.
3. `/gm_compile` now reads `.yeet.yaml` only; it will not find `.yeet.md` files.

### In-flight CKFS yaml state (recommended, not required)

Live `*.gmcc.yaml` files in user CKFS trees (`project_data`, `instance_data`,
`session_data`) copied from pre-v6.2 templates may carry stale comment headers
referencing `gmcc.yeet.md` instead of `gmcc.yeet.yaml`. These files still parse
correctly — the mismatch is documentation-stale only, not broken.

Recommended path when running `/gm_init` after updating to v6.2.0:

1. Identify any CKFS yamls whose top comment block references `gmcc.yeet.md`.
2. Move them to `_archive/cold_storage/` per the universal archive bucket
   convention (one bucket, no sub-sorting).
3. Reconstruct them from the current v6.2 templates, copying the live data
   fields verbatim: `id`, `uuid`, `code`, `name`, `description`,
   `created_time`, `updated_time`, path fields, and the
   `prompts`/`changed_files`/`sessions`/`instances` lists.

The reconstructed files inherit up-to-date headers and any v6.2 schema
additions automatically. This avoids surgical in-place comment edits across
every live CKFS yaml and makes `/gm_init` the single update path.

---

## v6.0.1 to v6.1.0 — Base YEETS types + `.gmcc.yaml` rename

> Note: `.yeet.md` (referenced throughout this entry) was superseded by `.yeet.yaml` in v6.2.0.

Populates `gmcc.yeet.md` with the core type definitions and migrates the
four runtime yaml files to YEETS-validated `.gmcc.yaml` form.

### New

- `gmcc.yeet.md` now exports the **base `has_*` mixins** (`has_serial_id`,
  `has_code`, `has_uuid`, `has_name`, `has_description`, `has_created_time`,
  `has_updated_time`, `has_base_fields`, `has_gmcc_ckfs_absolute_path`,
  `has_gmcc_ckfs_relative_path`, `has_ckfs_paths`, `has_system_path`) and
  the four **runtime file types** (`gmcc_project_index_file`,
  `gmcc_project_index_file_project_entry`, `gmcc_project_index_file_instance_entry`,
  `gmcc_project_index_file_session_entry`, `gmcc_project_data_file`, `gmcc_instance_data_file`,
  `gmcc_session_data_file`). Package UUID is the nil UUID (`00000000-...`),
  reserved for the bootstrap package.
- `UUID` and `FILE_PATH` are now primary types in YEETS.
- New section in `skills/gmcc/SKILL.md`: **The `unwrap` keyword** —
  documents YEETS struct composition (`unwrap` = implements / mixin),
  including inline `<YEET>` shorthand and the canonical `Unwrap<other>`
  longhand.
- **`.gmcc.yaml` suffix** marks a yaml as YEETS-enabled. The four core
  runtime files were renamed:
    - `project_index.yaml` → `project_index.gmcc.yaml`
    - `project_data.yaml` → `project_data.gmcc.yaml`
    - `instance_data.yaml` → `instance_data.gmcc.yaml`
    - `session_data.yaml` → `session_data.gmcc.yaml`
  Each now carries `yeet:` + `yeet_type:` top-level keys and conforms to
  its declared type.

### Field changes inside the runtime yamls

Each runtime yaml now unwraps `has_base_fields` + `has_ckfs_paths`. This
adds `id` (int serial), `code` (the slug — formerly `id` for instances /
`name` for projects), `uuid` (v4), `name` (display name), `description`,
`created_time` (formerly `created_at` / `registered_at` / `started_at`),
`updated_time`, `gmcc_ckfs_absolute_path`, `gmcc_ckfs_relative_path`.

Instance entries also unwrap `has_system_path` — the underlying repo
checkout path that used to live in `abs_path` now lives in `system_path`.

`project_index.gmcc.yaml` is the registry: it nests `projects[]` →
`instances[]` → `sessions[]`, each entry carrying full identity + path
fields.

### Migration steps

1. Update the plugin to v6.1.0.
2. `detect_repo.sh` provisions the new file shape automatically on next
   SessionStart for any new project / instance / session.
3. Existing v6.0.x `*.yaml` runtime files are NOT auto-migrated. Run
   `/gm_cleanup` (or invoke the prompt that did the live migration) to
   rewrite them.

---

## v6.0.0 to v6.0.1 — YEETS scaffolding

> Note: `.yeet.md` (referenced throughout this entry) was superseded by `.yeet.yaml` in v6.2.0.

Adds the YEETS (YAML Expositional Estimated Typing System) language to GMCC.

### New

- `## YEETS` section inline in `skills/gmcc/SKILL.md` — primary types, parametric collections (`Map`/`List`/`Set`), nullability (`?` type suffix), `Enum<T>` / `Struct<T>`, inline `<YEET>...</YEET>` blocks, `.yeet.md` file format (Name / UUID / Package frontmatter; mandatory `DEFAULT` section with `Enums` + `Structs` subsections), and the dual import contract (`import {pkg}` between `.yeet.md` files; top-level `yeet: [pkgs]` list inside `.yaml` files).
- `plugins/gmcc/gmcc.yeet.md` — core type package (`Package: gmcc`). Ships as a **TODO stub**; real type population deferred to v6.1.
- `/gm_compile <project> <instance> <session>` — read-only validation pass over `.yeet.md` files, importing yamls, and inline `<YEET>` blocks. Surface-level checks in v6.0.x; deep nested-generic validation lands in v6.1.

### Not changed

- `plugin.json` version is unchanged. No env vars added. No hook changes. No retrofit of existing yaml schemas (deferred to v6.1).

### Migration steps

1. Update the plugin to v6.0.x.
2. No restart required. `/gm_compile` is available immediately on next session.

---

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
    ├── project_index.gmcc.yaml                   # registry of all projects
    └── {project_name}/                      # project name = git repo dir basename
        ├── project_data.gmcc.yaml
        └── instances/
            └── {slug_of_abs_path}/          # one entry per physical checkout of this repo
                ├── instance_data.gmcc.yaml
                └── sessions/
                    └── {sanitized_branch}/  # one entry per git branch in this instance
                        ├── session_data.gmcc.yaml
                        └── prompts/
                            ├── {id}_{name}.yaml             # draft
                            └── {id}_{name}_clarified.yaml   # clarified
```

### Removed concepts

- The terms **FAM** and **per-branch FAM** are gone. Their replacement is **session** (a branch within an instance).
- `GMCC_REPO_PATH`, `GMCC_FAM_PATH`, `GMCC_REPO_ID`, `GMCC_ACTIVE_BRANCH` env vars are removed (not renamed — they point at a structure that no longer exists).
- `ChangedFiles.md` as a file is gone. Changed-files info is now a structured `changed_files:` section inside `session_data.gmcc.yaml` (entries: `file`, `timestamp`, `lines` ranges, `commit`).
- `thoughts/mem_{N}_{name}/` workflow directories are gone. The per-session `prompts/` directory replaces them, and bot workflows now author prompts (draft + clarified) only — intermediate exploration/architecture/review reports are no longer persisted to disk (they live in conversation context).
- `plugins/gmcc/ckfs_templates/` is gone. Replaced by `plugins/gmcc/templates/projects/` (mirrors the runtime tree).

### New env vars (exported by `detect_repo.sh`)

| Var | Value |
|-----|-------|
| `GMCC_PROJECTS` | `$GMCC_CKFS_ROOT/projects` |
| `GMCC_PROJECTS_INDEX` | `$GMCC_CKFS_ROOT/projects/project_index.gmcc.yaml` |
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

`project_data.gmcc.yaml`, `instance_data.gmcc.yaml`, `session_data.gmcc.yaml`, and `project_index.gmcc.yaml` ship with **minimal placeholder fields**. Full schema design lands in a follow-up release.

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

The FAM (`$GMCC_FAM_PATH`) format is being rewritten end-to-end. New top-level concept: `_PROJECTS` env var → `ckfs/projects/{name}/project_data.gmcc.yaml` → instances (`instance_data.gmcc.yaml`) → sessions (`session_data.gmcc.yaml`). Templates will live under `plugins/gmcc/templates/projects/`. That work is gated on a separate RPI session; v5.5.0 is the last release of the current FAM format.

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
