#!/bin/bash
# kbite_triggers_cache.sh - Cache kbite triggers on session start
# Called by SessionStart hook to build trigger cache for fast prompt matching

# Exit codes:
# 0 = success (stdout shown in verbose mode)
# 2 = blocking error (stderr shown to Claude)
# other = non-blocking error

CKFS_ROOT="${GMCC_CKFS_ROOT:-}"
CACHE_FILE="${GMCC_TRIGGERS_CACHE:-/tmp/gmcc_kbite_triggers_$$.cache}"

# Skip if no CKFS root
if [ -z "$CKFS_ROOT" ] || [ ! -d "$CKFS_ROOT" ]; then
    echo "GMCC_TRIGGERS_CACHE="
    exit 0
fi

KBITES_DIR="$CKFS_ROOT/kbites"

# Skip if no kbites directory
if [ ! -d "$KBITES_DIR" ]; then
    echo "GMCC_TRIGGERS_CACHE="
    exit 0
fi

# Build trigger cache
TRIGGERS=""
for kbite_dir in "$KBITES_DIR"/*/; do
    if [ -d "$kbite_dir" ]; then
        kbite_name=$(basename "$kbite_dir")
        triggers_file="$kbite_dir/KBITE_TRIGGERS.md"

        if [ -f "$triggers_file" ]; then
            # Extract trigger keywords from KBITE_TRIGGERS.md
            # Format: each line starting with "- " is a trigger
            while IFS= read -r line; do
                if [[ "$line" =~ ^-[[:space:]](.+) ]]; then
                    trigger="${BASH_REMATCH[1]}"
                    # Remove trailing colon and reason if present
                    trigger="${trigger%%:*}"
                    trigger=$(echo "$trigger" | xargs) # trim whitespace
                    if [ -n "$trigger" ]; then
                        TRIGGERS="$TRIGGERS$kbite_name:$trigger"$'\n'
                    fi
                fi
            done < "$triggers_file"
        fi
    fi
done

# Write cache file
echo "$TRIGGERS" > "$CACHE_FILE"

# Export cache location
echo "export GMCC_TRIGGERS_CACHE=\"$CACHE_FILE\""
echo "# Cached $(echo "$TRIGGERS" | grep -c ':') kbite triggers"
exit 0
