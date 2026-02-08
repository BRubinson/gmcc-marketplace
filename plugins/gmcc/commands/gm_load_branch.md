---
name: gm_load_branch
description: Sets ACTIVE_BRANCH to the current git branch and initializes/loads the FAM (Feature Access Memory) for that branch.
argument-hint: [branch-name]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Load Branch and FAM

You are loading or creating a FAM (Feature Access Memory) for a branch.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: loading... | TASK: branch-load | STATE: in_progress
```

**Write state:** `{"task": "branch-load", "state": "in_progress"}` to `.claude/GMB_STATE.json`

## Environment Variables

The following should be set by the SessionStart hook:
- `$GMCC_CKFS_ROOT` - Base CKFS path (~/gmcc_ckfs)
- `$GMCC_REPO_ID` - Repository directory name
- `$GMCC_REPO_PATH` - Path to this repo's CKFS (~/gmcc_ckfs/{repo})
- `$GMCC_FAM_PATH` - Path to current branch FAM
- `$GMCC_PLUGIN_ROOT` - Plugin installation path

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
2. Get current git branch: `git branch --show-current`
3. If $ARGUMENTS provided, use that as branch name override

If CKFS doesn't exist:
```
[GMB] GM-CDE not initialized for this repository!

Run /gm_repo_init first to set up the CKFS.
```
Exit without changes.

## Determine Branch

```bash
BRANCH=$(git branch --show-current)
```

If $ARGUMENTS is provided and different from current branch:
Use AskUserQuestion:
```
You're on branch '{current}' but specified '{argument}'.

Which branch should I load the FAM for?
- Current branch ({current}) - Load FAM for the branch you're actually on
- Specified branch ({argument}) - Load FAM for the branch you named (useful for planning)
```

## Check for Existing FAM

Check if `$GMCC_REPO_PATH/fam/{branch_name}/` exists.

### If FAM Exists

1. Load the FAM context:
   - Read Purpose.md
   - Read Tasks.md
   - Read Famalouge.md
   - Read ChangedFiles.md

2. Update ACTIVE_BRANCH property

3. **Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

4. Report status:
```
[GMB] MODE: GM-CDE | BRANCH: {branch} | TASK: none | STATE: idle

Loaded FAM for branch: {branch}

Purpose: {first 2 lines of Purpose.md}

Open Tasks: {count of unchecked items in Tasks.md}
Completed Tasks: {count of checked items}

Recent Context:
{last 3 lines from Famalouge.md}

Ready to continue. Run /gm_bot_team, /gm_bot_rpi, or /gm_bot to start working.
```

### If FAM Does Not Exist

1. Use AskUserQuestion:
```
No FAM exists for branch '{branch}'.

Would you like to create one?
- Yes, create new FAM - Initialize FAM structure for this branch
- No, stay on main - Keep using main branch FAM
```

If no, exit without changes.

2. If yes, gather purpose info with AskUserQuestion:
```
What is the purpose of this branch?

Describe what you're trying to accomplish. This will be saved to Purpose.md and guide all work on this branch.
```
(Use "Other" free-text option for detailed input)

3. Create FAM directory structure:
```
$GMCC_REPO_PATH/fam/{branch_name}/
├── Purpose.md
├── Tasks.md
├── ChangedFiles.md
├── Famalouge.md
└── thoughts/
    └── .gitkeep
```

4. Populate files:

**Purpose.md**:
```markdown
# Branch Purpose: {branch_name}

## Why This Branch Exists
{user's description}

## Goals
- [ ] {parse goals from description or leave placeholder}

## Completion Criteria
- [ ] {parse criteria or leave placeholder}

---
*Created: {TODAY}*
*This file is human-editable. GMB may format but not change meaning.*
```

**Tasks.md**:
```markdown
# Tasks: {branch_name}

## Active Tasks
- [ ] Define initial tasks with /gm_bot_team, /gm_bot_rpi, or /gm_bot

## Completed Tasks
*None yet*

---
*Maintained by: GMB*
```

**ChangedFiles.md**:
```markdown
# Changed Files: {branch_name}

## Summary
Branch created. No changes yet.

## Diff from main
*Run /gm_fam_sync to update*

## File List
*None yet*

---
*Maintained by: GMB*
*Last sync: {TODAY}*
```

**Famalouge.md**:
```markdown
# Famalouge: {branch_name}

## Current Understanding
New branch created for: {purpose summary}

## Key Decisions
*None yet - development hasn't started*

## Context for New Sessions
- Branch purpose: {purpose}
- Ready for feature development
- Run /gm_bot_team or /gm_bot_rpi to start

---
*Compiled from thoughts by: GMB*
*Last compiled: {TODAY}*
```

5. Update $GMCC_REPO_PATH/FAM_INDEX.md:
Add new row:
```markdown
| {branch_name} | {purpose summary - max 50 chars} | {TODAY} | - | - |
```

6. Create initial thought:
Save to `$GMCC_REPO_PATH/fam/{branch}/thoughts/{timestamp}_branch_created.md`:
```markdown
# Thought: Branch Created

**Date**: {timestamp}
**Context**: New branch FAM initialized

## Purpose
{full purpose from user}

## Initial Understanding
{GMB's interpretation}

## Next Steps
- Define tasks with /gm_bot_team or /gm_bot_rpi
- Or add quick tasks with /gm_bot
```

7. **Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

8. Report success:
```
[GMB] MODE: GM-CDE | BRANCH: {branch} | TASK: none | STATE: idle

Created FAM for branch: {branch}

Purpose: {summary}

Files created:
- Purpose.md
- Tasks.md
- ChangedFiles.md
- Famalouge.md
- thoughts/branch_created.md

Updated:
- $GMCC_REPO_PATH/FAM_INDEX.md

Ready for development. Run /gm_bot_team, /gm_bot_rpi, or /gm_bot to begin.
```

## Error Handling

**Branch name has special characters**:
Sanitize branch name for filesystem:
- Replace `/` with `__`
- Remove other special chars

**Git not on a branch (detached HEAD)**:
```
[GMB] Warning: Detached HEAD state

You're not on a named branch. FAM requires a branch name.

Options:
1. Create a branch: git checkout -b <branch-name>
2. Checkout existing branch: git checkout <branch-name>
```
