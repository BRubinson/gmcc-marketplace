---
name: gmcc_session_creation
description: Standalone GM-CDE session bootstrapper. Creates or repairs the current session folder (session_data.gmcc.yaml + prompts/ + gmcc_session_file_index.yaml) independent of the SessionStart hook. Idempotent — never clobbers existing files.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob
---

# GMCC Session Creation Skill

Bootstraps (or repairs) the **current** session folder on demand. The
`SessionStart` hook (`scripts/detect_repo.sh`) already does this automatically
the first time Claude Code starts in a repo, but this skill exists as a
**standalone, manually-invocable** path for when:

- the hook never ran (e.g. session started outside a git repo, then `cd`'d in),
- `session_data.gmcc.yaml` was deleted or corrupted and needs rebuilding,
- a session predates the `gmcc_session_file_index.yaml` file and needs it seeded,
- `/gmcc_session_cleanup` finds a missing core file and delegates here.

It mirrors `detect_repo.sh` step 5d (same SESSION_TEMPLATE substitution set and
kbite inheritance) but runs in primary context against the already-resolved
`$GMCC_SESSION_PATH`. **It does NOT modify `detect_repo.sh` or the SessionStart
flow.**

---

## When to Use

- Manually, when `session_data.gmcc.yaml` is missing/corrupt for the active session.
- To seed `gmcc_session_file_index.yaml` into an older session that lacks it.
- As the repair target invoked by `/gmcc_session_cleanup`.

---

## Core Principle: Idempotency

Every step is **create-if-missing**. The skill NEVER overwrites an existing
file. Running it twice on a healthy session creates nothing the second time and
prints "already present" for each file. If a file exists but is malformed,
this skill does NOT fix it — that is `/gmcc_session_cleanup`'s job (which may
back up the bad file first, then call back here to reseed).

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

Verify the following are set and exist: `$GMCC_SESSION_PATH`, `$GMCC_INSTANCE_PATH`,
`$GMCC_CKFS_ROOT`. If `$GMCC_SESSION_PATH` is unset, the environment never
resolved a session — instruct the user to restart Claude Code from inside a git
repo and exit.

---

## Execution

### 1. Session folder + prompts/

```bash
mkdir -p "$GMCC_SESSION_PATH/prompts"
```
Idempotent; safe if it already exists.

### 2. session_data.gmcc.yaml (create-if-missing)

If `$GMCC_SESSION_PATH/session_data.gmcc.yaml` already exists, **skip** (report
"already present"). Otherwise, derive the tokens and substitute the
SESSION_TEMPLATE — the **same** set `detect_repo.sh` step 5d uses:

| Token | Value |
|-------|-------|
| `SESSION_TEMPLATE_CODE` | session dir basename (slugified branch) |
| `SESSION_TEMPLATE_UUID` | a fresh v4 uuid (`uuidgen | tr 'A-Z' 'a-z'`) |
| `SESSION_TEMPLATE_NAME` | slugified branch (same as CODE) |
| `SESSION_TEMPLATE_CREATED_AT` | now, ISO 8601 (`date -u +"%Y-%m-%dT%H:%M:%SZ"`) |
| `SESSION_TEMPLATE_CKFS_ABS_PATH` | `$GMCC_SESSION_PATH` |
| `SESSION_TEMPLATE_CKFS_REL_PATH` | `$GMCC_SESSION_PATH` relative to `$GMCC_CKFS_ROOT` |
| `SESSION_TEMPLATE_BRANCH` | the slugified branch (dir basename) |
| `SESSION_TEMPLATE_INSTANCE_UUID` | `instance_uuid:` from `$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml` (its top-level `uuid:`) |
| `SESSION_TEMPLATE_PROJECT_UUID` | `project_uuid:` from `instance_data.gmcc.yaml` |

```bash
TEMPLATE="$GMCC_PLUGIN_ROOT/templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.gmcc.yaml"
sed -e "s|SESSION_TEMPLATE_CODE|$CODE|g" \
    -e "s|SESSION_TEMPLATE_UUID|$UUID|g" \
    -e "s|SESSION_TEMPLATE_NAME|$NAME|g" \
    -e "s|SESSION_TEMPLATE_CREATED_AT|$ISO_NOW|g" \
    -e "s|SESSION_TEMPLATE_CKFS_ABS_PATH|$GMCC_SESSION_PATH|g" \
    -e "s|SESSION_TEMPLATE_CKFS_REL_PATH|$SESSION_REL|g" \
    -e "s|SESSION_TEMPLATE_BRANCH|$SESSION_BRANCH|g" \
    -e "s|SESSION_TEMPLATE_INSTANCE_UUID|$INSTANCE_UUID|g" \
    -e "s|SESSION_TEMPLATE_PROJECT_UUID|$PROJECT_UUID|g" \
    "$TEMPLATE" > "$GMCC_SESSION_PATH/session_data.gmcc.yaml"
```

Then **inherit the kbite list** from the parent `instance_data.gmcc.yaml`: copy
its `kbite:` block over the new file's `kbite: []` placeholder (only when the
parent has a non-empty list). This matches `detect_repo.sh`'s `inherit_kbite`.

### 3. gmcc_session_file_index.yaml (create-if-missing)

If `$GMCC_SESSION_PATH/gmcc_session_file_index.yaml` exists, **skip**. Otherwise
write the seed below. Pull `code`/`name` from the just-ensured
`session_data.gmcc.yaml`; generate a **fresh** uuid for the index (it is its own
addressable file, distinct from the session). Conforms to
`gmcc.gmcc_session_file_index_file`.

```yaml
# gmcc_session_file_index.yaml — per-session file index.
#
# Indexes this session's architecture decision records and yeeted sections.
# Conforms to gmcc.gmcc_session_file_index_file (see $GMCC_PLUGIN_ROOT/gmcc.yeet.yaml).

yeet:
  - gmcc
yeet_type: gmcc.gmcc_session_file_index_file

id: 1
code: {session code}
uuid: {fresh v4 uuid}
name: {session name} file index
description: ""
created_time: {ISO 8601 now}
updated_time: {ISO 8601 now}
gmcc_ckfs_absolute_path: {GMCC_SESSION_PATH}/gmcc_session_file_index.yaml
gmcc_ckfs_relative_path: {session rel path}/gmcc_session_file_index.yaml

# Architecture decision records. Each entry conforms to
# gmcc_session_file_index_adr_entry: { id: int, name: string, description: string }.
architecture_decision_records: []

# Yeeted sections (TODO stub — gmcc_session_file_index_yeeted_section).
# Empty mapping for now; a later prompt defines this section's shape.
yeeted: {}
```

### 4. Register session in instance_data (optional, parity with detect_repo.sh)

If the session is not already listed in `$GMCC_INSTANCE_PATH/instance_data.gmcc.yaml`'s
`sessions:` list, append an entry (id/code/uuid/name/paths/branch) matching the
`gmcc_instance_data_file_session_entry` shape. Skip if already registered.

### 5. Summary

Print what was created vs. already-present:
```
GMCC Session Creation: {session code}

- prompts/                      {created | already present}
- session_data.gmcc.yaml        {created | already present}
- gmcc_session_file_index.yaml  {created | already present}
- instance_data sessions[] entry {added | already present}

Session ready at: $GMCC_SESSION_PATH
```

---

## Notes

- This skill is the canonical writer of `gmcc_session_file_index.yaml`. The
  SessionStart hook does NOT create it — older sessions get it lazily here or via
  `/gmcc_session_cleanup`.
- Never overwrite. Malformed-file repair belongs to `/gmcc_session_cleanup`,
  which backs up first and may then reseed via this skill.
- The index file carries no `version:` integer (consistent with the other core
  ckfs yamls); conformance is checked structurally by `yeet_type` + required
  fields, not by a version number.
