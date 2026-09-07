#!/bin/bash

# GM-CDE SessionStart bootstrap. Three jobs only: confirm we're in a git
# repo, find the plugin root, and find the right gm binary. Everything else
# — identity, paths, env emission, the artifact home, dope boot sync, the
# cheatsheet — is owned by the gm binary (`gm context ensure` +
# `gm context env`). This script computes NOTHING the daemon computes.
#
# Anything outside a git repo: silent exit with no GMCC vars set.

# --- 0. Git-repo guard ------------------------------------------------------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# --- 1. Plugin root from this script's location -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- 2. Sandbox marker ------------------------------------------------------
# A snapshot repo copy carries .gmcc_sandbox at its root. PARSED as data,
# never sourced — a repo file must not get shell execution at SessionStart.
# GMCC_ROOT selects the runtime (binaries + db); GMCC_CKFS_ROOT is the
# daemon-down fallback claim `gm context env` checks against the db.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.gmcc_sandbox" ]; then
    _sb_root=$(sed -n 's/^export GMCC_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
    _sb_ckfs=$(sed -n 's/^export GMCC_CKFS_ROOT="\(.*\)"$/\1/p' "$REPO_ROOT/.gmcc_sandbox" | head -1)
    [ -n "$_sb_root" ] && export GMCC_ROOT="$_sb_root"
    [ -n "$_sb_ckfs" ] && export GMCC_CKFS_ROOT="$_sb_ckfs"
fi

# --- 3. Locate gm -----------------------------------------------------------
GM_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin/gm"
if [ ! -x "$GM_BIN" ]; then
    echo "[GMB] gm binary missing at $GM_BIN — run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' to build, then restart the session"
    exit 0
fi

# --- 4. Rows + artifact home + dope boot sync (stderr = notices) ------------
warnings=$( (cd "$REPO_ROOT" && "$GM_BIN" context ensure >/dev/null) 2>&1 )
if [ $? -ne 0 ]; then
    warnings="$warnings
[GMB] daemon unavailable — context not ensured (run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' or /gmcc_daemon, then 'gm context ensure')"
fi

# --- 5. Cheatsheet into hook stdout (automatic; the agent never runs it) ----
"$GM_BIN" cheatsheet 2>/dev/null || true

# --- 6. Env contract → $CLAUDE_ENV_FILE (stdout), warnings → context --------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    warnings="$warnings
$( (cd "$REPO_ROOT" && "$GM_BIN" context env --plugin-root "$GMCC_PLUGIN_DIR") 2>&1 >> "$CLAUDE_ENV_FILE" )"
fi

if [ -n "$(printf '%s' "$warnings" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$warnings"
fi

exit 0
