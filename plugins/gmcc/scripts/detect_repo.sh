#!/bin/bash

# GM-CDE Repository Detection Script — v6.0.0
#
# Runs on SessionStart. When inside a git repository, this script:
#   1. Resolves the active project (= git repo dir basename)
#   2. Resolves the active instance (= unique filesystem path to this checkout)
#   3. Resolves the active session (= current git branch)
#   4. Lazily creates the project / instance / session directories from templates
#      under $GMCC_PLUGIN_ROOT/templates/projects/ if any are missing
#   5. Registers the project in $GMCC_PROJECTS_INDEX (idempotent)
#   6. Exports all GMCC_* env vars via $CLAUDE_ENV_FILE
#
# Anything outside a git repo: silent exit with no GMCC vars set.

# --- 0. Git-repo guard ------------------------------------------------------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# --- 1. Resolve plugin root from this script's location ---------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$GMCC_PLUGIN_DIR/templates/projects"

# --- 2. Stable paths --------------------------------------------------------
GMCC_CKFS_ROOT="$HOME/gmcc_ckfs"
GMCC_PROJECTS="$GMCC_CKFS_ROOT/projects"
GMCC_PROJECTS_INDEX="$GMCC_PROJECTS/project_index.yaml"

# --- 3. Per-session identifiers ---------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
PROJECT_NAME=$(basename "$REPO_ROOT")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Slugify: replace each / with __ (matches branch sanitization convention).
# Use sed (not tr) — tr is char-to-char and would collapse / into a single _.
slugify() { echo "$1" | sed 's|/|__|g'; }

# Strip the leading __ that comes from the leading / in absolute paths.
INSTANCE_ID=$(slugify "$REPO_ROOT" | sed 's|^__||')
SESSION_BRANCH=$(slugify "$BRANCH")

# --- 4. Resolved paths ------------------------------------------------------
GMCC_PROJECT_PATH="$GMCC_PROJECTS/$PROJECT_NAME"
GMCC_INSTANCE_PATH="$GMCC_PROJECT_PATH/instances/$INSTANCE_ID"
GMCC_SESSION_PATH="$GMCC_INSTANCE_PATH/sessions/$SESSION_BRANCH"

# --- 5. Lazy create ---------------------------------------------------------
ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 5a. Projects root + registry (created by /gm_init normally; safety net here).
if [ ! -d "$GMCC_PROJECTS" ]; then
    mkdir -p "$GMCC_PROJECTS"
fi
if [ ! -f "$GMCC_PROJECTS_INDEX" ] && [ -f "$TEMPLATES_DIR/project_index.yaml" ]; then
    cp "$TEMPLATES_DIR/project_index.yaml" "$GMCC_PROJECTS_INDEX"
fi

# 5b. Project dir + Project_Data.yaml
if [ ! -d "$GMCC_PROJECT_PATH" ]; then
    mkdir -p "$GMCC_PROJECT_PATH/instances"
fi
if [ ! -f "$GMCC_PROJECT_PATH/Project_Data.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/Project_Data.yaml" ]; then
    sed -e "s|PROJECT_TEMPLATE_NAME|$PROJECT_NAME|g" \
        -e "s|PROJECT_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/Project_Data.yaml" \
        > "$GMCC_PROJECT_PATH/Project_Data.yaml"
fi

# 5c. Instance dir + instance_data.yaml
if [ ! -d "$GMCC_INSTANCE_PATH" ]; then
    mkdir -p "$GMCC_INSTANCE_PATH/sessions"
fi
if [ ! -f "$GMCC_INSTANCE_PATH/instance_data.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.yaml" ]; then
    sed -e "s|INSTANCE_TEMPLATE_ID|$INSTANCE_ID|g" \
        -e "s|INSTANCE_TEMPLATE_ABS_PATH|$REPO_ROOT|g" \
        -e "s|INSTANCE_TEMPLATE_PROJECT_NAME|$PROJECT_NAME|g" \
        -e "s|INSTANCE_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.yaml" \
        > "$GMCC_INSTANCE_PATH/instance_data.yaml"
fi

# 5d. Session dir + session_data.yaml + prompts/
if [ ! -d "$GMCC_SESSION_PATH" ]; then
    mkdir -p "$GMCC_SESSION_PATH/prompts"
fi
if [ ! -f "$GMCC_SESSION_PATH/session_data.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.yaml" ]; then
    sed -e "s|SESSION_TEMPLATE_BRANCH|$SESSION_BRANCH|g" \
        -e "s|SESSION_TEMPLATE_INSTANCE_ID|$INSTANCE_ID|g" \
        -e "s|SESSION_TEMPLATE_PROJECT_NAME|$PROJECT_NAME|g" \
        -e "s|SESSION_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.yaml" \
        > "$GMCC_SESSION_PATH/session_data.yaml"
fi

# 5e. Register project + instance in $GMCC_PROJECTS_INDEX if not already present.
# Idempotent grep-then-append. Full yaml-aware updates are a follow-up.
if [ -f "$GMCC_PROJECTS_INDEX" ]; then
    if ! grep -qE "^- name: $PROJECT_NAME$" "$GMCC_PROJECTS_INDEX" 2>/dev/null; then
        # New project — append minimal stub. Keeps the file valid yaml.
        if grep -qE "^projects: \[\]$" "$GMCC_PROJECTS_INDEX"; then
            # Convert empty list to populated list with the first entry.
            sed -i.bak "s|^projects: \[\]$|projects:|" "$GMCC_PROJECTS_INDEX"
            rm -f "$GMCC_PROJECTS_INDEX.bak"
        fi
        {
            echo "- name: $PROJECT_NAME"
            echo "  path: $GMCC_PROJECT_PATH"
            echo "  registered_at: $ISO_NOW"
            echo "  instances:"
            echo "    - id: $INSTANCE_ID"
            echo "      abs_path: $REPO_ROOT"
            echo "      registered_at: $ISO_NOW"
        } >> "$GMCC_PROJECTS_INDEX"
    fi
    # Note: instance-level registration when project already exists is left to
    # /gm_cleanup or a follow-up — minimal yaml editing in bash gets fragile fast.
fi

# --- 6. Export to $CLAUDE_ENV_FILE -----------------------------------------
if [ -n "$CLAUDE_ENV_FILE" ]; then
    {
        echo "GMCC_CKFS_ROOT=$GMCC_CKFS_ROOT"
        echo "GMCC_PROJECTS=$GMCC_PROJECTS"
        echo "GMCC_PROJECTS_INDEX=$GMCC_PROJECTS_INDEX"
        echo "GMCC_PROJECT_PATH=$GMCC_PROJECT_PATH"
        echo "GMCC_INSTANCE_PATH=$GMCC_INSTANCE_PATH"
        echo "GMCC_SESSION_PATH=$GMCC_SESSION_PATH"
        # KBite layout (unchanged from v5.5).
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
