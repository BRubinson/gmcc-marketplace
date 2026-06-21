# GMCC Migration Guide

## v11.0.0 to v12.0.0 — `/gm_task` command + kbite trigger system fully retired

Two changes, both behavioral rather than schema-level — no on-disk data migration
is required.

### New `/gm_task` command

Adds `/gm_task <request>` — a context-loaded, **read-only** sibling to `/gm_bot`.
It boots the full GMCC session context and then just does the work, **without** the
prompt-authoring ceremony (no draft folder, no initial/clarified prompt files, no
`changed_files`/`phase_history` bookkeeping). It writes nothing to the ckfs
(`$GMCC_CKFS_ROOT`) unless the user explicitly asks for a retroactive write-back
later in the conversation. Editing the user's *repository* files is still expected —
"read-only" refers to the ckfs only. Use it when you want GMCC context applied to a
task but don't want the prompt pipeline.

### KBite trigger system removed from the kbite skill

The trigger-activation paradigm was retired at the inheritance level in v11; v12
removes its last remnants from the kbite skill and templates. `KBITE_TRIGGERS.md`
and `KBITE_TRIGGER_MAP.md` are no longer part of the kbite layout, and the
"Suggested Triggers" / "Anti-Triggers" sections are dropped from the chewed-resource
template (the "Keywords and Triggers" section is now just "Keywords"). KBites are
discovered and loaded via `kbite:` inheritance registries, not trigger matching.

**Existing kbites:** any `KBITE_TRIGGERS.md` / `KBITE_TRIGGER_MAP.md` files left in
already-digested kbites are simply ignored — nothing reads them anymore. They can be
deleted at leisure; no action is required.

## v10.0.0 to v11.0.0 — Prompt style (typed initial/clarified files, backstory/goal/detail split, YEET-type detection)

Introduces the structured "prompt style": prompt content is split into named
components, the initial and clarified prompt files become typed YEETS documents,
the Clarify phase clarifies `goal` and `detail` with separate question suites, and
its first step detects YEETS types in the prompt. Every change is additive at the
type level; runtime data under existing v10.0.0 prompt folders is migrated by
`/gm_cleanup` (prompt-file schema `2 → 3`).

### Type additions in `gmcc.yeet.yaml`

- **Enum `gmcc_yeet_detection_source`** — `declared | inferred`.
- **Enum `gmcc_yeet_detection_confidence`** — `confident | needs_clarification`.
- **Struct `gmcc_initial_prompt_file`** — body of `{id}_{name}_initial.yaml`:
  `backstory`, `goal`, `detail`, `kbites_loaded`, `kbite_context_summary?`.
- **Struct `gmcc_clarified_prompt_file`** — body of `{id}_{name}_clarified.yaml`:
  `clarified_at`, `backstory`, `goal_clarifications`, `detail_clarifications`,
  `refined_goal`, `refined_detail`, `detected_yeet_types`, `key_files`,
  `patterns_to_follow?`, `constraints`, `kbites_loaded`.
- **Support structs** `gmcc_prompt_clarification` (`q`, `a`, `rating?`),
  `gmcc_detected_yeet_type` (`type`, `resolved_to`, `source`, `confidence`),
  `gmcc_clarified_prompt_key_file` (`path`, `relevance`, `consensus?`).
- **`backstory: string` added to `gmcc_session_data_file`** — seeded empty at
  session creation; new prompts inherit it into their initial `backstory`.

### YEETS grammar: new `datetime` primary type

The YEETS grammar gains a `datetime` primary type — an ISO 8601 datetime string
(e.g. `2026-06-21T15:40:00Z`), distinct from `timestamp` (an epoch-ms integer).
This is the type the GMCC runtime yamls have always *stored* for ISO 8601 fields.
`gmcc.yeet.yaml` now targets `yeet_version: "6.3"` and retypes the fields that
hold ISO 8601 strings to `datetime`: `has_created_time.created_time`,
`has_updated_time.updated_time`, `gmcc_session_data_file_changed_files_entry.timestamp`,
and the new `gmcc_clarified_prompt_file.clarified_at`. No on-disk data changes —
the values were already ISO 8601 strings; only the declared type is corrected (they
were previously typed `timestamp`). The Swift mapping (`datetime → String`) is
documented in `skills/gmcc/yeet_mappings/swift.yeet_template.md`. The short-list
enum form `values: [a, b, c]` (equivalent to `a | a` pairs when variable equals
backing string) is now documented explicitly in `skills/gmcc/SKILL.md`.

### Prompt content files become typed

Pre-change: `_initial.yaml` (single `content:`) and `_clarified.yaml`
(`original_content` + `clarifications` + `refined_content`) were untyped plain
yaml. Post-change: both keep the `.yaml` suffix but carry `yeet:` +
`yeet_type:` headers so `/gm_compile` validates them. The initial file splits
`content:` into `backstory` / `goal` / `detail`; the clarified file splits the
single Q/A list and `refined_content` into per-section suites and `refined_goal` /
`refined_detail`, and adds `detected_yeet_types`.

### Clarify phase: detection-first + split suites

When `prompt_status` moves to `Clarifying`, the **first** step is YEET-type
detection over the initial prompt's `goal` + `detail` — both explicitly-declared
types and structurally-inferred shapes. Each is resolved confidently or the user
is asked; results are recorded in `detected_yeet_types`. The bot then runs
**separate** `goal` and `detail` clarification suites. Applies to all three bots
(`/gm_bot`, `/gm_bot_rpi`, `/gm_bot_team`), preserving each tier's extras.

### Backstory

`session_data.gmcc.yaml` gains a `backstory:` field (in SESSION_TEMPLATE; copied
by `detect_repo.sh`, seeded empty). A future tool may populate it. New prompts
inherit the session backstory into their initial file at draft-create time; a
prompt's backstory may then diverge.

### Migration steps

1. Update the plugin to v11.0.0 and restart Claude Code. Fresh sessions get the
   `backstory:` field and new-shape prompt files automatically.
2. Existing `session_data.gmcc.yaml` files gain `backstory: ""` the next time
   `/gm_cleanup` migrates them (or add it by hand).
3. Run `/gm_cleanup`. It detects v2 prompt folders as **Outdated schema** and
   migrates each per-file: the initial file's `content:` is split into
   `backstory`/`goal`/`detail` and gains `yeet:`/`yeet_type:` headers; the
   clarified file is mapped to the new split shape with `detected_yeet_types: []`.
   Prompt-file schema version bumps `2 → 3`.

---

## v6.2.0 to v10.0.0 — Typing-system finalization (prompts → folders, kbite mixin, typed entries, hash-coded instances)

A follow-on within the v6.2.0 release that closes the v6.1.x typing gap
end-to-end. Every change is additive at the type level; runtime data
under existing v6.1 trees is migrated by `/gm_cleanup`.

### Type additions in `gmcc.yeet.yaml`

- **Enum `gmcc_prompt_status`** with values `Draft`, `Clarifying`, `Clarified`.
- **Mixin `has_kbite_list`** — single field `kbite: List<string>`. Unwrapped into all five file types (`gmcc_project_index_file`, `gmcc_project_data_file`, `gmcc_instance_data_file`, `gmcc_session_data_file`, `gmcc_prompt_data_file`). Inherited from parent at lazy-create time; deletes/changes do NOT propagate.
- **New file type `gmcc_prompt_data_file`** — top-level shape of `{prompt_folder}/{id}_{name}_data.gmcc.yaml`. Unwraps `has_base_fields`, `has_ckfs_paths`, `has_kbite_list`. Adds `initial_prompt_path`, `clarified_prompt_path` (empty until Clarified), `prompt_status`, `command`.
- **New entry type `gmcc_session_data_file_prompt_files_entry`** — lightweight stub (`id`, `name`, `status`, `path`).
- **New entry type `gmcc_session_data_file_changed_files_entry`** — typed (`file`, `timestamp`, `lines`, `commit`, `note`).
- **`branch: string` added to `gmcc_instance_data_file_session_entry`** — sessions now carry their raw branch in the instance_data entry alongside the slug-form `code`.
- **Replaced fields on `gmcc_session_data_file`**: `prompts: List<string>` → `List<gmcc_session_data_file_prompt_files_entry>`; `changed_files: List<string>` → `List<gmcc_session_data_file_changed_files_entry>`.

### Instance directory algorithm change

Pre-change: `instance_id` was the slugified absolute path
(`Users__brycerubinson__Dev__gmcc-marketplace`) and was used as both
the directory name and the `code:` field.

Post-change: `code = {basename($REPO_ROOT)}_{4-char hash of abs path}`
(e.g. `gmcc-marketplace_a3f2`). The code IS the directory name.
`name:` is the human-readable basename. The hook (`detect_repo.sh`)
derives this deterministically from `$REPO_ROOT` — no user input
required.

### Prompts on disk: file → folder

Pre-change: `prompts/{id}_{name}.yaml` + `prompts/{id}_{name}_clarified.yaml`
(two flat siblings).

Post-change: one folder per prompt:

```
prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # gmcc_prompt_data_file (index)
    {id}_{name}_initial.yaml        # raw user prompt content
    {id}_{name}_clarified.yaml      # absent until Clarified
    memory/
        explore.md
        architecture.md
        review.md
```

### Bot artifact persistence reversed

The earlier v6.0.0 "intermediate artifacts NOT persisted" policy is
**reversed**. All three bots (`/gm_bot`, `/gm_bot_rpi`, `/gm_bot_team`)
now write per-phase artifacts under `prompts/{id}_{name}/memory/`. For
`/gm_bot_team`, only the synthesized output of each team phase is
persisted — individual teammate reports are not. See
`skills/gmcc/ref/bot_workflows.md`.

### Migration steps

1. Update the plugin to v6.2.0 (typing finalization).
2. Restart Claude Code. `detect_repo.sh` will produce new code-based
   instance directories for fresh trees; existing v6.1 instances are
   untouched until `/gm_cleanup` runs.
3. Run `/gm_cleanup`. It detects:
   - Legacy slugified-abs-path instance directories → renames to
     `{basename}_{hash4}` and rewrites `gmcc_ckfs_absolute_path` /
     `gmcc_ckfs_relative_path` in the instance_data + every session_data
     beneath it + the matching entry in the parent project_data.
   - Legacy flat-file prompts (`prompts/{id}_{name}.yaml` +
     `prompts/{id}_{name}_clarified.yaml`) → migrates each pair into a
     `prompts/{id}_{name}/` folder containing `{id}_{name}_data.gmcc.yaml`,
     `{id}_{name}_initial.yaml`, and `{id}_{name}_clarified.yaml` (if
     present). Prompt-file schema version bumps `1 → 2`.
4. Existing session entries gain `branch:` automatically the next time
   `detect_repo.sh` registers a new session in that instance; legacy
   session entries are left alone until `/gm_cleanup` patches them.

---

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
