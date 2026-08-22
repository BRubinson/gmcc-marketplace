---
name: import_legacy_yaml_gmcc
description: Import legacy yaml-based GMCC prompts into the daemon db. Walks projects/** (skipping _archive/), backfills context chains + prompt rows (uuid-reused) + artifact pointers via gm. Read-only over the yamls; nothing is moved. Run before /archive_legacy_yaml_gmcc.
argument-hint: ""
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /import_legacy_yaml_gmcc

Run Phase 1 (Import) of the GM-CDE legacy migration. Full spec in
`$GMCC_PLUGIN_ROOT/skills/gmcc_migrate_legacy/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify the daemon is reachable (`~/gmcc/bin/gm ping`); if not, self-heal
first (`bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`), then retry. Run
`gm backup` before importing (cheap insurance).

---

## Execution

Read the `gmcc_migrate_legacy` skill and follow its **Phase 1: Import**
protocol exactly:

1. Walk `$GMCC_CKFS_ROOT/projects/` — **never** descend into `_archive/`.
2. Per session dir: `gm context ensure --from-ckfs "projects/{p}/instances/{i}/sessions/{s}" --json`.
3. Per current-shape prompt folder: `gm prompt create --uuid <reused> ...`
   (skip if the uuid is already in `gm prompt list`), then `set-status` to
   match the legacy status.
4. Register every file as an artifact pointer at its **post-archive**
   cold-storage path, with a one-sentence caption note.
5. Report: imported / skipped / left-in-place-for-triage counts. Malformed
   or older shapes are reported and left untouched.

This command moves NOTHING — the yamls stay in place until
`/archive_legacy_yaml_gmcc` is run.
