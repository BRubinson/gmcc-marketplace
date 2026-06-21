#!/bin/bash

# GM-CDE Repository Detection Script — v6.1.0
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
# As of v6.1.0 the four runtime yamls use the .gmcc.yaml suffix and
# carry yeet:/yeet_type: headers — they conform to types in gmcc.yeet.md.
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
GMCC_PROJECTS_INDEX="$GMCC_PROJECTS/project_index.gmcc.yaml"

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

# Ckfs-relative paths (for the gmcc_ckfs_relative_path fields).
PROJECT_REL="projects/$PROJECT_NAME"
INSTANCE_REL="$PROJECT_REL/instances/$INSTANCE_ID"
SESSION_REL="$INSTANCE_REL/sessions/$SESSION_BRANCH"

# UUID generator — prefer uuidgen, fall back to /proc or python.
gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        python3 -c 'import uuid; print(uuid.uuid4())'
    fi
}

# Extract the first top-level `uuid:` value from a yaml file.
get_yaml_uuid() {
    grep -m1 "^uuid: " "$1" 2>/dev/null | sed 's/^uuid: //'
}

# --- 5. Lazy create ---------------------------------------------------------
ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 5a. Projects root + registry (created by /gm_init normally; safety net here).
if [ ! -d "$GMCC_PROJECTS" ]; then
    mkdir -p "$GMCC_PROJECTS"
fi
if [ ! -f "$GMCC_PROJECTS_INDEX" ] && [ -f "$TEMPLATES_DIR/project_index.gmcc.yaml" ]; then
    INDEX_UUID=$(gen_uuid)
    sed -e "s|PROJECT_INDEX_FILE_UUID|$INDEX_UUID|g" \
        -e "s|PROJECT_INDEX_FILE_CREATED_AT|$ISO_NOW|g" \
        -e "s|PROJECT_INDEX_FILE_CKFS_ABS_PATH|$GMCC_PROJECTS_INDEX|g" \
        "$TEMPLATES_DIR/project_index.gmcc.yaml" \
        > "$GMCC_PROJECTS_INDEX"
fi

# 5b. Project dir + project_data.gmcc.yaml
if [ ! -d "$GMCC_PROJECT_PATH" ]; then
    mkdir -p "$GMCC_PROJECT_PATH/instances"
fi
if [ ! -f "$GMCC_PROJECT_PATH/project_data.gmcc.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/project_data.gmcc.yaml" ]; then
    PROJECT_UUID=$(gen_uuid)
    sed -e "s|PROJECT_TEMPLATE_CODE|$PROJECT_NAME|g" \
        -e "s|PROJECT_TEMPLATE_UUID|$PROJECT_UUID|g" \
        -e "s|PROJECT_TEMPLATE_NAME|$PROJECT_NAME|g" \
        -e "s|PROJECT_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        -e "s|PROJECT_TEMPLATE_CKFS_ABS_PATH|$GMCC_PROJECT_PATH|g" \
        -e "s|PROJECT_TEMPLATE_CKFS_REL_PATH|$PROJECT_REL|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/project_data.gmcc.yaml" \
        > "$GMCC_PROJECT_PATH/project_data.gmcc.yaml"
fi

# Always-resolve the project's uuid (either freshly generated or extracted
# from an existing project_data.gmcc.yaml) — needed as the project_uuid
# back-reference inside instance_data and session_data.
PROJECT_UUID=$(get_yaml_uuid "$GMCC_PROJECT_PATH/project_data.gmcc.yaml")

# 5c. Instance dir + instance_data.gmcc.yaml
if [ ! -d "$GMCC_INSTANCE_PATH" ]; then
    mkdir -p "$GMCC_INSTANCE_PATH/sessions"
fi
if [ ! -f "$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.gmcc.yaml" ]; then
    INSTANCE_UUID=$(gen_uuid)
    sed -e "s|INSTANCE_TEMPLATE_CODE|$INSTANCE_ID|g" \
        -e "s|INSTANCE_TEMPLATE_UUID|$INSTANCE_UUID|g" \
        -e "s|INSTANCE_TEMPLATE_NAME|$INSTANCE_ID|g" \
        -e "s|INSTANCE_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        -e "s|INSTANCE_TEMPLATE_CKFS_ABS_PATH|$GMCC_INSTANCE_PATH|g" \
        -e "s|INSTANCE_TEMPLATE_CKFS_REL_PATH|$INSTANCE_REL|g" \
        -e "s|INSTANCE_TEMPLATE_SYSTEM_PATH|$REPO_ROOT|g" \
        -e "s|INSTANCE_TEMPLATE_PROJECT_UUID|$PROJECT_UUID|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.gmcc.yaml" \
        > "$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml"
fi
INSTANCE_UUID=$(get_yaml_uuid "$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml")

# 5d. Session dir + session_data.gmcc.yaml + prompts/
if [ ! -d "$GMCC_SESSION_PATH" ]; then
    mkdir -p "$GMCC_SESSION_PATH/prompts"
fi
if [ ! -f "$GMCC_SESSION_PATH/session_data.gmcc.yaml" ] \
   && [ -f "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.gmcc.yaml" ]; then
    SESSION_UUID=$(gen_uuid)
    sed -e "s|SESSION_TEMPLATE_CODE|$SESSION_BRANCH|g" \
        -e "s|SESSION_TEMPLATE_UUID|$SESSION_UUID|g" \
        -e "s|SESSION_TEMPLATE_NAME|$SESSION_BRANCH|g" \
        -e "s|SESSION_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
        -e "s|SESSION_TEMPLATE_CKFS_ABS_PATH|$GMCC_SESSION_PATH|g" \
        -e "s|SESSION_TEMPLATE_CKFS_REL_PATH|$SESSION_REL|g" \
        -e "s|SESSION_TEMPLATE_BRANCH|$SESSION_BRANCH|g" \
        -e "s|SESSION_TEMPLATE_INSTANCE_UUID|$INSTANCE_UUID|g" \
        -e "s|SESSION_TEMPLATE_PROJECT_UUID|$PROJECT_UUID|g" \
        "$TEMPLATES_DIR/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.gmcc.yaml" \
        > "$GMCC_SESSION_PATH/session_data.gmcc.yaml"
fi
SESSION_UUID=$(get_yaml_uuid "$GMCC_SESSION_PATH/session_data.gmcc.yaml")

# 5e. Register slim project entry in $GMCC_PROJECTS_INDEX if not already
# present. Per-project instance lists live in project_data.gmcc.yaml, and
# per-instance session lists live in instance_data.gmcc.yaml — see 5f, 5g.
if [ -f "$GMCC_PROJECTS_INDEX" ]; then
    if ! grep -qE "^    code: $PROJECT_NAME$" "$GMCC_PROJECTS_INDEX" 2>/dev/null; then
        if grep -qE "^projects: \[\]$" "$GMCC_PROJECTS_INDEX"; then
            sed -i.bak "s|^projects: \[\]$|projects:|" "$GMCC_PROJECTS_INDEX"
            rm -f "$GMCC_PROJECTS_INDEX.bak"
        fi
        {
            echo "  - id: 1"
            echo "    code: $PROJECT_NAME"
            echo "    uuid: $PROJECT_UUID"
            echo "    name: $PROJECT_NAME"
            echo "    description: \"\""
            echo "    created_time: $ISO_NOW"
            echo "    updated_time: $ISO_NOW"
            echo "    gmcc_ckfs_absolute_path: $GMCC_PROJECT_PATH"
            echo "    gmcc_ckfs_relative_path: $PROJECT_REL"
        } >> "$GMCC_PROJECTS_INDEX"
    fi
fi

# 5f. Register instance entry in $GMCC_PROJECT_PATH/project_data.gmcc.yaml
# if not already present.
PROJECT_DATA="$GMCC_PROJECT_PATH/project_data.gmcc.yaml"
if [ -f "$PROJECT_DATA" ]; then
    if ! grep -qE "^    code: $INSTANCE_ID$" "$PROJECT_DATA" 2>/dev/null; then
        if grep -qE "^instances: \[\]$" "$PROJECT_DATA"; then
            sed -i.bak "s|^instances: \[\]$|instances:|" "$PROJECT_DATA"
            rm -f "$PROJECT_DATA.bak"
        fi
        {
            echo "  - id: 1"
            echo "    code: $INSTANCE_ID"
            echo "    uuid: $INSTANCE_UUID"
            echo "    name: $INSTANCE_ID"
            echo "    description: \"\""
            echo "    created_time: $ISO_NOW"
            echo "    updated_time: $ISO_NOW"
            echo "    gmcc_ckfs_absolute_path: $GMCC_INSTANCE_PATH"
            echo "    gmcc_ckfs_relative_path: $INSTANCE_REL"
            echo "    system_path: $REPO_ROOT"
        } >> "$PROJECT_DATA"
    fi
fi

# 5g. Register session entry in $GMCC_INSTANCE_PATH/instance_data.gmcc.yaml
# if not already present.
INSTANCE_DATA="$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml"
if [ -f "$INSTANCE_DATA" ]; then
    if ! grep -qE "^    code: $SESSION_BRANCH$" "$INSTANCE_DATA" 2>/dev/null; then
        if grep -qE "^sessions: \[\]$" "$INSTANCE_DATA"; then
            sed -i.bak "s|^sessions: \[\]$|sessions:|" "$INSTANCE_DATA"
            rm -f "$INSTANCE_DATA.bak"
        fi
        {
            echo "  - id: 1"
            echo "    code: $SESSION_BRANCH"
            echo "    uuid: $SESSION_UUID"
            echo "    name: $SESSION_BRANCH"
            echo "    description: \"\""
            echo "    created_time: $ISO_NOW"
            echo "    updated_time: $ISO_NOW"
            echo "    gmcc_ckfs_absolute_path: $GMCC_SESSION_PATH"
            echo "    gmcc_ckfs_relative_path: $SESSION_REL"
        } >> "$INSTANCE_DATA"
    fi
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
