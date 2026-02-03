---
name: gm_merge_branch
description: Prepares to merge the active branch to main - runs review agents, writes changelog entry, updates FAM_INDEX, updates SRC_INDEX, and ensures alignment with GREATER_PURPOSE.
argument-hint: [--dry-run]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task, AskUserQuestion
---

# Merge Branch to Main

You are preparing to merge the active branch to main with full GM-CDE tracking.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: merge-prep | STATE: in_progress
```

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized
2. Load current FAM
3. Verify branch is not main
4. Run /gm_fam_sync to ensure ChangedFiles is current

If on main:
```
[GMB] Already on main branch. Nothing to merge.
```

## Review Checklist

Use AskUserQuestion:
```
Pre-merge checklist for branch '{branch}':

Have you completed all planned work?
- Yes, all tasks done - Ready to merge
- No, incomplete - Review remaining tasks first
- Skip check - Force proceed anyway
```

If incomplete, show remaining tasks from Tasks.md.

## Launch Review Agents

### Code Review
Spawn agent to review all changes:
```
Review all changes from this branch for merge readiness.

Check:
- Code quality
- Potential bugs
- Missing tests
- Documentation gaps

Return: Issues by severity (critical/warning/suggestion)
```

### Alignment Check
Spawn agent to verify alignment:
```
Verify changes align with GREATER_PURPOSE.md.

Check:
- Do changes move toward project goals?
- Any contradictions with core principles?
- Does this contribute to success criteria?

Return: Alignment assessment
```

## Present Review Results

Use AskUserQuestion:
```
Merge Review Complete

**Code Review:**
{issues or "No issues found"}

**Alignment with GREATER_PURPOSE:**
{assessment}

**Recommendation:** {Ready to merge / Address issues first}

How would you like to proceed?
- Merge now - Continue with merge preparation
- Fix issues - Address problems before merging
- Cancel - Abort merge process
```

## Update CHANGELOG.md

Determine version increment:
- If new features: bump minor version
- If only fixes: bump patch version
- (User can override)

Add entry to `$GMCC_REPO_PATH/CHANGELOG.md`:

```markdown
## [{version}] - {TODAY}

### Added
{list of new features from Tasks.md}

### Changed
{list of changes}

### Fixed
{list of bug fixes}

### Removed
{list of removed items}
```

## Update SRC_INDEX.md

For each changed/created source file:

1. If file is new, add row:
```markdown
| {path} | {keywords} | {3-sentence pitch} | {key exports} |
```

2. If file modified significantly, update its row

3. If file deleted, remove its row

## Update FAM_INDEX.md

Update the branch row:
```markdown
| {branch} | {purpose} | {opened} | {TODAY} | {list of changed files} |
```

## Close FAM

Update FAM files:

### Tasks.md
Verify all tasks marked complete.
If incomplete tasks exist:
Use AskUserQuestion:
```
There are {n} incomplete tasks:
{task list}

How should these be handled?
- Mark as complete - They're done, just not checked
- Move to main - These will continue on main
- Cancel merge - I need to complete these first
```

### Famalouge.md
Add closing entry:
```markdown
## Branch Closed: {TODAY}

**Summary:** {What was accomplished}

**Merged to main:** Yes
**Final changes:** {n} files
```

### Create closing thought
Save to `$GMCC_FAM_PATH/thoughts/{timestamp}_branch_merged.md`:
```markdown
# Thought: Branch Merged

**Date**: {timestamp}
**Context**: Branch merged to main

## Accomplishments
{Summary of what was done}

## Lessons Learned
{Any insights from this work}

## Future Considerations
{Anything to keep in mind}
```

## Dry Run Mode

If `$ARGUMENTS` contains `--dry-run`:

Only show what would happen without making changes:
```
[GMB] Dry Run - Merge Preparation

Would update:
- CHANGELOG.md: Add version {x.y.z}
- SRC_INDEX.md: {n} files to update
- FAM_INDEX.md: Close branch entry
- Tasks.md: {n} tasks to mark complete

Would create:
- $GMCC_FAM_PATH/thoughts/{timestamp}_branch_merged.md

No changes made. Run without --dry-run to execute.
```

## Execute Merge Preparation

### Set ACTIVE_BRANCH to main
Update property tracking.

### Report Success

```
[GMB] MODE: GM-CDE | BRANCH: main | TASK: none | STATE: idle

Merge Preparation Complete: {branch}

**Updated:**
- CHANGELOG.md (version {x.y.z})
- SRC_INDEX.md ({n} file entries)
- FAM_INDEX.md (branch closed)

**FAM Archived:**
- Branch work preserved in $GMCC_FAM_PATH/
- Closing thought recorded

**Next Steps:**
1. Execute git merge: `git checkout main && git merge {branch}`
2. Push to remote: `git push`
3. Delete branch: `git branch -d {branch}`

The git commands above are not executed automatically.
Run them manually to complete the merge.
```

## Error Handling

### Merge conflicts expected
```
Warning: Files modified on both branches

These files may have merge conflicts:
- {file list}

Recommendation: Run `git diff main` to preview conflicts before merging.
```

### FAM not found
```
[GMB] Error: No FAM found for branch '{branch}'

Run /gm_load_branch first to create the FAM, or merge manually without GM-CDE tracking.
```
