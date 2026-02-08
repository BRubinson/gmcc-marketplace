#!/bin/bash

# GM-CDE Repository Detection Script
# Runs on SessionStart to detect git repository and set environment variables
# These variables are used by all GMCC commands for path resolution
#
# [FIX #14] This intentionally runs on SessionStart (not Setup) because
# the active git branch can change between sessions in the same project.
# SessionStart ensures env vars always reflect current git state.

# Only proceed if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    # Not in a git repo - no GMCC env vars to set
    exit 0
fi

# [FIX #1] Resolve plugin root from this script's location
# ${CLAUDE_PLUGIN_ROOT} is resolved by Claude Code in hook command strings
# but is NOT available as a persistent session env var. We derive it from
# this script's path: plugins/gmcc/scripts/detect_repo.sh -> parent of scripts/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Get repository information
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
REPO_ID=$(basename "$REPO_ROOT")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Sanitize branch name for filesystem (replace / with __)
SANITIZED_BRANCH=$(echo "$BRANCH" | tr '/' '__')

# Define GMCC paths
GMCC_CKFS_ROOT="$HOME/gmcc_ckfs"
GMCC_REPO_PATH="$GMCC_CKFS_ROOT/$REPO_ID"
GMCC_FAM_PATH="$GMCC_REPO_PATH/fam/$SANITIZED_BRANCH"

# Export environment variables via CLAUDE_ENV_FILE
# This is the required mechanism for SessionStart hooks to set env vars
if [ -n "$CLAUDE_ENV_FILE" ]; then
    {
        echo "GMCC_CKFS_ROOT=$GMCC_CKFS_ROOT"
        echo "GMCC_REPO_ID=$REPO_ID"
        echo "GMCC_ACTIVE_BRANCH=$BRANCH"
        echo "GMCC_FAM_PATH=$GMCC_FAM_PATH"
        echo "GMCC_REPO_PATH=$GMCC_REPO_PATH"
        # Signal successful GMCC boot - commands check this to validate environment
        echo "GMCC_BOOTED=1"
        # [FIX #1] Export resolved plugin root for use by commands and agents
        echo "GMCC_PLUGIN_ROOT=$GMCC_PLUGIN_DIR"
    } >> "$CLAUDE_ENV_FILE"
fi

exit 0
