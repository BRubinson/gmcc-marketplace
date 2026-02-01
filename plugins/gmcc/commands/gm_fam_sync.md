---
name: gm_fam_sync
description: Syncs the current FAM with git state - updates ChangedFiles.md with diffs from main, verifies file lists, and keeps the FAM context current.
argument-hint: [--full]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob
---

# Sync FAM with Git State

You are synchronizing the current FAM with the actual git state.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: fam-sync | STATE: in_progress
```

**Write state:** `{"task": "fam-sync", "state": "in_progress"}` to `.claude/GMB_STATE.json`

## Pre-Flight

1. Verify GM-CDE is initialized
2. Verify ACTIVE_BRANCH matches current git branch
3. Load current FAM

## Gather Git State

Run these commands:

```bash
# Get current branch
git branch --show-current

# Get diff summary against main
git diff main --stat

# Get list of changed files
git diff main --name-only

# Get detailed diff (for full sync)
git diff main
```

## Update ChangedFiles.md

Rewrite `$GMCC_FAM_PATH/ChangedFiles.md`:

```markdown
# Changed Files: {branch}

## Summary
{n} files changed, {insertions} insertions(+), {deletions} deletions(-)

## Diff from main
```diff
{git diff main --stat output}
```

## File List
{For each changed file:}
- `{filepath}`: {brief description of changes based on diff}

---
*Maintained by: GMB*
*Last sync: {NOW}*
```

## Full Sync (--full flag)

If `$ARGUMENTS` contains `--full`:

1. Also update the detailed diffs section:
```markdown
## Detailed Changes

### {filepath}
```diff
{actual diff for this file}
```
```

2. Verify Tasks.md reflects current work:
   - Check if any tracked tasks are complete but not checked
   - Check if ChangedFiles.md files align with task descriptions

3. Update Famalouge.md with sync summary:
```markdown
## Sync: {timestamp}
- {n} files changed
- Key changes: {summary}
```

## Handle Edge Cases

### No changes from main
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

FAM Sync: No changes detected

This branch is identical to main. Nothing to sync.
```

### Merge conflicts detected
```
[GMB] Warning: Potential merge conflicts

The following files have diverged significantly from main:
- {file list}

Consider running `git fetch && git rebase main` before continuing.
```

### Branch ahead of main
Report commits ahead:
```bash
git log main..HEAD --oneline
```

## Sync Complete

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

FAM Sync Complete

**Changes from main:**
- {n} files changed
- +{insertions} -{deletions}

**Updated:**
- ChangedFiles.md
{if --full:}
- Famalouge.md

**Branch Status:**
- {n} commits ahead of main
- {merge conflict warning if applicable}
```
