---
name: gmcc_boot
description: GMCC boot validation system. Automatically initializes GMCC environment on SessionStart. Invoke directly for boot diagnostics and troubleshooting.
user-invocable: true
allowed-tools: Bash, Read
---

# GMCC Boot System

The GMCC boot system runs automatically on SessionStart via the `detect_repo.sh` hook.

## Boot Sequence

When Claude Code starts a session:

1. **SessionStart hook fires** (defined in `hooks.json`)
2. **detect_repo.sh executes**
   - Detects if in a git repository
   - If not in git repo: exits silently (no GMCC vars set)
   - If in git repo: sets all GMCC environment variables
3. **Environment variables written to `$CLAUDE_ENV_FILE`**:
   - `GMCC_CKFS_ROOT` - Base path for CKFS data (`~/gmcc_ckfs`)
   - `GMCC_REPO_ID` - Repository identifier (directory name)
   - `GMCC_ACTIVE_BRANCH` - Current git branch
   - `GMCC_FAM_PATH` - Active branch FAM directory
   - `GMCC_REPO_PATH` - Repo-level CKFS directory
   - `GMCC_BOOTED=1` - **Boot completion signal**

## Boot Validation for Commands

All `gm_` commands MUST validate boot state before execution.

### Pre-Flight Boot Check Pattern

Add this check at the start of every command's Pre-Flight section:

```markdown
## Pre-Flight

**Boot Validation**:
Check if GMCC environment is ready:

If `$GMCC_BOOTED` is not set or empty:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. This happens when:
1. You are not in a git repository, OR
2. The SessionStart hook did not run (session started elsewhere)

To fix:
- Ensure you are in a git repository
- Restart Claude Code to trigger the SessionStart hook

Run /gmcc_boot for diagnostics.
```
Exit without proceeding.

If `$GMCC_BOOTED` is set: Continue with remaining pre-flight checks.
```

### Exception: Init Commands

The following commands should NOT check `GMCC_BOOTED`:
- `/gm_init` - Initializes the system (runs before boot is possible)
- `/gm_repo_init` - Initializes a repository (may run in partially-booted state)

These commands have their own validation logic.

---

## Diagnostics (When Invoked Directly)

When a user invokes `/gmcc_boot` directly, run diagnostics:

### Step 1: Display Environment State

```bash
echo "=== GMCC Boot Diagnostics ==="
echo ""
echo "Boot Status:"
echo "  GMCC_BOOTED: ${GMCC_BOOTED:-NOT SET}"
echo ""
echo "Environment Variables:"
echo "  GMCC_CKFS_ROOT: ${GMCC_CKFS_ROOT:-NOT SET}"
echo "  GMCC_REPO_ID: ${GMCC_REPO_ID:-NOT SET}"
echo "  GMCC_ACTIVE_BRANCH: ${GMCC_ACTIVE_BRANCH:-NOT SET}"
echo "  GMCC_FAM_PATH: ${GMCC_FAM_PATH:-NOT SET}"
echo "  GMCC_REPO_PATH: ${GMCC_REPO_PATH:-NOT SET}"
echo "  CLAUDE_PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT:-NOT SET}"
echo ""
```

### Step 2: Check Prerequisites

```bash
echo "Prerequisites:"
echo "  Git repository: $(git rev-parse --git-dir > /dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "  System initialized: $([ -d "$HOME/gmcc_ckfs" ] && echo 'YES' || echo 'NO')"
echo "  Repo initialized: $([ -d "$GMCC_REPO_PATH" ] && echo 'YES - '$GMCC_REPO_PATH || echo 'NO')"
echo "  FAM exists: $([ -d "$GMCC_FAM_PATH" ] && echo 'YES' || echo 'NO')"
echo ""
```

### Step 3: Provide Guidance

Based on diagnostics, provide guidance:

**If GMCC_BOOTED is NOT SET**:
```
Issue: GMCC boot did not complete.

Most likely causes:
1. Not in a git repository - navigate to a git repo and restart Claude Code
2. Session started in a non-git directory - restart Claude Code from within a git repo
3. Plugin not installed correctly - verify GMCC plugin is enabled

To fix: Restart Claude Code from within a git repository.
```

**If GMCC_BOOTED is SET but system not initialized**:
```
Issue: GMCC system not initialized.

Run /gm_init to create the system-level ~/gmcc_ckfs/ directory.
```

**If GMCC_BOOTED is SET but repo not initialized**:
```
Issue: This repository is not initialized for GM-CDE.

Run /gm_repo_init to initialize this repository.
```

**If all checks pass**:
```
GMCC boot status: READY

All systems operational. You can run any gm_ command.
```

---

## Manual Boot (Emergency Fallback)

If the SessionStart hook fails to run, you can manually trigger boot by sourcing the detection script:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/detect_repo.sh"
```

**Note**: This is a fallback for debugging. Normal boot should happen automatically.

---

## Troubleshooting

### "GMCC not booted" error when running commands

1. **Check if in git repo**: Run `git status` - if it fails, you're not in a git repository
2. **Restart Claude Code**: The SessionStart hook only runs on session start
3. **Verify plugin installed**: Check `~/.claude/settings.json` includes `gmcc@gmcc-marketplace`

### Environment variables partially set

This usually means the SessionStart hook ran but there was a problem:
- Check `detect_repo.sh` script for errors
- Verify git repository is accessible
- Run `/gmcc_boot` for full diagnostics

### Boot works but FAM missing

Boot only sets environment variables - it doesn't create CKFS structure:
1. Run `/gm_init` (once per machine)
2. Run `/gm_repo_init` (once per repository)
3. Run `/gm_load_branch` (to create FAM for current branch)
