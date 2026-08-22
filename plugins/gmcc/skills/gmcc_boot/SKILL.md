---
name: gmcc_boot
description: GMCC boot validation system. Automatically initializes GMCC environment on SessionStart. Invoke directly for boot diagnostics and troubleshooting.
user-invocable: true
allowed-tools: Bash, Read
---

# GMCC Boot System (v16.3.0)

The GMCC boot system runs automatically on SessionStart via the `detect_repo.sh` hook.

## Boot Sequence

When Claude Code starts a session:

1. **SessionStart hooks fire** (defined in `hooks.json`): `detect_repo.sh` then `check_daemon_stale.sh` (which warns when the daemon binaries are missing/stale).
2. **detect_repo.sh executes**
   - Detects if in a git repository
   - If not in git repo: exits silently (no GMCC vars set)
   - If in git repo: resolves project / instance / session for the current repo + branch, `mkdir -p`s `$GMCC_SESSION_PATH/prompts/` (the artifact home), best-effort calls `~/gmcc/bin/gm context ensure` to upsert the db rows (warns and continues if the daemon is unavailable), and sets all GMCC environment variables (including the boot signal `GMCC_BOOTED=1`)
3. **Environment variables written to `$CLAUDE_ENV_FILE`** — `detect_repo.sh` is the single source of truth for the full set. Read `${CLAUDE_PLUGIN_ROOT}/scripts/detect_repo.sh` directly for the authoritative export list. The diagnostics in this skill echo whatever is actually set at runtime.

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
echo "Environment Variables (all GMCC_* + CLAUDE_PLUGIN_ROOT):"
env | grep -E '^GMCC_' | sort | sed 's/^/  /'
echo "  CLAUDE_PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT:-NOT SET}"
echo ""
```

### Step 2: Check Prerequisites

```bash
echo "Prerequisites:"
echo "  Git repository: $(git rev-parse --git-dir > /dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "  Ckfs root: $([ -d "$HOME/gmcc_ckfs" ] && echo 'YES' || echo 'NO — run /gm_init')"
echo "  gm binary: $([ -x "$HOME/gmcc/bin/gm" ] && echo 'YES' || echo 'NO — run build_daemon.sh')"
echo "  Session artifact home: $([ -d "$GMCC_SESSION_PATH/prompts" ] && echo 'YES - '$GMCC_SESSION_PATH || echo 'NO')"
echo ""
echo "Daemon / DB:"
"$HOME/gmcc/bin/gm" ping 2>&1 | sed 's/^/  /'
"$HOME/gmcc/bin/gm" status 2>&1 | sed 's/^/  /'
echo ""
echo "Context rows (null uuids => rows not ensured):"
"$HOME/gmcc/bin/gm" context get --json 2>&1 | sed 's/^/  /'
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

**If the gm binary is missing or `gm ping` fails**:
```
Issue: daemon system unavailable.

Run: bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
Then: ~/gmcc/bin/gm setup && ~/gmcc/bin/gm context ensure
(See skills/gmcc_daemon/SKILL.md — self-heal rule.)
```

**If `gm context get` returns null uuids**:
```
Issue: db rows not ensured for this repo/branch.

Run: ~/gmcc/bin/gm context ensure
```

**If all checks pass**:
```
GMCC boot status: READY

Daemon reachable, db rows present. You can run any gm_ command.
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

### Boot works but gm calls fail

The env can boot fine while the daemon system is missing or stale:
1. Heed the `check_daemon_stale.sh` SessionStart warning — run `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`
2. `~/gmcc/bin/gm setup` creates `~/gmcc/` runtime dirs; `gm daemon status` / `/gmcc_daemon` for lifecycle
3. `gm context ensure` (idempotent) recreates missing db rows for the current repo/branch
