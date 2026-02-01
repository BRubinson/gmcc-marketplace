---
name: gm_evolve
description: Evolve GM-CDE by updating template and instance using the ECLAIR macro workflow. High-accuracy evolution with exploration, clarification, learning, architecture, implementation, and review.
argument-hint: <evolution description>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task, AskUserQuestion
---

# GM-CDE Evolution Command (ECLAIR-Powered)

You are evolving the GM-CDE system itself using the ECLAIR macro workflow for high-accuracy implementation.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: gm-evolve | STATE: initializing
```

**Write state:** `{"task": "gm-evolve", "state": "initializing"}` to `$GMCC_PLUGIN_ROOT/GMB_STATE.json`

---

## Pre-Flight Checks

1. Verify template exists at `$GMCC_REPO_PATH/gmcc_plugin_template/`
2. Verify instance is initialized (`$GMCC_PLUGIN_ROOT/ckfs/` exists)
3. Get current git branch

### If Template Missing
```
[GMB] Template not found at $GMCC_PLUGIN_ROOT/green_mountain_template/

The GM-CDE template directory is required for evolution.
Create it by copying current instance files, or check your installation.
```
Exit without changes.

### If Instance Not Initialized
```
[GMB] Warning: GM-CDE instance not fully initialized

$GMCC_PLUGIN_ROOT/ckfs/ not found. You can still evolve the template,
but instance sync will be skipped.

Continue with template-only evolution?
```
Use AskUserQuestion to confirm.

---

## Invoke ECLAIR Macro

After pre-flight passes, invoke the ECLAIR macro for the evolution:

### Generate Session Name

Convert `$ARGUMENTS` to a snake_case session name:
- `"update evolve to use eclair"` → `evolve_eclair_update`
- `"add new gm_audit command"` → `evolve_gm_audit_command`
- Prefix with `evolve_` to distinguish from feature development sessions

### ECLAIR Invocation

```
gmcc:macro:workflow:eclair(
  session_name: "{generated_session_name}",
  initial_prompt: "GM-CDE Evolution Request: {$ARGUMENTS}

## Evolution Context

This is a GM-CDE system evolution, not a feature development task. The scope is:
- Skills: `$GMCC_PLUGIN_ROOT/green_mountain_template/skills/`
- Commands: `$GMCC_PLUGIN_ROOT/green_mountain_template/commands/`
- Agents: `$GMCC_PLUGIN_ROOT/green_mountain_template/agents/`
- Props: `$GMCC_PLUGIN_ROOT/green_mountain_template/props/`
- Macros: `$GMCC_PLUGIN_ROOT/green_mountain_template/skills/gmcc_macro*/`
- FAM Templates: `$GMCC_PLUGIN_ROOT/green_mountain_template/ckfs_templates/`

## Critical Rules for GM-CDE Evolution

1. **Template First**: Always update `$GMCC_REPO_PATH/gmcc_plugin_template/` FIRST - this is the source of truth
2. **Instance Sync**: After template changes, sync to `$GMCC_PLUGIN_ROOT/` instance files
3. **Never Sync These**:
   - `~/gmcc_ckfs/` (runtime FAM files)
   - `$GMCC_PLUGIN_ROOT/settings.local.json` (instance-specific)
4. **Skill Changes**: If `skills/gmcc/SKILL.md` is modified, user must restart Claude session

## Expected Outputs

The ECLAIR Review phase must include:
- Diff between template and instance for each changed file
- User approval before syncing changes to instance
- Documentation in EVOLUTION_LOG.md
"
)
```

---

## ECLAIR Phase Guidance for Evolutions

### Phase 1 (Explore) - Evolution-Specific Focus

Explorer agents should focus on:
- Existing GM-CDE structure and conventions
- Similar commands/skills/agents for pattern reference
- Integration points between components

### Phase 2 (Clarify) - Evolution-Specific Questions

Common clarification areas for evolutions:
- Scope: Which GM-CDE components affected?
- Breaking changes: Will this affect existing behavior?
- Instance sync: Automatic or require approval?

### Phase 3 (Learn) - Evolution-Specific Learnings

Brain bites should capture:
- GM-CDE architecture patterns
- Command/skill design conventions
- Successful evolution approaches

### Phase 4 (Architect) - Evolution-Specific Considerations

Architecture agents should consider:
- Template file organization
- Command flag conventions
- Agent invocation patterns
- State file formats

### Phase 5 (Implement) - Evolution-Specific Requirements

Implementation must:
1. Update template files in `$GMCC_REPO_PATH/gmcc_plugin_template/`
2. Track all modified files for instance sync
3. Preserve existing functionality unless explicitly changing it

### Phase 6 (Review) - Evolution-Specific Gates

Review must include:
1. Template changes review
2. Instance sync diff review
3. User approval gate
4. EVOLUTION_LOG entry

---

## Post-ECLAIR: Instance Sync

After ECLAIR completes, perform GM-CDE-specific sync:

### Generate Diffs

For each modified template file:

```bash
diff -u $GMCC_PLUGIN_ROOT/{file} $GMCC_PLUGIN_ROOT/green_mountain_template/{file}
```

### Present Diffs

Use AskUserQuestion:
```
Template changes complete via ECLAIR. Here are the diffs to apply to your instance:

**Files changed:** {count}

{For each file, show summary}
- {file}: +{additions} -{deletions}

Would you like to see the full diffs?
- Show full diffs - Display detailed changes
- Apply without review - Trust the changes (not recommended)
- Cancel - Keep template changes, skip instance sync
```

If "Show full diffs" selected, display each diff and then ask:
```
Apply these changes to your instance?
- Yes, apply all - Update instance files
- Apply selectively - Choose which files to sync
- Cancel - Keep template changes, skip instance sync
```

### Apply to Instance

For each approved file:
1. Read from `$GMCC_PLUGIN_ROOT/green_mountain_template/{file}`
2. Write to `$GMCC_PLUGIN_ROOT/{file}`

**Files to NEVER sync to instance:**
- `$GMCC_PLUGIN_ROOT/ckfs/` (runtime files, not template)
- `$GMCC_PLUGIN_ROOT/settings.local.json` (instance-specific)

---

## Post-ECLAIR: Document Evolution

### Create Evolution Log Entry

If `$GMCC_REPO_PATH/EVOLUTION_LOG.md` doesn't exist, create it:
```markdown
# GM-CDE Evolution Log

All evolutions to the GM-CDE template and instance are logged here.

---
```

Append new entry:
```markdown
## [Evolution {number}] - {TODAY}

### Description
{evolution description from user}

### ECLAIR Session
- Session Name: {session_name}
- State File: `$GMCC_FAM_PATH/ECLAIR_STATE_{session_name}.md`

### Changes
**Template:**
- {list of template files modified}

**Instance:**
- {list of instance files synced}

### Impact
- {what this evolution enables/changes}

### Breaking Changes
{list any breaking changes or "None"}

---
```

### Sync Status Report

Analyze what changed and report:

**If `commands/` changed:**
- Report: "Commands updated. Changes take effect immediately."

**If `agents/` changed:**
- Report: "Agents updated. Changes take effect immediately."

**If `skills/gmcc/SKILL.md` changed:**
- **CRITICAL**: Warn user to restart Claude session
- Report: "SKILL.md updated. Restart your Claude session for changes to take effect."

**If `skills/gmcc_macro*/` changed:**
- Report: "Macro skills updated. Changes take effect immediately."

**If `props/env.md` changed:**
- Report: "Properties updated. Changes take effect immediately."

**If `ckfs_templates/` changed:**
- Report: "FAM templates updated. Changes will apply to future /gm_init and /gm_load_branch calls."

**If `scripts/` or `hooks/` changed:**
- Report: "Scripts/hooks updated. Verify hook configuration if needed."

### Final Report

**Write state:** `{"task": "none", "state": "idle"}` to `$GMCC_PLUGIN_ROOT/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Evolution Complete: {description}

**ECLAIR Session:** {session_name}

**Template Updated:**
- {count} files in $GMCC_PLUGIN_ROOT/green_mountain_template/

**Instance Synced:**
- {count} files in $GMCC_PLUGIN_ROOT/

**Logged:**
- EVOLUTION_LOG.md updated
- ECLAIR state preserved

{Any warnings about restart needed}

**Next Steps:**
- {if SKILL.md changed: "Restart Claude session"}
- Test the evolution with a simple use case
- Run /gm_fam_sync to update FAM
```

---

## Error Handling

**Template file not found:**
```
[GMB] Error: Template file not found

Expected: $GMCC_PLUGIN_ROOT/green_mountain_template/{file}

The template may be incomplete. Check your GM-CDE installation.
```

**Write permission denied:**
```
[GMB] Error: Cannot write to {file}

Check file permissions and try again.
```

**ECLAIR session failure:**
```
[GMB] ECLAIR session failed at phase {N}

State preserved at: $GMCC_FAM_PATH/ECLAIR_STATE_{session_name}.md

To resume: /gm_evolve --resume {session_name}
```

**User cancels mid-evolution:**
```
[GMB] Evolution cancelled

Template changes have been made but instance was not synced.
To complete the sync later, run:
/gm_evolve --instance-only

Or to revert template changes:
git checkout $GMCC_PLUGIN_ROOT/green_mountain_template/
```

---

## Flags

**--template-only**: Only update template, skip instance sync
**--instance-only**: Only sync instance from existing template changes
**--resume {session_name}**: Resume a paused ECLAIR evolution session
**--skip-approval**: Apply instance sync without showing diffs (use with caution)
