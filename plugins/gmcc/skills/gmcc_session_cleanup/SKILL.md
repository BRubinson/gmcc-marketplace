---
name: gmcc_session_cleanup
description: GM-CDE session-scoped cleanup auditor. Audits ONLY the current session — its prompts/ artifact tree on disk vs the daemon db rows (prompt stubs, artifact pointers, file changes) — and interactively resolves each finding with the user.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Session Cleanup Skill (v16.3.0)

Audits the **current session** — the artifact tree at `$GMCC_SESSION_PATH`
cross-checked against the daemon db rows (`gm session get`, `gm prompt
list/get`, `gm artifact list`, `gm file-change list`) — and interactively
resolves each finding.

This is the **session-scoped counterpart** to `gmcc_cleanup` (the
`/gmcc_environment_cleanup` command). The environment auditor deliberately
**excludes** the running session's paths from its walk, so the inside of
the active session is never inspected there. This skill fills that gap: it
looks *only* at the current session and never walks siblings or the
broader `$GMCC_CKFS_ROOT`.

---

## When to Use

- After manually editing/deleting files inside the session's `prompts/` folder.
- When artifact pointers dangle or `gm prompt get` shows artifacts that aren't on disk.
- Periodically, to keep the active session's disk and db in sync.

---

## Scope (hard boundary)

**Walk ONLY `$GMCC_SESSION_PATH` + this session's db rows.** Never recurse
into `$GMCC_CKFS_ROOT` broadly, never inspect sibling sessions, never touch
`_archive/`. All db access is read via `gm`; repairs are `gm` calls or
filesystem moves within the session.

---

## What Counts as Non-Compliant

### (a) Prompt folder ↔ prompt row integrity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Missing memory/ dir | prompt row exists but `prompts/{seq}_{name}/memory/` doesn't | `mkdir -p` it (default) |
| Orphan prompt folder | `prompts/{seq}_{name}/` on disk but no row with that `seq` in `gm prompt list` | If it contains a legacy yaml triad → hand off to `/import_legacy_yaml_gmcc`; if memory/-only → flag for user (archive or leave) |
| Legacy yaml files | `*_data.gmcc.yaml` / `*_initial.yaml` / `*_clarified.yaml` inside a prompt folder, or `session_data.gmcc.yaml` / `gmcc_session_file_index.yaml` at the session root | Hand off: `/import_legacy_yaml_gmcc` then `/archive_legacy_yaml_gmcc` (default), or skip |
| Loose file at prompts/ root | any file directly under `prompts/` (not in a `{seq}_{name}/` folder) | Move into the correct prompt folder, or archive to cold storage |
| Folder/row name drift | on-disk folder `{seq}_{name}` doesn't match the row's `seq`/`name` | Rename folder to match the row (source of truth), or skip |

### (b) Artifact pointer integrity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Unregistered artifact | `memory/{explore,qualified,architecture,review}.md` on disk with no `prompt_artifact` row (`gm artifact list --prompt-uuid U`) | Register via `gm artifact add` with the matching `--kind` + caption note (default), or skip |
| Dangling pointer | artifact row whose `file_path` doesn't exist on disk | Flag for user — restore the file if recoverable, or accept (pointers are history; no gm delete path) |
| Unknown memory file | a `memory/*.md` not matching a known kind | Register as `--kind other` (default), or skip |

### (c) File-change trail sanity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Stale file-change path | `gm file-change list` entry whose `path` no longer exists in the repo | Report only (the trail is append-only history — deletions/renames are normal); optionally record a `--kind delete|rename` follow-up entry |

### (d) Daemon/session health

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| No session row | `gm context get` returns null session for this repo/branch | `gm context ensure` via the `gmcc_session_creation` skill (default) |
| Daemon unreachable | `gm` exits 2 | Self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, retry |

---

## Walk Strategy

Bounded to the session. Order:

1. **Health first** — `gm ping`, `gm context get --json`; without a
   reachable daemon + session row, only filesystem findings can be
   audited (offer to fix health first).
2. **Session root** — expect only `prompts/`; anything else (including
   legacy `session_data.gmcc.yaml` / `gmcc_session_file_index.yaml`) is a
   finding.
3. **Db → disk** — for each stub in `gm prompt list --json`: check the
   `{seq}_{name}/memory/` dir, then `gm artifact list` rows vs disk files.
4. **Disk → db** — for each `prompts/{seq}_{name}/` folder: check a
   matching row exists; flag legacy yamls and unknown files.
5. **File-change trail** — `gm file-change list --json` path sanity.

Never judge the *content* of `memory/*.md` files (free-form artifacts) —
only presence and registration.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is
always the recommended, non-destructive default. Standard options:

| Option | What it does |
|--------|--------------|
| **Register / repair** (default for db-vs-disk drift) | The matching `gm` call (`artifact add`, `context ensure`) or `mkdir -p`/rename. |
| **Hand off** (default for legacy yaml) | Point at `/import_legacy_yaml_gmcc` + `/archive_legacy_yaml_gmcc`; never migrate inline. |
| **Archive** | `mv` into `$GMCC_CKFS_ROOT/_archive/cold_storage/{relative_path}` (structure-preserving, reversible). |
| **Skip** | Leave the finding in place. Always available. |

---

## Output Format

After the walk, before any prompts:

```
[GMB] Session Audit Report

Session: {code} ({session_uuid})
Daemon: {reachable | UNREACHABLE}
Total findings: {n}
- Prompt folder ↔ row integrity: {n}
- Artifact pointers: {n}
- File-change trail: {n}
- Legacy yaml (hand-off): {n}

Beginning interactive resolution. You can abort at any time — completed actions are NOT rolled back.
```

After resolution, print a resolved/skipped tally. Db repairs are audited
automatically in the daemon event log (`gm events`); filesystem actions
are reported in chat only.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete** — the destructive option is archive to cold storage (move, not delete).
- **Never write the db directly** — all db repairs go through `gm`.
- **Stay in scope** — never act on anything outside `$GMCC_SESSION_PATH` (plus this session's db rows via `gm`).
- **--dry-run** — when invoked with `--dry-run`, walk and report only; skip the resolution loop entirely.
