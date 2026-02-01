---
name: gm_execute_remaining
description: Reviews remaining tasks in the FAM and creates an execution plan to complete them. Can run in planning mode or execute immediately.
argument-hint: [--plan-only]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# Execute Remaining Tasks

You are reviewing and executing remaining tasks from the current FAM.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: execute-remaining | STATE: planning
```

## Pre-Flight

1. Verify GM-CDE is initialized
2. Load current FAM (Tasks.md, Purpose.md, Famalouge.md)

## Gather Task State

Parse Tasks.md for:
- Incomplete tasks: `- [ ]`
- Completed tasks: `- [x]`
- Task groupings/features

## Present Task Summary

```
Remaining Tasks for branch '{branch}':

**Incomplete ({n}):**
{grouped by feature/section}

## Feature: {feature_name}
- [ ] {task 1}
- [ ] {task 2}

## Quick Tasks
- [ ] {task 3}

**Completed ({m}):**
- [x] {completed task 1}
- [x] {completed task 2}
```

## Task Analysis

Use AskUserQuestion:
```
I found {n} remaining tasks. How would you like to proceed?

- Execute all - Work through all tasks in order
- Select tasks - Choose specific tasks to complete
- Prioritize first - Let me analyze and suggest an order
- Plan only - Just create execution plan without doing
```

## If Prioritize First Selected

Analyze tasks for:
- Dependencies (which must come before others)
- Complexity (quick wins vs heavy lifts)
- Risk (higher risk tasks may need more attention)

Present prioritized order:
```
Suggested execution order:

1. {task} - Quick win, unblocks others
2. {task} - Dependency for #3
3. {task} - Main feature work
4. {task} - Polish/cleanup

Does this order work?
- Yes, execute in this order
- Reorder - Let me adjust
- Select subset - Only do some tasks
```

## If Select Tasks

Use AskUserQuestion with multi-select:
```
Which tasks should I complete?

{List all incomplete tasks as options}
- [ ] {task 1}
- [ ] {task 2}
- [ ] {task 3}
```

## Execution Plan

Create execution plan document (internal, not saved to ckfs):
```
Execution Plan:
1. {task 1}
   - Files involved: {list}
   - Approach: {brief}
   - Estimated complexity: {low/medium/high}

2. {task 2}
   - Files involved: {list}
   - Approach: {brief}
   - Estimated complexity: {low/medium/high}
```

## Plan Only Mode

If `$ARGUMENTS` contains `--plan-only`:

Save plan to `$GMCC_FAM_PATH/thoughts/{timestamp}_execution_plan.md`:
```markdown
# Thought: Execution Plan

**Date**: {timestamp}
**Context**: Planning remaining task execution

## Tasks to Execute
{prioritized list}

## Execution Strategy
{overall approach}

## Per-Task Plans

### Task: {task 1}
- **Files**: {list}
- **Approach**: {description}
- **Risks**: {any concerns}

{etc.}

## Estimated Effort
{overall assessment}
```

Report and exit:
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Execution plan created for {n} tasks.

Plan saved to: $GMCC_FAM_PATH/thoughts/{timestamp}_execution_plan.md

Run /gm_execute_remaining (without --plan-only) to execute.
```

## Execute Tasks

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: {current-task} | STATE: implementing
```

**Write state:** `{"task": "execute-remaining", "state": "implementing", "taskName": "{current-task}"}` to `.claude/GMB_STATE.json`

### For Each Task

1. Announce task start
2. Gather context (read relevant files)
3. Execute task
4. Mark complete in Tasks.md
5. Update ChangedFiles.md
6. Announce completion

If task hits a blocker, use AskUserQuestion:
```
Task blocked: {task name}

Issue: {description of blocker}

How should I proceed?
- Skip for now - Move to next task, come back later
- Help me resolve - Provide guidance to unblock
- Cancel execution - Stop and review
```

### Progress Updates

After each task:
```
[GMB] Progress: {completed}/{total} tasks

Completed: {task name}
Next: {next task name}
```

## Execution Complete

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Execution Complete

**Completed ({n}/{total}):**
- [x] {task 1}
- [x] {task 2}

**Skipped ({m}):**
- [ ] {task 3} - {reason}

**Files Modified:**
- {file list}

**Next Steps:**
- Run /gm_fam_sync to update diffs
- {address skipped tasks if any}
- Run /gm_merge_branch when ready
```

## All Tasks Already Complete

If no incomplete tasks:
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

All tasks complete!

No remaining tasks in Tasks.md.

Options:
- Add new tasks with /gm_task
- Start new feature with /gm_feature_dev
- Merge branch with /gm_merge_branch
```
