#!/bin/bash

# GM-CDE Status Line Script
# Reads GMB runtime state and outputs status for Claude Code status line
# Supports ECLAIR phase progress display
#
# Uses environment variables set by SessionStart hook:
# - GMCC_FAM_PATH: Path to current branch FAM
# - GMCC_REPO_PATH: Path to repo CKFS

# State file is now in project's .claude/ directory (not CKFS)
STATE_FILE=".claude/GMB_STATE.json"

# Check if state file exists (GM-CDE initialized for this repo)
if [ ! -f "$STATE_FILE" ]; then
    echo "[GMB] not initialized"
    exit 0
fi

# Get current git branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "?")

# Read runtime state from JSON file
if [ -f "$STATE_FILE" ]; then
    # Extract state fields using simple grep/sed (no jq dependency)
    STATE=$(grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    TASK=$(grep -o '"task"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    MACRO=$(grep -o '"macro"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    PHASE_NUM=$(grep -o '"phase"[[:space:]]*:[[:space:]]*[0-9]*' "$STATE_FILE" | sed 's/.*:[[:space:]]*\([0-9]*\)/\1/' | head -1)
    MODE=$(grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)

    # Default to idle if empty
    STATE=${STATE:-"idle"}
    TASK=${TASK:-""}
    MACRO=${MACRO:-""}
    PHASE_NUM=${PHASE_NUM:-"0"}
    MODE=${MODE:-"full"}
else
    STATE="idle"
    TASK=""
    MACRO=""
    PHASE_NUM="0"
    MODE="full"
fi

# Determine FAM directory - prefer env var, fallback to constructed path
if [ -n "$GMCC_FAM_PATH" ] && [ -d "$GMCC_FAM_PATH" ]; then
    FAM_DIR="$GMCC_FAM_PATH"
elif [ -n "$GMCC_REPO_PATH" ]; then
    # Construct from repo path
    SANITIZED_BRANCH=$(echo "$BRANCH" | tr '/' '__')
    FAM_DIR="$GMCC_REPO_PATH/fam/$SANITIZED_BRANCH"
else
    # Legacy fallback (should not reach here with proper setup)
    SANITIZED_BRANCH=$(echo "$BRANCH" | tr '/' '__')
    FAM_DIR="$HOME/gmcc_ckfs/$(basename $(git rev-parse --show-toplevel 2>/dev/null))/fam/$SANITIZED_BRANCH"
fi

# Count incomplete tasks from FAM
if [ -d "$FAM_DIR" ] && [ -f "$FAM_DIR/Tasks.md" ]; then
    INCOMPLETE=$(grep -c '\- \[ \]' "$FAM_DIR/Tasks.md" 2>/dev/null || echo "0")
    if [ "$INCOMPLETE" = "0" ]; then
        TASKS_INFO="done"
    else
        TASKS_INFO="${INCOMPLETE} tasks"
    fi
else
    TASKS_INFO="no FAM"
fi

# Build status line based on macro type
if [ "$MACRO" = "eclair" ]; then
    # ECLAIR-specific status format: [GMB] branch | ECLAIR N/6: phase | tasks

    # Map phase number to phase name
    case $PHASE_NUM in
        1) PHASE_LABEL="explore" ;;
        2) PHASE_LABEL="clarify" ;;
        3) PHASE_LABEL="learn" ;;
        4) PHASE_LABEL="architect" ;;
        5) PHASE_LABEL="implement" ;;
        6) PHASE_LABEL="review" ;;
        0) PHASE_LABEL="init" ;;
        *) PHASE_LABEL="unknown" ;;
    esac

    # Add mode indicator for LITE mode
    if [ "$MODE" = "lite" ]; then
        MODE_INDICATOR=" (lite)"
    else
        MODE_INDICATOR=""
    fi

    echo "[GMB] $BRANCH | ECLAIR $PHASE_NUM/6: $PHASE_LABEL$MODE_INDICATOR | $TASKS_INFO"
else
    # Non-ECLAIR state - use standard format
    # Format: [GMB] branch | state | tasks
    if [ -n "$TASK" ] && [ "$TASK" != "none" ]; then
        # Show task name when active
        echo "[GMB] $BRANCH | $STATE: $TASK | $TASKS_INFO"
    else
        # Just show state when no specific task
        echo "[GMB] $BRANCH | $STATE | $TASKS_INFO"
    fi
fi
