---
name: gm_evolve
description: Evolve GM-CDE by updating the shared template and syncing to the live plugin using the ECLAIR macro workflow. High-accuracy evolution with exploration, clarification, learning, architecture, implementation, and review.
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

**Write state:** `{"task": "gm-evolve", "state": "initializing"}` to `.claude/GMB_STATE.json` (in the project directory)

---

## Key Paths

- **Template (edit here first):** `~/gmcc_ckfs/gmcc_plugin_template/`
- **Live Plugin (sync to here):** `${CLAUDE_PLUGIN_ROOT}` (set by Claude for marketplace plugins)
- **Fallback live plugin search:**
  - `~/.claude/plugins/cache/gmcc-marketplace/gmcc/*/` (marketplace install)
  - `~/.claude/plugins/gmcc/` (manual install)

The template is SHARED across all repositories at the system level.

---

## Pre-Flight Checks

1. Verify template exists at `~/gmcc_ckfs/gmcc_plugin_template/`
2. Determine live plugin path (for syncing after changes)
3. Get current git branch

### Determine Live Plugin Path

```bash
# Find live plugin location
if [ -n "${CLAUDE_PLUGIN_ROOT}" ]; then
    LIVE_PLUGIN="${CLAUDE_PLUGIN_ROOT}"
elif [ -d "$HOME/.claude/plugins/cache/gmcc-marketplace/gmcc" ]; then
    LIVE_PLUGIN=$(ls -d "$HOME/.claude/plugins/cache/gmcc-marketplace/gmcc"/*/ 2>/dev/null | sort -V | tail -1)
elif [ -d "$HOME/.claude/plugins/gmcc" ]; then
    LIVE_PLUGIN="$HOME/.claude/plugins/gmcc"
fi
```

### If Template Missing
```
[GMB] Template not found at ~/gmcc_ckfs/gmcc_plugin_template/

The shared GM-CDE template directory is required for evolution.
Run /gm_init to create it, or manually copy:
cp -r <plugin_path>/* ~/gmcc_ckfs/gmcc_plugin_template/
```
Exit without changes.

### If Live Plugin Not Found
```
[GMB] Warning: Live plugin not found

Cannot determine live plugin location for syncing.
Template evolution will proceed, but you'll need to manually sync changes.

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
- Skills: `~/gmcc_ckfs/gmcc_plugin_template/skills/`
- Commands: `~/gmcc_ckfs/gmcc_plugin_template/commands/`
- Agents: `~/gmcc_ckfs/gmcc_plugin_template/agents/`
- Macros: `~/gmcc_ckfs/gmcc_plugin_template/skills/gmcc_macro*/`
- FAM Templates: `~/gmcc_ckfs/gmcc_plugin_template/ckfs_templates/`
- Scripts: `~/gmcc_ckfs/gmcc_plugin_template/scripts/`
- Hooks: `~/gmcc_ckfs/gmcc_plugin_template/hooks/`

## Critical Rules for GM-CDE Evolution

1. **Template First**: Always update `~/gmcc_ckfs/gmcc_plugin_template/` FIRST - this is the source of truth
2. **Instance Sync**: After template changes, sync to live plugin at `${CLAUDE_PLUGIN_ROOT}` (or detected path)
3. **Never Sync These**:
   - `~/gmcc_ckfs/{repo}/` directories (runtime FAM files)
   - Instance-specific settings
4. **Skill Changes**: If `skills/gmcc/SKILL.md` is modified, user must restart Claude session

## Expected Outputs

The ECLAIR Review phase must include:
- Diff between template and live plugin for each changed file
- User approval before syncing changes to live plugin
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
1. Update template files in `~/gmcc_ckfs/gmcc_plugin_template/`
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
diff -u "${LIVE_PLUGIN}/{file}" ~/gmcc_ckfs/gmcc_plugin_template/{file}
```

### Present Diffs

Use AskUserQuestion:
```
Template changes complete via ECLAIR. Here are the diffs to apply to your live plugin:

**Template:** ~/gmcc_ckfs/gmcc_plugin_template/
**Live Plugin:** {LIVE_PLUGIN path}

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
Apply these changes to your live plugin?
- Yes, apply all - Update live plugin files
- Apply selectively - Choose which files to sync
- Cancel - Keep template changes, skip instance sync
```

### Apply to Live Plugin

For each approved file:
1. Read from `~/gmcc_ckfs/gmcc_plugin_template/{file}`
2. Write to `${LIVE_PLUGIN}/{file}`

**Files to NEVER sync:**
- `~/gmcc_ckfs/{repo}/` directories (runtime FAM files)
- Any `.claude/` project-specific files

---

## Post-ECLAIR: Document Evolution

### Create Evolution Log Entry

Log the evolution in `~/gmcc_ckfs/{current_repo}/EVOLUTION_LOG.md`:

If it doesn't exist, create it:
```markdown
# GM-CDE Evolution Log

All evolutions to the GM-CDE template are logged here.
Evolution changes apply to the shared template at ~/gmcc_ckfs/gmcc_plugin_template/

---
```

Append new entry:
```markdown
## [Evolution {number}] - {TODAY}

### Description
{evolution description from user}

### ECLAIR Session
- Session Name: {session_name}
- Initiated from repo: {GMCC_REPO_ID}

### Changes
**Template (~/gmcc_ckfs/gmcc_plugin_template/):**
- {list of template files modified}

**Live Plugin ({LIVE_PLUGIN}):**
- {list of live plugin files synced}

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

**If `ckfs_templates/` changed:**
- Report: "FAM templates updated. Changes will apply to future /gm_init and /gm_load_branch calls."

**If `scripts/` or `hooks/` changed:**
- Report: "Scripts/hooks updated. Verify hook configuration if needed."

### Final Report

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Evolution Complete: {description}

**ECLAIR Session:** {session_name}

**Template Updated:**
- {count} files in ~/gmcc_ckfs/gmcc_plugin_template/

**Live Plugin Synced:**
- {count} files in {LIVE_PLUGIN}

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

Expected: ~/gmcc_ckfs/gmcc_plugin_template/{file}

The template may be incomplete. Run /gm_init --force to repopulate.
```

**Write permission denied:**
```
[GMB] Error: Cannot write to {file}

Check file permissions and try again.
```

**ECLAIR session failure:**
```
[GMB] ECLAIR session failed at phase {N}

State preserved at: {FAM_PATH}/ECLAIR_STATE_{session_name}.md

To resume: /gm_evolve --resume {session_name}
```

**User cancels mid-evolution:**
```
[GMB] Evolution cancelled

Template changes have been made but live plugin was not synced.
To complete the sync later, run:
/gm_evolve --instance-only

Or to revert template changes:
git checkout ~/gmcc_ckfs/gmcc_plugin_template/
```

---

## Flags

**--template-only**: Only update template, skip live plugin sync
**--instance-only**: Only sync live plugin from existing template changes
**--resume {session_name}**: Resume a paused ECLAIR evolution session
**--skip-approval**: Apply live plugin sync without showing diffs (use with caution)
