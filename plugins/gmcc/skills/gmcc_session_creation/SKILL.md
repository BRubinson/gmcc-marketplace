---
name: gmcc_session_creation
description: Standalone GM-CDE session bootstrapper. Ensures the current session's db rows (gm context ensure) and physical artifact home (prompts/) exist, independent of the SessionStart hook. Idempotent — never clobbers existing state.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob
---

# GMCC Session Creation Skill (v16.3.0)

Bootstraps (or repairs) the **current** session on demand. The
`SessionStart` hook (`scripts/detect_repo.sh`) already does this
automatically the first time Claude Code starts in a repo, but this skill
exists as a **standalone, manually-invocable** path for when:

- the hook never ran (e.g. session started outside a git repo, then `cd`'d in),
- the daemon was unreachable at SessionStart so no db rows were ensured,
- the session's `prompts/` artifact home was deleted,
- `/gmcc_session_cleanup` finds missing session state and delegates here.

**It does NOT modify `detect_repo.sh` or the SessionStart flow.**

---

## When to Use

- Manually, when the db has no rows for the active session (`gm context get` returns nulls).
- To recreate a deleted `$GMCC_SESSION_PATH/prompts/` directory.
- As the repair target invoked by `/gmcc_session_cleanup`.

---

## Core Principle: Idempotency

Both steps are natively idempotent: `gm context ensure` upserts (reusing
existing uuids, seeding kbite inheritance only at row-create time) and
`mkdir -p` is a no-op on existing dirs. Running this twice on a healthy
session changes nothing.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

Verify `$GMCC_SESSION_PATH` is set. If unset, the environment never resolved
a session — instruct the user to restart Claude Code from inside a git repo
and exit.

---

## Execution

### 1. Physical artifact home

```bash
mkdir -p "$GMCC_SESSION_PATH/prompts"
```

### 2. Db rows

```bash
~/gmcc/bin/gm context ensure --json
```

Run from inside the repo (git context is auto-detected). If this exits 2
(daemon unreachable), self-heal first:

```bash
bash "$GMCC_PLUGIN_ROOT/scripts/build_daemon.sh"
~/gmcc/bin/gm context ensure --json
```

The response reports `project_uuid` / `instance_uuid` / `session_uuid` and
`created_*` booleans telling you which rows were newly created vs. already
present.

### 3. Summary

Print what was created vs. already-present:
```
GMCC Session Creation: {session code}

- prompts/            {created | already present}
- project row         {created | already present}
- instance row        {created | already present}
- session row         {created | already present}

Session ready: $GMCC_SESSION_PATH (artifacts) + ~/gmcc/gmcc.db (data)
```

---

## Notes

- The runtime yamls (session_data.gmcc.yaml, gmcc_session_file_index.yaml,
  templates) are retired as of v16 — this skill no longer writes any yaml.
  Legacy yaml trees are handled by `/import_legacy_yaml_gmcc` +
  `/archive_legacy_yaml_gmcc`.
- Kbite inheritance is seeded db-side at row-create time by
  `gm context ensure`. Explicit registry ops afterward are
  `gm kbite add/remove/list` — the db is the sole registry.
