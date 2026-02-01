---
name: gm_feature_dev
description: Feature development entry point - invokes ECLAIR FULL mode for thorough multi-agent exploration, architecture design, and implementation with quality review.
argument-hint: [feature description] or [--resume]
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Feature Development (ECLAIR FULL)

You are executing feature development via the ECLAIR macro in FULL mode.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: feature-dev | STATE: initializing
```

## Pre-Flight

1. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
2. Get current git branch → this is `{ACTIVE_BRANCH}`
3. Load current FAM context:
   - Read Purpose.md
   - Read Tasks.md
   - Read Famalouge.md

If ckfs missing:
```
[GMB] GM-CDE not initialized. Run /gm_init first.
```

If on different branch than expected:
Use AskUserQuestion:
```
Branch mismatch detected!

You're on git branch '{git_branch}' but FAM context may be stale.

What would you like to do?
- Load current branch - Run /gm_load_branch for '{git_branch}'
- Continue anyway - Use existing FAM context
```

---

## Handle --resume Flag

If `$ARGUMENTS` contains `--resume`:

1. Search for ECLAIR_STATE files in `$GMCC_FAM_PATH/`:
   - Find files matching `ECLAIR_STATE_feat_*.md` or `ECLAIR_STATE_task_*.md`
   - Check status != "complete"

2. Use AskUserQuestion:
```
Which session would you like to resume?

{List incomplete ECLAIR sessions with their last phase and mode}
- {session_name_1} (Phase {N}: {phase_name}, mode: {mode})
- {session_name_2} (Phase {M}: {phase_name}, mode: {mode})
- Start fresh - Begin a new feature instead
```

3. Read ECLAIR_STATE file to get original mode:
   - Extract `**Mode**: {mode}` from state file

4. If original mode was "lite" (task session), warn user:
   Use AskUserQuestion:
   ```
   This session was started as a quick task (ECLAIR LITE mode).

   Resume options:
   - Continue as LITE - Keep streamlined execution (recommended)
   - Upgrade to FULL - Switch to 4-agent exploration (may duplicate work)
   - Start fresh FULL - Begin a new feature session
   ```

5. Invoke ECLAIR with appropriate mode:
```
gmcc:macro:workflow:eclair(
  session_name: "{selected_session}",
  resume: true,
  mode: "{mode_from_state_or_user_choice}"
)
```

---

## New Feature Flow

### 1. Capture Feature Request

If `$ARGUMENTS` is empty, use AskUserQuestion:
```
What feature would you like to build?

Describe the feature you want to implement. I'll use ECLAIR FULL mode for thorough exploration and architecture design.
```

### 2. Generate Session Name

Convert feature description to snake_case session name:
- "Add OAuth support" → `feat_oauth_support`
- "Fix login validation" → `feat_fix_login_validation`
- Prefix with `feat_` for features

### 3. Create Feature Request Thought

Save to `$GMCC_FAM_PATH/thoughts/{timestamp}_feature_request.md`:
```markdown
# Feature Request

**Date**: {timestamp}
**Feature**: {$ARGUMENTS}
**Mode**: ECLAIR FULL
**Session**: {session_name}

## Initial Understanding
{Brief interpretation of the feature request}
```

### 4. Invoke ECLAIR FULL Mode

```
gmcc:macro:workflow:eclair(
  mode: "full",
  session_name: "{session_name}",
  initial_prompt: "{$ARGUMENTS}"
)
```

ECLAIR FULL mode will execute all 6 phases with 4 divergent agents:
- **Phase 1 (Explore)**: 4 methodology-seeded code explorers
- **Phase 2 (Clarify)**: Interactive clarification with user
- **Phase 3 (Learn)**: Brain bite capture, context management
- **Phase 4 (Architect)**: 4 divergent architects + synthesis
- **Phase 5 (Implement)**: Task-tracked implementation
- **Phase 6 (Review)**: 4 methodology-seeded quality reviewers

---

## Post-ECLAIR Finalization

After ECLAIR completes:

### 1. Update Famalouge

Append to `$GMCC_FAM_PATH/Famalouge.md`:
```markdown
## Feature Completed: {Feature Name}

**Date**: {timestamp}
**ECLAIR Session**: {session_name}
**Mode**: FULL

**Summary**: {what was built}

**Key Decisions**:
- {decision 1 from ECLAIR Clarify/Architect phases}
- {decision 2}

**Files Modified**:
- {file list from ECLAIR Implement phase}
```

### 2. Final Report

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Feature Development Complete: {Feature Name}

**ECLAIR Session**: {session_name}
**Mode**: FULL (4 divergent agents per phase)

**Phases Completed**:
- ✓ Explore - Codebase understanding
- ✓ Clarify - Requirements refinement
- ✓ Learn - Knowledge capture
- ✓ Architect - Design synthesis
- ✓ Implement - Code changes
- ✓ Review - Quality validation

**Files Modified**: {count}

**Suggested Next Steps:**
- Run /gm_fam_sync to update FAM
- Run /gm_merge_branch when ready
```

---

## When to Use /gm_feature_dev vs /gm_task

| Use `/gm_feature_dev` (ECLAIR FULL) | Use `/gm_task` (ECLAIR LITE) |
|-------------------------------------|------------------------------|
| New features with unclear scope | Bug fixes with known location |
| Architecture decisions needed | Small, well-defined changes |
| Multiple components affected | Single file modifications |
| Want thorough exploration | Want quick execution |
| Complex requirements | Simple requirements |

---

## Error Handling

**ECLAIR session paused**:
```
ECLAIR session paused at Phase {N}.

State preserved at: $GMCC_FAM_PATH/ECLAIR_STATE_{session_name}.md

To resume later: /gm_feature_dev --resume
```

**User wants to abort**:
```
Feature development aborted.

Partial state preserved in ECLAIR_STATE file.
You can resume or start fresh later.
```
