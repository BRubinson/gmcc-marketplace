#!/bin/bash

# [FIX #17] Stop hook - reset GMB runtime state when session ends
# Prevents stale state in GMB_STATE.json when sessions end mid-workflow.
# Without this, the status line would show an outdated task/state on next session.

STATE_FILE=".claude/GMB_STATE.json"
if [ -f "$STATE_FILE" ]; then
    echo '{"task": "none", "state": "idle"}' > "$STATE_FILE"
fi

exit 0
