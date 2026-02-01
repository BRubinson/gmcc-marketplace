---
name: gm_task
description: Quick task entry point - invokes ECLAIR LITE mode for streamlined execution with single hybrid agent per phase. Good for bug fixes, small features, and well-defined work.
argument-hint: <task description>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Quick Task (ECLAIR LITE)

You are executing a quick task via the ECLAIR macro in LITE mode.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: quick-task | STATE: initializing
```

## Pre-Flight

1. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
2. Get current git branch → this is `{ACTIVE_BRANCH}`
3. Load current FAM context from `$GMCC_FAM_PATH/`:
   - Read Purpose.md
   - Read Tasks.md

If no task description provided ($ARGUMENTS empty):
Use AskUserQuestion:
```
What task would you like to accomplish?

Describe the task briefly. For complex features, use /gm_feature_dev instead.
```

---

## Task Classification

Analyze the task to determine complexity:

### Simple Task Indicators (Use ECLAIR LITE)
- Bug fix with known location
- Adding a small feature
- Configuration change
- Documentation update
- Refactoring with clear scope
- Single file modifications

### Complex Task Indicators (Suggest /gm_feature_dev)
- Multiple components involved
- Architecture decisions needed
- Unclear requirements
- New patterns required
- Multiple files across different modules

If task seems complex:
Use AskUserQuestion:
```
This task seems complex. It may benefit from ECLAIR FULL mode with thorough multi-agent exploration.

How would you like to proceed?
- Use /gm_feature_dev (Recommended) - ECLAIR FULL with 4 divergent agents per phase
- Continue as quick task - ECLAIR LITE with 1 hybrid agent per phase
- Let me simplify the task - I'll break it down into smaller pieces
```

---

## Task Execution

### 1. Generate Session Name

Convert task description to snake_case session name:
- "Fix login bug" → `task_fix_login_bug`
- "Add config option" → `task_add_config_option`
- Prefix with `task_` for tasks

### 2. Create Task Thought

Save to `$GMCC_FAM_PATH/thoughts/{timestamp}_task_{name}.md`:
```markdown
# Quick Task

**Date**: {timestamp}
**Task**: {$ARGUMENTS}
**Mode**: ECLAIR LITE
**Session**: {session_name}

## Classification
- Complexity: Simple
- Estimated scope: {brief scope assessment}
```

### 3. Invoke ECLAIR LITE Mode

```
gmcc:macro:workflow:eclair(
  mode: "lite",
  session_name: "{session_name}",
  initial_prompt: "{$ARGUMENTS}"
)
```

ECLAIR LITE mode executes all 6 phases with 1 hybrid agent (Pragmatic+Alternative):
- **Phase 1 (Explore)**: 1 hybrid code explorer
- **Phase 2 (Clarify)**: Interactive clarification (streamlined)
- **Phase 3 (Learn)**: Optional brain bite capture
- **Phase 4 (Architect)**: 1 hybrid architect
- **Phase 5 (Implement)**: Task-tracked implementation
- **Phase 6 (Review)**: 1 hybrid quality reviewer

---

## Post-ECLAIR Finalization

After ECLAIR completes:

### 1. Update ChangedFiles.md

Update `$GMCC_FAM_PATH/ChangedFiles.md`:
```markdown
## Quick Task: {task-name}
- {file1}: {what changed}
- {file2}: {what changed}
```

### 2. Final Report

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Task Complete: {task-name}

**ECLAIR Session**: {session_name}
**Mode**: LITE (1 hybrid agent per phase)

**Phases Completed**:
- ✓ Explore → Clarify → Learn → Architect → Implement → Review

**Changes:**
- {summary of changes}

**Files Modified:**
- {file list}

**Next:**
- Run /gm_fam_sync to update diffs
- Continue with more tasks or /gm_merge_branch when ready
```

---

## When to Use /gm_task vs /gm_feature_dev

| Use `/gm_task` (ECLAIR LITE) | Use `/gm_feature_dev` (ECLAIR FULL) |
|------------------------------|-------------------------------------|
| Bug fixes with known location | New features with unclear scope |
| Small, well-defined changes | Architecture decisions needed |
| Single file modifications | Multiple components affected |
| Want quick execution | Want thorough exploration |
| Simple requirements | Complex requirements |

---

## Converting to Feature Dev

If at any point the task grows in scope:

Use AskUserQuestion:
```
This task is growing beyond quick task scope.

Would you like to convert to ECLAIR FULL mode?
- Yes, convert to feature dev - Switch to /gm_feature_dev with ECLAIR FULL
- No, continue as is - Complete with ECLAIR LITE
```

If converting, the current ECLAIR LITE session state is preserved and can inform the FULL mode session.

---

## Error Handling

**ECLAIR LITE session paused**:
```
Task paused at Phase {N}.

State preserved at: $GMCC_FAM_PATH/ECLAIR_STATE_{session_name}.md

To resume: Invoke /gm_task again and select resume option.
```

**Task blocked**:
```
Task blocked by {blocker}.

Options:
- Resolve blocker and retry
- Convert to /gm_feature_dev for deeper exploration
- Abort task
```
