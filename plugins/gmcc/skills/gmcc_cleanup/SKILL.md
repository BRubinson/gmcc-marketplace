---
name: gmcc_cleanup
description: GM-CDE CKFS cleanup auditor. Walks $GMCC_CKFS_ROOT to find non-compliant folder/file structures (legacy v5.x FAM data, misplaced files, orphan registry entries, missing required files) and interactively resolves each finding with the user.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Cleanup Skill

Audits `$GMCC_CKFS_ROOT` for state that doesn't conform to the current (v6.0.0+) layout and interactively resolves each finding.

This skill exists because v6.0.0 ships **no migration tool** from v5.x — the old FAM hierarchy (`{repo}/fam/{branch}/`) is ignored by the new runtime, not deleted. Users with v5.x data run `/gm_cleanup` to deliberately decide what to do with each piece of legacy state.

The skill is also useful steady-state: catching orphan registry entries, missing required files, and accidental cruft.

---

## When to Use

- After upgrading from v5.x to v6.0.0
- Periodically, to keep the CKFS tidy
- After manual ckfs edits (renamed dirs, deleted files) that may have desynced the registry
- When `/gm_bot*` reports a missing or malformed `session_data.gmcc.yaml`

---

## What Counts as Non-Compliant

| Category | Example | Default suggestion |
|----------|---------|--------------------|
| Legacy v5.x FAM | `~/gmcc_ckfs/{repo}/fam/{branch}/ChangedFiles.md` | Archive to `~/gmcc_ckfs/_archive/legacy_fam/{repo}/{branch}/` (default), or delete, or convert manually |
| Legacy v5.x repo root | `~/gmcc_ckfs/{repo}/` with no `projects/` parent | Archive (default) or delete |
| Orphan project registry entry | `project_index.gmcc.yaml` lists `foo` but `projects/foo/` doesn't exist | Remove from registry (default) or recreate empty project dir |
| Orphan project dir | `projects/foo/` exists but `foo` is not in `project_index.gmcc.yaml` | Re-register (default) or archive |
| Orphan instance registry entry | `project_index.gmcc.yaml` lists an instance `abs_path` that no longer exists on disk | Remove from registry (default) or keep (user moved the checkout temporarily) |
| Missing `project_data.gmcc.yaml` | `projects/{name}/instances/` exists but `project_data.gmcc.yaml` doesn't | Recreate from template (default) |
| Missing `instance_data.gmcc.yaml` | `projects/{p}/instances/{i}/sessions/` exists but `instance_data.gmcc.yaml` doesn't | Recreate from template (default) |
| Missing `session_data.gmcc.yaml` | `sessions/{branch}/prompts/` has files but `session_data.gmcc.yaml` doesn't | Recreate from template (default), rebuild `prompts:` list from filenames |
| **Outdated schema** | yaml `version:` field is lower than the template's `version:` for the same file type | **LLM-driven migration** (default — see "Schema Migration" section below), or skip, or backup+recreate |
| Malformed yaml | file fails to parse as yaml | LLM-driven repair (default — uses template + parseable fragments as context), or backup + recreate, or manual fix |
| Cruft at unexpected level | `projects/{name}/foo.txt` not matching the schema | Keep (default) or archive |
| Legacy `gmcc_plugin_template/` | `~/gmcc_ckfs/gmcc_plugin_template/` (removed in v5.5.0) | Delete (default) |
| Legacy `gmcc_user_workspace/` | Any path named `gmcc_user_workspace` (see deprecated concepts below) | Archive (default) or delete |
| Stale chewed provenance path | Inside `kbites/digested/{name}/.../*_chewed.md`, a `**Source**:` or `**Location**:` line points at an absolute path that no longer exists (typically a legacy maw under `~/gmcc_ckfs/{anything}/fam/.../maw/`) | Rewrite the line to strip the dead absolute prefix and prepend `(retired maw source) `, preserving the relative slug for provenance (default), or leave the line unchanged |

---

## Legacy Deprecated — No Longer Supported Concepts

This section is the **only** place in the live plugin that mentions these concepts. They are not part of the v6.0.0+ runtime and exist solely as cleanup targets when `/gm_cleanup` encounters them on a user's disk.

| Concept | What it was | Where it can appear | Detection signature |
|---------|-------------|---------------------|---------------------|
| `gmcc_user_workspace` (external) | A pre-CKFS scratch dir at `~/gmcc_user_workspace/`, used before v6 unified everything under `$GMCC_CKFS_ROOT`. Often git-initialized with assorted `.md`, `.swift`, `.excalidraw` files and ad-hoc sub-projects. | `~/gmcc_user_workspace/` (outside the CKFS) | Any directory at `$HOME/gmcc_user_workspace` is legacy by definition. Default action: **Archive** to `~/gmcc_ckfs/_archive/cold_storage/gmcc_user_workspace_external/`. |
| `gmcc_user_workspace` (CKFS-internal) | A v5.x-era copy that lived as a v5 repo root inside the CKFS, with its own `fam/`, `resource/`, `REPOSITORY_INDEX.md`, etc. | `~/gmcc_ckfs/gmcc_user_workspace/` | Falls under the generic "Legacy v5.x repo root" rule above. Default action: **Archive** to `~/gmcc_ckfs/_archive/cold_storage/gmcc_user_workspace/`. |
| `$GMCC_FAM_PATH` and friends | The v5.x env vars `GMCC_FAM_PATH`, `GMCC_REPO_PATH`, `GMCC_REPO_ID`, `GMCC_ACTIVE_BRANCH` pointed at the per-branch FAM directory structure. The runtime no longer exports them; if a shell still has them set, it's a stale shell. | `~/.zshrc`, `~/.bashrc`, exported in a long-running shell session | Grep user rc files for `GMCC_FAM_PATH=` / `GMCC_REPO_PATH=` exports. Default action: **flag for user** — do not auto-edit shell rc files. |
| FAM hierarchy | `~/gmcc_ckfs/{repo}/fam/{branch}/{ChangedFiles,Famalouge,Purpose,Tasks}.md` + `thoughts/mem_*` dirs. Replaced by `sessions/{branch}/session_data.gmcc.yaml` + `prompts/`. | Anywhere under `~/gmcc_ckfs/{anything}/fam/` | Covered by the "Legacy v5.x FAM" rule above. |
| `gmcc_plugin_template/` at CKFS root | A scaffolding dir for authoring sibling plugins; removed in v5.5.0. | `~/gmcc_ckfs/gmcc_plugin_template/` | Covered by the "Legacy `gmcc_plugin_template/`" rule above. |
| `ckfs_templates/` inside the plugin | Pre-v6 template location for FAM/CKFS scaffolding. Moved to `plugins/gmcc/templates/projects/`. | `plugins/gmcc/ckfs_templates/` inside any installed plugin checkout | Not normally on the user's CKFS — flag only if encountered. |
| `thoughts/mem_{N}_{name}/` dirs | v5.x equivalent of today's `prompts/{id}_{name}.yaml` + `_clarified.yaml`. | Inside any legacy `fam/{branch}/` tree | Captured by FAM hierarchy detection. |
| `REPOSITORY_INDEX.md`, `GREATER_PURPOSE.md`, `EVOLUTION_LOG.md`, `SRC_INDEX.md`, `FAM_INDEX.md`, `CHANGELOG.md` at a legacy repo root | The v5.x per-repo top-level docs. | Inside a legacy v5.x repo root in the CKFS | Captured by "Legacy v5.x repo root" detection. |

**Rule of thumb for additions:** when a concept is fully removed from the v6.0.0+ runtime, all live references should be deleted everywhere in the plugin and a single row added to this table. This file is the canonical graveyard.

### Stale Chewed Provenance Paths

A separate-but-related artifact: `*_chewed.md` files under `$GMCC_KBITE_DIGESTED/{name}/...` were produced by the chew agent from a maw source file, and they record where that source lived via a `**Source**:` or `**Location**:` line at the top of the file. When the underlying maw is retired (digested + deleted, or archived to cold storage), those absolute paths go stale — the chewed file remains the canonical artifact but the line is misleading.

Canonical rewrite (applied by `/gm_cleanup` and by hand here):

- Strip the dead absolute prefix (typically `/Users/.../gmcc_ckfs/{anything}/fam/{branch}/maw/`).
- Prepend `(retired maw source) ` to the remaining slug-relative path.
- Result: `**Source**: (retired maw source) {kbite}/{axis1}/{axis2}/{slug}/{file}.md`.

This preserves the slug for human provenance ("yes, this came from `swift_ui/primary/documentation/layout_fundamentals`") without lying about file existence.

Detection: any `*_chewed.md` under `kbites/digested/` whose `**Source**:` / `**Location**:` line starts with `/` and references a path that doesn't exist on disk. The chew prompt template should be updated separately to emit slug-relative paths in new chewed files.

---

## Schema Version Detection

Each templated yaml file carries a top-level `version:` integer. The cleanup skill reads the corresponding template file from `$GMCC_PLUGIN_ROOT/templates/projects/...` to determine the **current** version, then compares against each on-disk file:

| File type | Template path (current-version source) |
|-----------|----------------------------------------|
| `project_index.gmcc.yaml` | `templates/projects/project_index.gmcc.yaml` |
| `project_data.gmcc.yaml` | `templates/projects/PROJECT_TEMPLATE/project_data.gmcc.yaml` |
| `instance_data.gmcc.yaml` | `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.gmcc.yaml` |
| `session_data.gmcc.yaml` | `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.gmcc.yaml` |
| `prompts/{id}_{name}.yaml`, `{id}_{name}_clarified.yaml` | No templates ship — current version is hardcoded in this skill (currently 1). Bump this constant when the prompt-file schema changes. |

If the on-disk version is **equal** to the template's: file is compliant, no finding.
If the on-disk version is **lower**: emit an "Outdated schema" finding.
If the on-disk version is **higher**: emit a "Future schema" finding — the plugin is older than the data. Default action: skip (don't downgrade); suggest the user update the plugin.
If the on-disk version is **missing**: treat as version 0 (i.e., outdated).

---

## Schema Migration (LLM-driven)

When an "Outdated schema" finding is resolved with the default action, the cleanup skill does NOT apply a hardcoded migration function. Instead it asks the running model (you) to migrate the file content, using all available context. This means:

- No migration code needs to be pre-written when a schema is bumped.
- A schema bump is just: edit the template's `version:` + change its fields, and update `ckfs_details.md` to describe the new schema. The next `/gm_cleanup` run handles in-the-wild files automatically.
- Each migration is reviewed by the user before being written.

### Per-finding migration flow

For each "Outdated schema" finding the user chose to migrate:

1. **Read context** into the active model's working memory:
   - The full on-disk file content (the outdated one).
   - The full current template file (from `$GMCC_PLUGIN_ROOT/templates/projects/...`).
   - The relevant section of `$GMCC_PLUGIN_ROOT/skills/gmcc/ref/ckfs_details.md` (the schema documentation for that file type).
   - Sibling files at the same level if they could disambiguate intent (e.g., for a `session_data.gmcc.yaml` migration, the directory's `prompts/*.yaml` filenames help rebuild the prompts list if v2 changed its shape).

2. **Produce the migrated content.** Apply these rules when generating it:
   - Preserve every piece of user data from the old file — never drop fields whose data is recoverable. If a field was renamed, carry the value forward under the new name.
   - If a new required field has no source in the old file, fill it with the template's placeholder value or a sensible default and call this out in the diff summary.
   - If a field was removed in the new schema, drop it.
   - The output's `version:` field must equal the template's `version:`.
   - Comments from the template should be preserved in the output (they document the schema for future readers).

3. **Present the migration as a diff via AskUserQuestion**, with options:
   - **Apply** — write the migrated content to the original path, backing up the original as `{filename}.v{old_version}.bak` alongside.
   - **Skip** — leave the original in place, no backup. File remains in "outdated schema" state.
   - **Re-roll** — ask the model to produce a different migration (useful if the first attempt mishandled a field). The user can provide a hint.
   - **Backup + recreate from template** — drop the user's data, write a fresh file at the current version. Last resort.

4. **On Apply**, record the migration in `session_data.gmcc.yaml` of the **current** session (the one running `/gm_cleanup`) under a `cleanup_actions:` list. Each entry: `{path, action: "schema_migration", from_version, to_version, timestamp}`. This is the audit trail.

### What the user sees per migration

```
[GMB] Outdated schema: sessions/feature__login/session_data.gmcc.yaml

  Current on-disk version: 1
  Template version: 2

  I read: the file, the v2 template, and the schema doc.
  My proposed migration:

  --- /Users/.../session_data.gmcc.yaml (v1)
  +++ /Users/.../session_data.gmcc.yaml (v2)
  @@ -1,8 +1,12 @@
   version: 1
  +version: 2
  -changed_files:
  -  - file: src/auth.py
  -    timestamp: 2026-06-15T...
  -    lines: [[10, 20]]
  -    commit: abc1234
  +changed_files:
  +  - path: src/auth.py
  +    touched_at: 2026-06-15T...
  +    line_ranges: [[10, 20]]
  +    sha: abc1234
  +    note: ""        # new in v2, defaulted to empty

  Notes:
    - Renamed `file` → `path`, `timestamp` → `touched_at`, `lines` → `line_ranges`, `commit` → `sha`.
    - New required field `note` defaulted to empty string.

  - Apply (write v2, backup v1 as .v1.bak)
  - Skip (leave as v1)
  - Re-roll (try a different migration — give me a hint)
  - Backup + recreate from template (loses data)
```

### Bumping a schema yourself

Workflow when you want to introduce a new schema version:

1. Edit the template file: change its `version:` field and modify its structure.
2. Update `$GMCC_PLUGIN_ROOT/skills/gmcc/ref/ckfs_details.md` to describe the new schema (this is the LLM's spec at migration time — be precise about field meanings).
3. Ship. Existing in-the-wild files will be flagged as "Outdated schema" on the user's next `/gm_cleanup` run; the LLM handles them per-file.

No `if version == 1: ...` branches to write or maintain.

---

## Walk Strategy

The walk is bounded — never recurses into git repos, kbite resource trees, or `_archive/`. Order:

1. **Top-level of `$GMCC_CKFS_ROOT`** — anything other than `README.md`, `projects/`, `kbites/`, `_archive/` is a finding.
2. **`projects/`** — anything other than `project_index.gmcc.yaml` and per-project dirs is a finding.
3. **Per-project dir** — must have `project_data.gmcc.yaml` + `instances/`. Anything else is a finding.
4. **Per-instance dir** — must have `instance_data.gmcc.yaml` + `sessions/`. Anything else is a finding.
5. **Per-session dir** — must have `session_data.gmcc.yaml` + `prompts/`. Anything else is a finding.
6. **`prompts/`** — only `{id}_{name}.yaml` and `{id}_{name}_clarified.yaml` files; nothing else.
7. **Cross-check `project_index.gmcc.yaml`** against actual `projects/{name}/instances/{id}/` dirs. Mismatches in either direction are findings.
8. **Legacy detection**: `~/gmcc_ckfs/{anything}/fam/` is the v5.x signature. Any `{anything}/fam/{branch}/` tree is flagged with its full contents.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is always the recommended default. Standard option set:

| Option | What it does |
|--------|--------------|
| **Archive** (default for legacy) | `mv` the path into `~/gmcc_ckfs/_archive/{category}/{relative_path}/`. Creates `_archive/` lazily. Preserves the data without polluting the live tree. |
| **Delete** | `rm -rf` the path. Irreversible. Only offered when the data is clearly recoverable or unwanted. |
| **Recreate from template** (default for missing required files) | Copy from `$GMCC_PLUGIN_ROOT/templates/projects/...` with placeholders substituted. |
| **Skip** | Leave the finding in place, do nothing. Always available. |

Plus per-category specials:
- Orphan registry entries: **Re-register** (rebuild the registry entry from the on-disk state)
- Malformed yaml: **Backup + recreate** (save a `.bak` copy before rewriting)
- Legacy FAM directories: a one-time **Archive all** bulk action is offered after the first 3 findings so the user doesn't have to click through 50+ branches one at a time.

---

## Output Format

After the walk, before any prompts:

```
[GMB] CKFS Audit Report

Scanned: $GMCC_CKFS_ROOT
Total findings: {n}
- Legacy v5.x FAM: {n}
- Orphan registry entries: {n}
- Missing required files: {n}
- Outdated schema: {n}    ← LLM will be asked to migrate each one interactively
- Future schema (plugin older than data): {n}
- Malformed yaml: {n}
- Unexpected cruft: {n}

Beginning interactive resolution. You can abort at any time with Ctrl-C — completed actions are NOT rolled back.
```

After resolution:

```
[GMB] Cleanup Complete

Resolved: {n}/{total} findings
- Archived: {n} (to ~/gmcc_ckfs/_archive/)
- Deleted: {n}
- Recreated: {n}
- Re-registered: {n}
- Schema migrated: {n} (backups saved as .v{old}.bak alongside originals)
- Skipped: {n}

Aborted findings (still present): {n}

Audit trail: cleanup_actions entries appended to $GMCC_SESSION_PATH/session_data.gmcc.yaml
```

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete without explicit user choice** of the Delete option (the default is always non-destructive).
- **Archive is reversible**: data is moved, not deleted. The user can manually restore from `_archive/`.
- **Bulk actions** require an extra confirmation prompt.
- **Never touch the live current-session paths**: if the walk encounters `$GMCC_SESSION_PATH` or its parents, those are excluded from findings even if they look unusual (they belong to the running session).
