#!/bin/bash
# eclair_stop_check.sh - Verify ECLAIR workflow state before stopping
# Part of GMCC v4 hook lifecycle
# Returns JSON: {"ok": true} to allow stop, {"ok": false, "reason": "..."} to block

# Read hook input from stdin
INPUT=$(cat)

# Parse stop_hook_active from input to prevent infinite loops
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' || true)

if [ -n "$STOP_HOOK_ACTIVE" ]; then
    # Already in a stop hook continuation - allow stop to prevent loops
    echo '{"ok": true}'
    exit 0
fi

# Check if ECLAIR session is active
if [ -z "$GMCC_ECLAIR_SESSION" ]; then
    # No ECLAIR session active, allow stop
    echo '{"ok": true}'
    exit 0
fi

# ECLAIR session active - check if we have state
if [ -n "$GMCC_FAM_PATH" ] && [ -f "$GMCC_FAM_PATH/ECLAIR_STATE_${GMCC_ECLAIR_SESSION}.md" ]; then
    # Check for incomplete phases in the state file
    INCOMPLETE=$(grep -c "Status: in_progress" "$GMCC_FAM_PATH/ECLAIR_STATE_${GMCC_ECLAIR_SESSION}.md" 2>/dev/null || echo "0")

    if [ "$INCOMPLETE" -gt 0 ]; then
        # ECLAIR has incomplete work - block stopping
        echo '{"ok": false, "reason": "ECLAIR session in progress with incomplete phases. Complete or save state before stopping."}'
        exit 0
    fi
fi

# ECLAIR session exists but no incomplete work found - allow stop
echo '{"ok": true}'
exit 0
