#!/bin/bash

# GM-CDE Repository Detection Script — v16.3.0
#
# Runs on SessionStart. When inside a git repository, this script:
#   1. Resolves the active project (= git repo dir basename)
#   2. Resolves the active instance (= unique filesystem path to this checkout)
#   3. Resolves the active session (= current git branch)
#   4. Ensures the session's physical artifact home exists
#      ($GMCC_SESSION_PATH/prompts/)
#   5. Delegates all row creation to `gm context ensure` (daemon db —
#      warn-and-continue if the daemon/binary is unavailable)
#   6. Exports all GMCC_* env vars via $CLAUDE_ENV_FILE
#
# v16: the runtime yamls are RETIRED. No template copies, no registry
# appends, no kbite seeding in bash — project/instance/session rows live in
# ~/gmcc/gmcc.db, created idempotently by `gm context ensure` (which derives
# the SAME instance code / branch slug as this script — the two
# implementations must stay in lockstep).
#
# Kbite registries are db-native: seeding happens db-side at row-create time
# (gm context ensure), with no yaml fallback on this path. The only remaining
# yaml `kbite:` reads live in `gm context ensure --from-ckfs` (legacy import).
#
# Anything outside a git repo: silent exit with no GMCC vars set.

# --- 0. Git-repo guard ------------------------------------------------------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# --- 1. Resolve plugin root from this script's location ---------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# --- 2. Stable paths --------------------------------------------------------
GMCC_CKFS_ROOT="$HOME/gmcc_ckfs"
GMCC_PROJECTS="$GMCC_CKFS_ROOT/projects"

# --- 3. Per-session identifiers ---------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
PROJECT_NAME=$(basename "$REPO_ROOT")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Slugify: replace each / with __ (used for branch sanitization).
# Use sed (not tr) — tr is char-to-char and would collapse / into a single _.
slugify() { echo "$1" | sed 's|/|__|g'; }

# Portable 4-char hex hash of the input string. Used to disambiguate
# instances of the same repo basename checked out at different abs paths.
# MUST match GitContext's derivation in the gm CLI (Swift).
hash4() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | cut -c1-4
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5 | cut -c1-4
    else
        # POSIX-ish fallback: cksum is universal but not crypto. 4 chars
        # of its hex output is good enough as a uniqueness suffix.
        printf '%s' "$1" | cksum | awk '{printf "%04x", $1}' | cut -c1-4
    fi
}

# Instance code = {repo_basename}_{4-char hash of abs path}.
# Machine-safe, collision-resistant, deterministic from $REPO_ROOT.
INSTANCE_ID="${PROJECT_NAME}_$(hash4 "$REPO_ROOT")"
SESSION_BRANCH=$(slugify "$BRANCH")

# --- 4. Resolved paths ------------------------------------------------------
GMCC_PROJECT_PATH="$GMCC_PROJECTS/$PROJECT_NAME"
GMCC_INSTANCE_PATH="$GMCC_PROJECT_PATH/instances/$INSTANCE_ID"
GMCC_SESSION_PATH="$GMCC_INSTANCE_PATH/sessions/$SESSION_BRANCH"

# --- 5. Ensure artifact home + db rows ---------------------------------------
# The prompt folders under prompts/ hold ONLY memory/*.md artifacts; all
# session/prompt data lives in the daemon db.
mkdir -p "$GMCC_SESSION_PATH/prompts"

# Delegate row creation to the daemon. Best-effort: never block env export.
GM_BIN="$HOME/gmcc/bin/gm"
if [ -x "$GM_BIN" ]; then
    if ! (cd "$REPO_ROOT" && "$GM_BIN" context ensure >/dev/null 2>&1); then
        echo "[GMB] daemon unavailable — context not ensured (run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' or /gmcc_daemon, then 'gm context ensure')"
    fi
else
    echo "[GMB] gm binary missing at $GM_BIN — run 'bash $GMCC_PLUGIN_DIR/scripts/build_daemon.sh' to build, then 'gm context ensure'"
fi

# Print the gm command cheatsheet into hook stdout so every gmcc session
# starts with the exact verb surface in context. Silent skip when missing.
if [ -x "$GM_BIN" ]; then
    "$GM_BIN" cheatsheet 2>/dev/null || true
fi

# --- 6. Export to $CLAUDE_ENV_FILE -----------------------------------------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    {
        echo "GMCC_CKFS_ROOT=$GMCC_CKFS_ROOT"
        echo "GMCC_PROJECTS=$GMCC_PROJECTS"
        echo "GMCC_PROJECT_PATH=$GMCC_PROJECT_PATH"
        echo "GMCC_INSTANCE_PATH=$GMCC_INSTANCE_PATH"
        echo "GMCC_SESSION_PATH=$GMCC_SESSION_PATH"
        echo "GMCC_KBITE=$GMCC_CKFS_ROOT/kbites"
        echo "GMCC_KBITE_DIGESTED=$GMCC_CKFS_ROOT/kbites/digested"
        echo "GMCC_KBITE_OPEN=$GMCC_CKFS_ROOT/kbites/open"
        # Plugin root, derived from this script's location.
        echo "GMCC_PLUGIN_ROOT=$GMCC_PLUGIN_DIR"
        # Boot completion signal.
        echo "GMCC_BOOTED=1"
    } >> "$CLAUDE_ENV_FILE"
fi

exit 0
