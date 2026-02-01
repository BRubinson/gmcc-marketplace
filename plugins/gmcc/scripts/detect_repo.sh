#!/bin/bash

# GM-CDE Repository Detection Script
# Runs on SessionStart to detect git repository and set environment variables
# These variables are used by all GMCC commands for path resolution

# Only proceed if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    # Not in a git repo - no GMCC env vars to set
    exit 0
fi

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
        # Note: CLAUDE_PLUGIN_ROOT is set by Claude itself for marketplace plugins
        # We don't override it here - Claude knows where the plugin is installed
        # Commands will use ${CLAUDE_PLUGIN_ROOT} directly or fall back to searching
        # common locations (marketplace cache, manual install path)
    } >> "$CLAUDE_ENV_FILE"
fi

exit 0
