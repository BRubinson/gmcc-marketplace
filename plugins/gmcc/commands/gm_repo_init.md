---
name: gm_repo_init
description: Initialize GM-CDE for the current repository. Creates the repo-specific CKFS structure at ~/gmcc_ckfs/{repo}/ with all necessary templates and the initial FAM.
argument-hint: [--force]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Initialize GM-CDE for Repository

You are initializing GM-CDE for this specific repository.

**IMPORTANT**: This command creates the repository-specific CKFS structure. The system-level `/gm_init` must be run first to create `~/gmcc_ckfs/` and the shared plugin template.

## Environment Variables

The following should be set by the SessionStart hook:
- `$GMCC_CKFS_ROOT` - Base CKFS path (~/gmcc_ckfs)
- `$GMCC_REPO_ID` - Repository directory name
- `$GMCC_REPO_PATH` - Path to this repo's CKFS (~/gmcc_ckfs/{repo})
- `$GMCC_FAM_PATH` - Path to current branch FAM
- `$GMCC_PLUGIN_ROOT` - Live plugin installation path (set by Claude for marketplace plugins)

## Pre-Flight Checks

First, verify:
1. This is a git repository (`git rev-parse --git-dir`)
2. System is initialized (`~/gmcc_ckfs/` exists)
3. Shared template exists (`~/gmcc_ckfs/gmcc_plugin_template/` exists)
4. Repo is not already initialized (unless `--force` in $ARGUMENTS)

### If Env Vars Not Set
The env vars may not be set if the SessionStart hook hasn't run. Proceed by computing them:
```bash
GMCC_CKFS_ROOT=~/gmcc_ckfs
GMCC_REPO_ID=$(basename $(git rev-parse --show-toplevel))
GMCC_REPO_PATH=$GMCC_CKFS_ROOT/$GMCC_REPO_ID
```

### If System Not Initialized
```
[GMB] GMCC system not initialized!

Run /gm_init first to create the system-level CKFS structure.
```
Exit without changes.

### If Shared Template Missing
```
[GMB] Shared plugin template not found!

Expected at: ~/gmcc_ckfs/gmcc_plugin_template/

Run /gm_init --force to reinitialize with the plugin template,
or manually copy: cp -r <plugin_path>/* ~/gmcc_ckfs/gmcc_plugin_template/
```
Exit without changes.

### If Repo Already Initialized (Without --force)
Use AskUserQuestion:
```
GM-CDE already initialized for this repository at:
$GMCC_REPO_PATH

What would you like to do?
- Reinitialize (wipe existing CKFS) - WARNING: This will delete all FAMs and history
- Keep existing (exit without changes)
- Load branch instead (run /gm_load_branch)
```

## Directory Structure Creation

Create the repository CKFS structure at `$GMCC_REPO_PATH`:

```
~/gmcc_ckfs/{repo}/
├── REPOSITORY_INDEX.md
├── GREATER_PURPOSE.md
├── SRC_INDEX.md
├── FAM_INDEX.md
├── CHANGELOG.md
├── EVOLUTION_LOG.md
├── resource/
│   └── .gitkeep
└── fam/
    └── main/
        ├── Purpose.md
        ├── Tasks.md
        ├── ChangedFiles.md
        ├── Famalouge.md
        └── thoughts/
            └── .gitkeep
```

**NOTE**: The plugin template is NOT stored per-repo. It lives at `~/gmcc_ckfs/gmcc_plugin_template/` and is shared across all repositories.

Also create in the project's `.claude/` directory:
```
.claude/
└── GMB_STATE.json
```

## File Templates

Use templates from `~/gmcc_ckfs/gmcc_plugin_template/ckfs_templates/` if they exist, otherwise use the inline templates below.

### GMB_STATE.json (in project .claude/)
```json
{"task": "none", "state": "idle"}
```

### REPOSITORY_INDEX.md
```markdown
# Repository: {REPO_NAME}

## Summary
[1-sentence description of this repository]

## Related Repositories

| Repository | Relationship |
|------------|--------------|
| | |

---
*This file tracks cross-repo relationships for GM-CDE*
```

### GREATER_PURPOSE.md
```markdown
# Greater Purpose

<!--
This document defines the ultimate goal of this project.
Only humans should edit this file.
GMB uses this to ensure all work aligns with the project vision.
-->

## Vision
[Describe the long-term vision for this project]

## Core Principles
- [Principle 1]
- [Principle 2]
- [Principle 3]

## Success Criteria
- [ ] [Major milestone 1]
- [ ] [Major milestone 2]
- [ ] [Major milestone 3]

---
*This file is human-maintained. GMB reads but never edits.*
```

### SRC_INDEX.md
```markdown
# Source Index

Index of all source files in the codebase.

| Path | Keywords | Elevator Pitch | Key Exports |
|------|----------|----------------|-------------|
| *Run /gm_merge_branch to populate* | | | |

---
*Last updated: Never*
*Updated by: GMB on merge operations*
```

### FAM_INDEX.md
```markdown
# FAM Index

Index of all Feature Access Memory (FAM) branches.

| Branch | Purpose | Opened | Closed | Files Changed |
|--------|---------|--------|--------|---------------|
| main | Primary development branch | {TODAY} | - | - |

---
*Updated by: GMB on branch operations*
```

### CHANGELOG.md
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Initialized GM-CDE environment

---
*Updated by: GMB on merge operations*
```

### EVOLUTION_LOG.md
```markdown
# GM-CDE Evolution Log

All evolutions to the GM-CDE template are logged here.
Evolution changes apply to the shared template at ~/gmcc_ckfs/gmcc_plugin_template/

---
```

### main/Purpose.md
```markdown
# Branch Purpose: main

## Why This Branch Exists
The main branch is the primary integration branch for stable code.

## Goals
- Maintain stable, working code
- Integrate completed features
- Serve as base for feature branches

## Completion Criteria
- All tests pass
- No known critical bugs
- Documentation current

---
*This file is human-editable. GMB may format but not change meaning.*
```

### main/Tasks.md
```markdown
# Tasks: main

## Active Tasks
- [ ] No active tasks on main

## Completed Tasks
- [x] Initialize GM-CDE environment

---
*Maintained by: GMB*
```

### main/ChangedFiles.md
```markdown
# Changed Files: main

## Summary
No changes tracked (this is the base branch).

## File List
*N/A for main branch*

---
*Maintained by: GMB*
*Last sync: {TODAY}*
```

### main/Famalouge.md
```markdown
# Famalouge: main

## Current Understanding
GM-CDE has been initialized. The main branch serves as the stable integration point.

## Key Decisions
- GM-CDE structure established
- Ready for feature development

## Context for New Sessions
- This is a freshly initialized GM-CDE environment
- No feature development has occurred yet
- GREATER_PURPOSE.md needs human input

---
*Compiled from thoughts by: GMB*
*Last compiled: {TODAY}*
```

## Post-Initialization

After creating all files:

1. **Configure Status Line** (if not already set):
   - Check `.claude/settings.local.json` for existing statusLine
   - If not present, add:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gm_statusline.sh"
     }
   }
   ```

2. **Prompt for GREATER_PURPOSE**:
   Use AskUserQuestion:
   ```
   Would you like to define the GREATER_PURPOSE now?
   - Yes, let me describe the vision - Opens interactive session to capture project goals
   - No, I'll fill it in later - You can edit ~/gmcc_ckfs/{repo}/GREATER_PURPOSE.md anytime
   ```

   If yes, ask follow-up questions:
   - What is this project trying to achieve?
   - What are the core principles guiding development?
   - What are the major milestones for success?

   Format their responses into GREATER_PURPOSE.md.

3. **Report Success**:
```
[GMB] MODE: GM-CDE | BRANCH: main | TASK: none | STATE: idle

GM-CDE repository initialized successfully!

Created at $GMCC_REPO_PATH:
- REPOSITORY_INDEX.md
- GREATER_PURPOSE.md {status}
- SRC_INDEX.md
- FAM_INDEX.md
- CHANGELOG.md
- EVOLUTION_LOG.md
- fam/main/ (complete FAM structure)

Created at .claude/:
- GMB_STATE.json (status line state)

Shared plugin template: ~/gmcc_ckfs/gmcc_plugin_template/

Next steps:
1. {Edit GREATER_PURPOSE.md if skipped}
2. Create a feature branch and run /gm_load_branch
3. Start development with /gm_bot_team, /gm_bot_rpi, or /gm_bot
```
