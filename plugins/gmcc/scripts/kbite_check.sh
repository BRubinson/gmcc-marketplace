#!/bin/bash
# kbite_check.sh - Check user prompt against cached kbite triggers
# Called by UserPromptSubmit hook to identify matching kbites

# Read hook input from stdin (JSON)
INPUT=$(cat)

# Extract user prompt from hook input
# Hook input format: {"session_id": "...", "prompt": "...", ...}
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    # No prompt to check
    exit 0
fi

CACHE_FILE="${GMCC_TRIGGERS_CACHE:-}"
CKFS_ROOT="${GMCC_CKFS_ROOT:-}"

# Skip if no cache or CKFS
if [ -z "$CACHE_FILE" ] || [ ! -f "$CACHE_FILE" ]; then
    exit 0
fi

if [ -z "$CKFS_ROOT" ]; then
    exit 0
fi

# Convert prompt to lowercase for matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Check each cached trigger
MATCHED_KBITES=""
while IFS=: read -r kbite trigger; do
    if [ -z "$kbite" ] || [ -z "$trigger" ]; then
        continue
    fi

    trigger_lower=$(echo "$trigger" | tr '[:upper:]' '[:lower:]')

    # Check if trigger appears in prompt (word boundary matching)
    if echo "$PROMPT_LOWER" | grep -qiw "$trigger_lower" 2>/dev/null; then
        # Add to matched list (deduplicate)
        if [[ ! "$MATCHED_KBITES" =~ (^|,)"$kbite"(,|$) ]]; then
            if [ -n "$MATCHED_KBITES" ]; then
                MATCHED_KBITES="$MATCHED_KBITES,$kbite"
            else
                MATCHED_KBITES="$kbite"
            fi
        fi
    fi
done < "$CACHE_FILE"

# If matches found, output context hint
if [ -n "$MATCHED_KBITES" ]; then
    echo "export GMCC_MATCHED_KBITES=\"$MATCHED_KBITES\""

    # Build paths to chewed files for matched kbites
    CHEWED_PATHS=""
    IFS=',' read -ra KBITES <<< "$MATCHED_KBITES"
    for kb in "${KBITES[@]}"; do
        chewed_dir="$CKFS_ROOT/kbites/$kb/chewed"
        if [ -d "$chewed_dir" ]; then
            if [ -n "$CHEWED_PATHS" ]; then
                CHEWED_PATHS="$CHEWED_PATHS:$chewed_dir"
            else
                CHEWED_PATHS="$chewed_dir"
            fi
        fi
    done

    if [ -n "$CHEWED_PATHS" ]; then
        echo "export GMCC_KBITE_CONTEXT=\"$CHEWED_PATHS\""
        echo "# KBite context available: $MATCHED_KBITES"
    fi
fi

exit 0
