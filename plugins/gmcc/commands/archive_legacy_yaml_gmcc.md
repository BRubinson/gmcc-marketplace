---
name: archive_legacy_yaml_gmcc
description: Move imported legacy GMCC prompt folders (and fully-migrated level yamls) into $GMCC_CKFS_ROOT/_archive/cold_storage/, preserving the full projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}/ structure and every file. Only archives what /import_legacy_yaml_gmcc verifiably imported.
argument-hint: ""
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /archive_legacy_yaml_gmcc

Run Phase 2 (Archive) of the GM-CDE legacy migration. Full spec in
`$GMCC_PLUGIN_ROOT/skills/gmcc_migrate_legacy/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify the daemon is reachable (`~/gmcc/bin/gm ping`). This command is
meaningless before `/import_legacy_yaml_gmcc` has run.

Bare `gm prompt list` defaults to the current repo/branch session only —
it is **not** a whole-db query. For import-status verification always use
`gm prompt list --all --json`: it returns every prompt in the db, each
stub carrying its `session_uuid` (group by it to match legacy folders to
their sessions). If the whole-db listing shows zero imported rows, stop
and say so.

---

## Execution

Read the `gmcc_migrate_legacy` skill and follow its **Phase 2: Archive**
protocol exactly:

1. Per imported prompt folder (uuid verified in `gm prompt list --all`): `mv` it
   to `$GMCC_CKFS_ROOT/_archive/cold_storage/projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}` —
   structure preserved, every file intact (memory/*.md + the yaml triad).
2. Per fully-migrated level: archive the legacy `session_data` /
   file-index / `instance_data` / `project_data` / `project_index` yamls to
   the same relative cold-storage locations; keep the live directory
   skeleton (`sessions/{s}/prompts/`).
3. Never touch anything already under `_archive/`; never archive an
   unverified folder (report instead). The current session's own folders
   require explicit per-folder AskUserQuestion confirmation.
4. Report moved / archived / left-in-place counts with destinations.
