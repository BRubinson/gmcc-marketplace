#!/bin/bash
# auto_fam_sync.sh - Auto-update FAM ChangedFiles.md after Edit/Write operations
# Called by PostToolUse hook for Edit|Write tools

# Read hook input from stdin (JSON)
INPUT=$(cat)

# Extract tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only process if we have valid data
if [ -z "$TOOL_NAME" ] || [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

CKFS_ROOT="${GMCC_CKFS_ROOT:-}"
if [ -z "$CKFS_ROOT" ]; then
    exit 0
fi

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
    exit 0
fi

# [FIX #5] Use GMCC_FAM_PATH which includes repo ID in the path
# Old: $CKFS_ROOT/fam/$BRANCH was missing /$REPO_ID/ segment
FAM_DIR="${GMCC_FAM_PATH:-$CKFS_ROOT/$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")/fam/$BRANCH}"
CHANGED_FILES="$FAM_DIR/ChangedFiles.md"

# Only update if FAM directory exists (session has been initialized)
if [ ! -d "$FAM_DIR" ]; then
    exit 0
fi

# Get git diff stats
DIFF_STAT=$(git diff --stat 2>/dev/null | tail -1)
CHANGED_COUNT=$(git diff --name-only 2>/dev/null | wc -l | xargs)
STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l | xargs)

# Get main branch diff stats
MAIN_BRANCH="main"
if ! git show-ref --verify --quiet refs/heads/main; then
    MAIN_BRANCH="master"
fi

MAIN_DIFF_STAT=$(git diff "$MAIN_BRANCH" --stat 2>/dev/null | tail -1)
COMMITS_AHEAD=$(git log "$MAIN_BRANCH"..HEAD --oneline 2>/dev/null | wc -l | xargs)
FILES_FROM_MAIN=$(git diff "$MAIN_BRANCH" --name-only 2>/dev/null)

# Build ChangedFiles.md content
cat > "$CHANGED_FILES" << EOF
# Changed Files: $BRANCH

## Summary
- **Working directory**: $CHANGED_COUNT files modified, $STAGED_COUNT staged
- **Ahead of $MAIN_BRANCH**: $COMMITS_AHEAD commits
- **From $MAIN_BRANCH**: $MAIN_DIFF_STAT

## Files Changed from $MAIN_BRANCH

\`\`\`
$(git diff "$MAIN_BRANCH" --stat 2>/dev/null || echo "No changes")
\`\`\`

## File List

$(echo "$FILES_FROM_MAIN" | while read -r f; do
    if [ -n "$f" ]; then
        echo "- \`$f\`"
    fi
done)

---
*Auto-synced by: GMB FAM Sync*
*Last update: $(date -u +"%Y-%m-%dT%H:%M:%SZ")*
*Triggered by: $TOOL_NAME on $FILE_PATH*
EOF

# Silent success - don't pollute output
exit 0
