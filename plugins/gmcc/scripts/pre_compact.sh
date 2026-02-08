#!/bin/bash

# [FIX #10] PreCompact hook - preserve GMCC state before context compaction
# Writes current state to a compact_recovery.md mem file in the FAM so that
# after compaction, Claude can re-read GMCC context efficiently.
# The additionalContext output instructs Claude what to reload.

GMCC_FAM_PATH="${GMCC_FAM_PATH:-}"
if [ -z "$GMCC_FAM_PATH" ] || [ ! -d "$GMCC_FAM_PATH" ]; then
    exit 0
fi

# Read current GMB runtime state
STATE_FILE=".claude/GMB_STATE.json"
STATE="idle"
TASK="none"
TASK_NAME=""
if [ -f "$STATE_FILE" ]; then
    STATE=$(grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    TASK=$(grep -o '"task"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    TASK_NAME=$(grep -o '"taskName"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
    STATE=${STATE:-"idle"}
    TASK=${TASK:-"none"}
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PLUGIN_ROOT="${GMCC_PLUGIN_ROOT:-unknown}"

# Find active memory set if in a bot workflow
ACTIVE_MEM=""
if [ -d "$GMCC_FAM_PATH/thoughts" ]; then
    ACTIVE_MEM=$(ls -d "$GMCC_FAM_PATH/thoughts"/mem_*/ 2>/dev/null | while read -r d; do
        if [ -f "$d/session_meta.md" ]; then
            if grep -q "Status.*active" "$d/session_meta.md" 2>/dev/null; then
                echo "$d"
            fi
        fi
    done | tail -1)
fi

# Write compact recovery file to FAM
cat > "$GMCC_FAM_PATH/compact_recovery.md" << EOF
# GMCC Compact Recovery

**Written**: $TIMESTAMP
**Branch**: $BRANCH
**Task**: ${TASK}
**State**: ${STATE}
**Task Name**: ${TASK_NAME:-none}
**Plugin Root**: $PLUGIN_ROOT
**FAM Path**: $GMCC_FAM_PATH
**Active Memory Set**: ${ACTIVE_MEM:-none}

## Recovery Instructions

After context compaction, you MUST reload GMCC context:

1. **Re-read the GMCC skill** for core GM-CDE rules
2. **Re-read FAM context**:
   - $GMCC_FAM_PATH/Purpose.md
   - $GMCC_FAM_PATH/Tasks.md
3. **Re-read Famalouge** for session history:
   - $GMCC_FAM_PATH/Famalouge.md
4. **If in a bot workflow** (task=$TASK, state=$STATE):
   - Read active memory set: ${ACTIVE_MEM:-"check thoughts/ for mem_* dirs"}
   - Read session_meta.md in the memory set for phase history
5. **Check kbite triggers** for the current task context

## State at Compaction Time
- GMB was in state: **$STATE** working on task: **$TASK**
- Branch: **$BRANCH**
EOF

# Output additionalContext - this is shown to Claude after compaction
# [FIX #10] This instructs Claude to reload GMCC context after compaction
cat << EOF
[GMB] Context compacted. GMCC state preserved.

RELOAD REQUIRED: Read $GMCC_FAM_PATH/compact_recovery.md for full recovery instructions.
Quick summary: Branch=$BRANCH, Task=${TASK}, State=${STATE}. Re-read GMCC skill, FAM Purpose.md, Tasks.md, and Famalouge.md to restore context.
EOF

exit 0
