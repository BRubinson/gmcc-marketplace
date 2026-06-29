---
name: gmcc_session_cleanup
description: GM-CDE session-scoped cleanup auditor. Walks ONLY the current session ($GMCC_SESSION_PATH) to find non-compliant state — broken prompt folders, a missing/malformed session file index, stale changed_files/phase_history, and schema drift — and interactively resolves each finding with the user.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Session Cleanup Skill

Audits the **current session** (`$GMCC_SESSION_PATH`) for state that doesn't
conform to the current layout, and interactively resolves each finding.

This is the **session-scoped counterpart** to `gmcc_cleanup` (the
`/gmcc_environment_cleanup` command). The environment auditor deliberately
**excludes** the running session's paths from its walk (its safety guardrail
won't touch `$GMCC_SESSION_PATH`), so the inside of the active session is never
inspected there. This skill fills that gap: it looks *only* inside the current
session and never walks siblings or the broader `$GMCC_CKFS_ROOT`.

---

## When to Use

- When `/gm_bot*` reports a missing or malformed `session_data.gmcc.yaml`.
- After manually editing/deleting files inside the session's `prompts/` folder.
- To confirm the session's `gmcc_session_file_index.yaml` exists and conforms.
- Periodically, to keep the active session tidy and its registries in sync.

---

## Scope (hard boundary)

**Walk ONLY `$GMCC_SESSION_PATH`.** Never recurse into `$GMCC_CKFS_ROOT` broadly,
never inspect sibling sessions, never touch `_archive/`. The only files outside
the session that may be *read* (never written) are the parent
`instance_data.gmcc.yaml` (for cross-checks) and `$GMCC_PLUGIN_ROOT` templates.

---

## What Counts as Non-Compliant

### (a) Prompt folder integrity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Missing prompt-data file | `prompts/{id}_{name}/` has no `{id}_{name}_data.gmcc.yaml` | Recreate stub from the on-disk folder name, or archive the folder |
| Missing initial file | folder has data file but no `{id}_{name}_initial.yaml` | Recreate empty initial stub, or skip |
| Missing memory/ dir | prompt folder has no `memory/` subdir | Create empty `memory/` (default) |
| Loose file at prompts/ root | a `*.yaml` directly under `prompts/` (not in an `{id}_{name}/` folder) | Move into the correct prompt folder, or archive |
| Orphan registry entry | `session_data.prompts[]` lists an id whose folder is missing on disk | Remove from registry (default), or recreate the folder |
| Orphan prompt folder | `prompts/{id}_{name}/` exists but is not in `session_data.prompts[]` | Re-register (default), or archive |
| Status drift | `session_data.prompts[].status` ≠ the prompt-data file's `prompt_status` | Sync registry to the prompt-data file (source of truth) |

### (b) Index file consistency

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Missing index | no `gmcc_session_file_index.yaml` in the session | **Seed it** via the `gmcc_session_creation` skill (default), or skip |
| Wrong/absent yeet_type | header is not `gmcc.gmcc_session_file_index_file` | Backup + reseed, or skip |
| Missing required fields | no `architecture_decision_records:` list or no `yeeted:` mapping | Backup + reseed, or skip |
| Malformed ADR entry | an `architecture_decision_records[]` entry missing `id`/`name`/`description` | Backup + recreate the entry, or skip |

### (c) changed_files & phase_history integrity (in session_data)

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Stale changed_files entry | `changed_files[].file` points at a path that no longer exists | Remove the entry (default), or keep |
| Malformed changed_files entry | missing `file`/`timestamp`/`lines`/`commit`, or `note` absent | Repair the entry shape, or remove |
| Dangling phase_history | `phase_history[].prompt_id` references a prompt id not in `prompts[]` | Remove the entry (default), or keep |

### (d) Schema / version drift

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Outdated schema | a session file's shape no longer conforms to the current `gmcc.yeet.yaml` type | **Archive** the file to `$GMCC_CKFS_ROOT/_archive/cold_storage/` (default), then optionally reseed — **never** in-place auto-migrate |
| Wrong/absent yeet headers | a `.gmcc.yaml`/index file missing `yeet:`/`yeet_type:` | Add the headers, or archive |

> Schema conformance is judged **structurally** (`yeet_type` + required fields
> present and well-typed), not by a `version:` integer — the core ckfs yamls
> (including the session file index) carry no `version:` field. Outdated-schema
> files are **archived to cold storage**, not migrated in place (project
> convention: archive over migrate).

---

## Walk Strategy

Bounded to the session. Order:

1. **Session root** — confirm `session_data.gmcc.yaml`, `gmcc_session_file_index.yaml`,
   and `prompts/` exist. Anything else at the session root that isn't expected is
   a (cruft) finding.
2. **`session_data.gmcc.yaml`** — parse; run categories (a) registry cross-checks,
   (c) changed_files/phase_history, and (d) schema headers.
3. **`gmcc_session_file_index.yaml`** — run category (b).
4. **`prompts/` tree** — for each `{id}_{name}/` folder, run category (a) file
   presence + status-drift checks; flag loose root files.

Never descend into a prompt's `memory/` contents for compliance (free-form
artifacts), only confirm the dir exists.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is
always the recommended, non-destructive default. Standard options:

| Option | What it does |
|--------|--------------|
| **Archive** (default for outdated schema) | `mv` the file into `$GMCC_CKFS_ROOT/_archive/cold_storage/{relative_path}/`. Creates `_archive/cold_storage/` lazily. Reversible. |
| **Recreate / Reseed** (default for missing required files) | For the index file, delegate to the `gmcc_session_creation` skill (which create-if-missing-seeds it). For prompt-data stubs, rebuild from the folder name. Backs up any malformed original as `.bak` first. |
| **Remove from registry** (default for orphan/stale entries) | Edit `session_data.gmcc.yaml` to drop the dangling `prompts[]` / `changed_files[]` / `phase_history[]` entry. |
| **Skip** | Leave the finding in place. Always available. |

Per-category specials: **Re-register** (rebuild a `prompts[]` entry from an
on-disk folder), **Sync status** (copy `prompt_status` from the prompt-data file
into the registry).

---

## Output Format

After the walk, before any prompts:

```
[GMB] Session Audit Report

Scanned: $GMCC_SESSION_PATH
Total findings: {n}
- Prompt folder integrity: {n}
- Index file consistency: {n}
- changed_files / phase_history: {n}
- Schema drift: {n}

Beginning interactive resolution. You can abort at any time — completed actions are NOT rolled back.
```

After resolution:

```
[GMB] Session Cleanup Complete

Resolved: {n}/{total} findings
- Archived to cold storage: {n}
- Reseeded / recreated: {n}
- Registry entries removed: {n}
- Re-registered: {n}
- Status synced: {n}
- Skipped: {n}

Audit trail: cleanup_actions entries appended to $GMCC_SESSION_PATH/session_data.gmcc.yaml
```

---

## Audit Trail

On each applied action, append a `cleanup_actions:` entry to the current
`$GMCC_SESSION_PATH/session_data.gmcc.yaml` (the list is created on first use;
it is owned by the cleanup commands, not declared in the session_data yeet type).
Each entry: `{path, action, detail, timestamp}` — e.g.
`{path, action: "archive_to_cold_storage", detail: "outdated schema", timestamp}`,
`{path, action: "remove_registry_entry", detail: "orphan prompt id 4", timestamp}`,
`{path, action: "reseed_index", timestamp}`.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete** — the destructive default for outdated files is **archive to
  cold storage**, which moves (not deletes) data; the user can restore from
  `_archive/cold_storage/`.
- **Archive over in-place migrate** for outdated-schema files (project convention).
- **Backup before rewrite** — any malformed file that is reseeded gets a `.bak`
  copy first.
- **Stay in scope** — never act on anything outside `$GMCC_SESSION_PATH`.
- **--dry-run** — when invoked with `--dry-run`, walk and report only; skip the
  resolution loop entirely.
