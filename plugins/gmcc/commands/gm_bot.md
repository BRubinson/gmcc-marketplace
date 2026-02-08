---
name: gm_bot
description: Lightweight GMCC workflow. All phases run in primary context with no subagents. Good for quick tasks, small implementations, and direct control.
argument-hint: <mem-name|index> <task/target/prompt>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot (Lightweight)

You are executing a lightweight development workflow entirely in the primary context.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: initializing
```

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
2. Get current git branch -> `{ACTIVE_BRANCH}`
3. Load current FAM context from `$GMCC_FAM_PATH/`:
   - Read Purpose.md
   - Read Tasks.md

If ckfs missing:
```
[GMB] GM-CDE not initialized. Run /gm_init first.
```

---

## Argument Parsing

Parse `$ARGUMENTS`:

### Case 1: First token is numeric (RESUME mode)
```
/gm_bot 3 continue with the login endpoint
         ^index    ^prompt
```
1. Find `$GMCC_FAM_PATH/thoughts/mem_3_*/` directory
2. If not found: error "No memory set found with index 3"
3. Read `session_meta.md` to restore context
4. Determine resume phase from existing files:
   - Has `fully_clarified_prompt.md` → resume at Phase 4 (Plan)
   - No clarified prompt → resume at Phase 3 (Clarify)
5. The remaining arguments become the continuation prompt

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot auth-refactor implement OAuth2 flow
         ^mem_name    ^prompt
```
1. Scan `$GMCC_FAM_PATH/thoughts/` for existing `mem_*` directories
2. Find the highest numeric index (default 0 if none exist)
3. Create `$GMCC_FAM_PATH/thoughts/mem_{index+1}_{mem_name}/`
4. Write initial `session_meta.md`

### Case 3: No arguments
Use AskUserQuestion:
```
What would you like to work on?

Provide a short name for this memory set and describe the task.
Example: auth-refactor implement OAuth2 flow

- Enter description - Type your task
```

---

## Memory Folder

### session_meta.md Template

Write to `$GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/session_meta.md`:

```markdown
# Memory Session: {mem_name}

**Index**: {index}
**Command**: /gm_bot
**Created**: {ISO timestamp}
**Branch**: {ACTIVE_BRANCH}
**Status**: active

## Initial Prompt
{raw user prompt}

## KBites Loaded
{list of kbite names, or "none"}

## Phase History
- {timestamp}: Session created
```

---

## Phase 1: KBite Index Loading (New Memory Only)

**Skip this phase if resuming an existing memory set.**

**Write state:** `{"task": "bot", "state": "initializing"}` to `.claude/GMB_STATE.json`

1. List available kbites from `$GMCC_CKFS_ROOT/kbites/`:
   - For each kbite directory, read `KBITE_PURPOSE.md` for a one-line summary

2. Use AskUserQuestion (multiSelect: true):
```
Which kbites are relevant to this task?

Available kbites:
- {kbite_1}: {purpose summary}
- {kbite_2}: {purpose summary}
- None - proceed without kbite context
```

3. For each selected kbite:
   - Read `KBITE_INDEX.md` for the resource list
   - Read `KBITE_TRIGGER_MAP.md` for relevant resource mapping
   - Load the top 3-5 highest-relevance chewed files into context

4. Update `session_meta.md` with loaded kbite names

---

## Phase 2: Implementation Overview

**Write state:** `{"task": "bot", "state": "exploring"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: exploring
```

With the kbite knowledge loaded, explore the codebase to build context:

1. Use Glob, Grep, and Read to find files relevant to the prompt
2. Map the relevant architecture and patterns
3. Identify integration points for the requested changes
4. Note any uncertainties or ambiguities for the Clarify phase

This is a mid-effort exploration done entirely in primary context. Focus on the most relevant files rather than exhaustive mapping.

---

## Phase 3: Clarify

**Write state:** `{"task": "bot", "state": "clarifying"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: clarifying
```

1. Based on exploration findings, identify underspecified aspects:
   - Edge cases and error handling
   - Integration points and scope boundaries
   - Design preferences
   - Backward compatibility concerns

2. Use AskUserQuestion to resolve all ambiguities

3. Write `fully_clarified_prompt.md` to the mem folder:

```markdown
# Fully Clarified Prompt

**Original Prompt**: {raw user prompt}
**Clarified**: {ISO timestamp}

## Clarifications

### Q: {question 1}
**A**: {answer 1}

### Q: {question 2}
**A**: {answer 2}

## Refined Task Description
{The original prompt rewritten with all clarifications integrated inline.
This is the single source of truth for what needs to be built.}

## Key Files Identified
- {file1}: {relevance}
- {file2}: {relevance}

## Constraints
- {constraint 1}
- {constraint 2}
```

4. Update `session_meta.md` phase history

---

## Phase 4: Plan

**Write state:** `{"task": "bot", "state": "planning"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: planning
```

1. Enter plan mode using EnterPlanMode
2. Design the implementation approach based on:
   - The fully clarified prompt
   - Kbite knowledge
   - Codebase exploration findings
3. Write a concrete plan with:
   - Files to create/modify
   - Implementation steps in order
   - Key patterns to follow
4. Exit plan mode for user approval

---

## Phase 5: Implement

**Write state:** `{"task": "bot", "state": "implementing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: implementing
```

1. Execute the approved plan
2. Write code changes
3. Update `session_meta.md` phase history as implementation progresses

---

## Phase 6: Feedback Integration

**Write state:** `{"task": "bot", "state": "reviewing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot | STATE: reviewing
```

1. Present a summary of what was implemented:
   - Files created/modified
   - Key decisions made
   - Any known limitations

2. Wait for user feedback

3. Iterate on feedback until the user is satisfied

4. On completion:

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

Update `session_meta.md`:
- Set Status to `completed`
- Add final phase history entry

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Bot Complete: {mem_name}

**Memory**: thoughts/mem_{index}_{mem_name}/
**Files Modified**: {count}
**Changes**: {brief summary}

**Next**: Run /gm_fam_sync to update FAM, or continue with more tasks.
```

---

## Error Handling

**Session paused (user stops responding):**
```
Session state preserved at: $GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/

To resume: /gm_bot {index} <continuation prompt>
```

**Task grows in scope:**
Use AskUserQuestion:
```
This task is growing beyond lightweight scope.

Would you like to upgrade?
- Continue as /gm_bot - Keep it lightweight
- Switch to /gm_bot_rpi - Add subagent exploration and review
- Switch to /gm_bot_team - Full agent team treatment
```
