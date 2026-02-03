---
name: gm_evolve
description: Evolve GM-CDE by updating the plugin source in the gmcc-marketplace repo using the ECLAIR macro workflow. Must be called from within the gmcc-marketplace repository.
argument-hint: <evolution description>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task, AskUserQuestion
---

# GM-CDE Evolution Command (ECLAIR-Powered) - v3

You are evolving the GM-CDE system itself using the ECLAIR macro workflow for high-accuracy implementation.

**v3 Change**: This command now ONLY updates files in the gmcc-marketplace repository. It does NOT sync to installed/live plugins. The marketplace distribution system handles deployment.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: gm-evolve | STATE: initializing
```

**Write state:** `{"task": "gm-evolve", "state": "initializing"}` to `.claude/GMB_STATE.json` (in the project directory)

---

## Pre-Flight Checks

### 1. Verify in gmcc-marketplace Repository

**CRITICAL**: This command only works in the gmcc-marketplace repository.

Run this check:
```bash
# Check if in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "NOT_GIT_REPO"
    exit 1
fi

# Check if remote contains gmcc-marketplace
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if echo "$REMOTE_URL" | grep -q "gmcc-marketplace"; then
    echo "VALID_REPO"
else
    echo "WRONG_REPO"
fi
```

### If NOT in gmcc-marketplace Repository

```
[GMB] Error: Not in gmcc-marketplace repository

The /gm_evolve command can only be run from within the gmcc-marketplace repository.

Current remote: {remote_url or "no remote configured"}

To use this command:
1. Clone or navigate to the gmcc-marketplace repository
2. Run /gm_evolve from there

This restriction ensures evolution changes are tracked in the proper repository.
```

Exit without making any changes.

### 2. Get Repository Info

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
ACTIVE_BRANCH=$(git branch --show-current)
PLUGIN_PATH="${REPO_ROOT}/plugins/gmcc"
```

### 3. Verify Plugin Directory Exists

Check that `${REPO_ROOT}/plugins/gmcc/` exists.

If missing:
```
[GMB] Error: Plugin directory not found

Expected: {REPO_ROOT}/plugins/gmcc/

The gmcc plugin directory is missing from this repository.
Verify you're in the correct repository and branch.
```

Exit without changes.

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

This is a GM-CDE system evolution. All changes target the repository source:
- **Repository**: {REPO_ROOT}
- **Branch**: {ACTIVE_BRANCH}
- **Plugin Path**: {REPO_ROOT}/plugins/gmcc/

### Directories to Evolve
- Skills: `{REPO_ROOT}/plugins/gmcc/skills/`
- Commands: `{REPO_ROOT}/plugins/gmcc/commands/`
- Agents: `{REPO_ROOT}/plugins/gmcc/agents/`
- Macros: `{REPO_ROOT}/plugins/gmcc/skills/gmcc_macro*/`
- FAM Templates: `{REPO_ROOT}/plugins/gmcc/ckfs_templates/`
- Scripts: `{REPO_ROOT}/plugins/gmcc/scripts/`
- Hooks: `{REPO_ROOT}/plugins/gmcc/hooks/`

## Critical Rules for GM-CDE Evolution

1. **Repo Source Only**: All changes go to `{REPO_ROOT}/plugins/gmcc/` - this IS the source of truth
2. **No Live Sync**: Do NOT attempt to sync to installed plugins - the marketplace handles distribution
3. **Version Updates**: If making significant changes, update version in `.claude-plugin/plugin.json`
4. **Skill Changes**: If `skills/gmcc/SKILL.md` is modified, note that users must restart Claude session after re-installing

## Expected Outputs

The ECLAIR Review phase should verify:
- All changes are within `{REPO_ROOT}/plugins/gmcc/`
- No external paths are modified
- Changes follow existing patterns and conventions
"
)
```

---

## ECLAIR Phase Guidance for Evolutions

### Phase 1 (Explore) - Evolution-Specific Focus

Explorer agents should focus on:
- Existing GM-CDE structure within `plugins/gmcc/`
- Similar commands/skills/agents for pattern reference
- Integration points between components

### Phase 2 (Clarify) - Evolution-Specific Questions

Common clarification areas for evolutions:
- Scope: Which GM-CDE components affected?
- Breaking changes: Will this affect existing behavior?
- Version bump: Is this a patch, minor, or major change?

### Phase 3 (Learn) - Evolution-Specific Learnings

Brain bites should capture:
- GM-CDE architecture patterns
- Command/skill design conventions
- Successful evolution approaches

### Phase 4 (Architect) - Evolution-Specific Considerations

Architecture agents should consider:
- File organization within `plugins/gmcc/`
- Command flag conventions
- Agent invocation patterns
- State file formats

### Phase 5 (Implement) - Evolution-Specific Requirements

Implementation must:
1. Update files in `{REPO_ROOT}/plugins/gmcc/` only
2. Track all modified files for the report
3. Preserve existing functionality unless explicitly changing it

### Phase 6 (Review) - Evolution-Specific Gates

Review must verify:
1. All changes within repository bounds
2. No hardcoded paths to external locations
3. Patterns consistent with existing code

---

## Post-ECLAIR: Document Evolution

### Update Evolution Log

If `EVOLUTION_LOG.md` exists in `{REPO_ROOT}/plugins/gmcc/`, append to it.
If not, create it:

```markdown
# GM-CDE Evolution Log

All evolutions to the GM-CDE plugin are logged here.

---
```

Append new entry:
```markdown
## [Evolution {number}] - {TODAY}

### Description
{evolution description from user}

### ECLAIR Session
- Session Name: {session_name}
- Branch: {ACTIVE_BRANCH}

### Files Modified
{list of files modified in plugins/gmcc/}

### Impact
{what this evolution enables/changes}

### Breaking Changes
{list any breaking changes or "None"}

---
```

### Change Impact Report

Analyze what changed and report:

**If `commands/` changed:**
- Report: "Commands updated. Changes will take effect after plugin re-installation."

**If `agents/` changed:**
- Report: "Agents updated. Changes will take effect after plugin re-installation."

**If `skills/gmcc/SKILL.md` changed:**
- **CRITICAL**: Note that users must restart Claude session after re-installing
- Report: "SKILL.md updated. After re-installing the plugin, restart your Claude session."

**If `skills/gmcc_macro*/` changed:**
- Report: "Macro skills updated. Changes will take effect after plugin re-installation."

**If `ckfs_templates/` changed:**
- Report: "FAM templates updated. Changes will apply to future /gm_init and /gm_load_branch calls after re-installation."

**If `scripts/` or `hooks/` changed:**
- Report: "Scripts/hooks updated. Verify hook configuration after re-installation."

### Final Report

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Evolution Complete: {description}

**ECLAIR Session:** {session_name}

**Files Modified:**
- {count} files in {REPO_ROOT}/plugins/gmcc/

**Logged:**
- EVOLUTION_LOG.md updated (if present)
- ECLAIR state preserved

{Change impact notes}

**Next Steps:**
- Commit changes: git add -A && git commit -m "Evolution: {description}"
- Test locally or push to trigger marketplace update
- {if SKILL.md changed: "After re-installation, restart Claude session"}
```

---

## Error Handling

**Not in gmcc-marketplace repo:**
```
[GMB] Error: Not in gmcc-marketplace repository

The /gm_evolve command can only be run from within the gmcc-marketplace repository.
This ensures all GM-CDE evolution changes are properly tracked and versioned.

Current directory: {pwd}
```

**Plugin directory not found:**
```
[GMB] Error: Plugin directory not found

Expected: {REPO_ROOT}/plugins/gmcc/

Verify you're on the correct branch and the plugin structure exists.
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

Partial changes may have been made. To see what changed:
git status
git diff

To revert all changes:
git checkout .
```

---

## Flags

**--resume {session_name}**: Resume a paused ECLAIR evolution session

To resume an interrupted evolution:
1. Run `/gm_evolve --resume {session_name}`
2. The ECLAIR macro will reload state from `ECLAIR_STATE_{session_name}.md`
3. Continue from the last incomplete phase
