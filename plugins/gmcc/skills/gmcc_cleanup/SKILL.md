---
name: gmcc_cleanup
description: GM-CDE environment auditor. Checks daemon/db health, db-vs-disk drift (memory/ artifacts vs prompt_artifact rows), leftover pre-daemon yaml runtime files, archive hygiene, and persistent env/permission drift (~/.zshrc, ~/.claude/settings.json). Interactively resolves each finding.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Cleanup Skill

Audits the GMCC environment — the daemon db (`~/gmcc/gmcc.db` via `gm`),
the artifact tree (`$GMCC_CKFS_ROOT`), and the persistent host config —
and interactively resolves each finding.

Runtime data and all four bot reports live in the db; the ckfs holds only
prompt-scoped files and kbite content. This skill's job is keeping the two
in sync and the host wiring healthy.

---

## When to Use

- Periodically, to keep db + disk in sync
- After manual ckfs edits (renamed dirs, deleted files)
- When `gm` calls error unexpectedly or artifact pointers dangle
- After a plugin upgrade (stale `GMCC_PLUGIN_ROOT`, stale daemon binaries)

---

## Audit Categories

| Category | Detection | Default suggestion |
|----------|-----------|--------------------|
| Daemon unhealthy | `gm ping` / `gm status` fails or exits 2 | Run `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm setup` + `gm context ensure` |
| Pre-daemon yaml runtime files | Any `session_data.gmcc.yaml`, `project_index.gmcc.yaml`, `project_data.gmcc.yaml`, `instance_data.gmcc.yaml`, `gmcc_session_file_index.yaml`, or prompt yaml triad (`*_data.gmcc.yaml` / `*_initial.yaml` / `*_clarified.yaml`) under `$GMCC_PROJECTS` (outside `_archive/`) | Archive to `_archive/cold_storage/` (default) — nothing reads these; the db is the runtime. Or skip |
| Orphan memory artifact | `prompts/{seq}_{name}/memory/*.md` on disk with no matching `prompt_artifact` row (`gm artifact list --prompt-uuid U`) | Register via `gm artifact add` with a caption note (default), or skip |
| Dangling artifact pointer | `prompt_artifact` row whose `file_path` no longer exists on disk | Flag for user — restore the file from `_archive/` if it was moved, or accept the dangling pointer (rows are history; no gm delete path) |
| Orphan prompt folder | `prompts/{seq}_{name}/` on disk with no matching prompt row (`gm prompt list`) | If it has a yaml triad → archive (above). If memory/-only → flag for user (may belong to another instance/branch) |
| Missing artifact home | Prompt row exists but `prompts/{seq}_{name}/memory/` doesn't | `mkdir -p` it (default) |
| Archive hygiene | Files under `$GMCC_CKFS_ROOT/_archive/` outside `cold_storage/` | Move into `_archive/cold_storage/` preserving relative structure (default), or skip — cold_storage is the single universal bucket |
| Unexpected cruft | Top-level `$GMCC_CKFS_ROOT` entries other than `README.md`, `projects/`, `kbites/`, `_archive/`; non-`prompts/` clutter in session dirs | Archive to `_archive/cold_storage/` (default) or keep |
| Stale chewed provenance path | Inside `kbites/digested/{name}/.../*_chewed.md`, a `**Source**:` or `**Location**:` line points at an absolute path that no longer exists | Rewrite the line to strip the dead absolute prefix and prepend `(retired maw source) `, preserving the relative slug (default), or leave unchanged |
| Stale `GMCC_PLUGIN_ROOT` in `~/.zshrc` | See "Persistent Env" below | Update to current value (default) |
| Missing CKFS permission grant in `~/.claude/settings.json` | See "Persistent Permissions" below | Add missing entries (default) |
| Undigested kbite content | `$GMCC_KBITE_DIGESTED/{name}/` contains `*_chewed.md` files but `gm kbite get --code {name} --json` shows no resources (pre-v16 kbite never backfilled) | Backfill (default): copy the chewed files (+ `KBITE_INDEX.md` / `KBITE_RELATIONSHIPS.md` if present) to `_archive/cold_storage/kbites/digested/{name}/`, then `gm kbite digest --code {name} --kbite-open-path "$GMCC_KBITE_DIGESTED/{name}"`, verify counts via `gm kbite get`, delete the stale `KBITE_INDEX.md` — Or skip |
| KBite drift: db row without content | A `gm kbite list --all` row whose code has neither `$GMCC_KBITE/{name}/` nor `$GMCC_KBITE_DIGESTED/{name}/` on disk | Report only — digested text legitimately lives db-only; a missing KBITE_PURPOSE.md/raw archive may still be intentional. Flag for user, never auto-delete db rows |
| KBite drift: content without registry reach | A kbite content dir whose code has db resources but appears in no registry (`gm kbite list --scope project|instance|session` all miss it) | Report only — informational; kbites are registered on explicit request (`gm kbite add`) |

---

## Persistent Env: `GMCC_PLUGIN_ROOT` in `~/.zshrc`

`/gm_init` writes a marked `# >>> gmcc env >>>` ... `# <<< gmcc env <<<` block to `~/.zshrc` containing the stable GMCC exports plus `GMCC_PLUGIN_ROOT`. The plugin-root value is version-dependent (`~/.claude/plugins/cache/gmcc-marketplace/gmcc/{version}/`), so it goes stale every time the plugin upgrades. GUI consumers (notably GMVibes) read it from the launching shell's environment, so a stale or missing value breaks them.

**Detection rules** (one finding max from this category):

1. If `$GMCC_PLUGIN_ROOT` is unset (cleanup invoked outside a booted Claude session) → skip this check entirely. Log `[GMB] Skipping GMCC_PLUGIN_ROOT check — session not booted`. Do NOT emit a finding.
2. If `~/.zshrc` does not exist, or the `# >>> gmcc env >>>` marker is absent → no finding. `/gm_init` owns block creation.
3. Otherwise, extract the block between the markers:
   - No `export GMCC_PLUGIN_ROOT=` line → finding **kind: missing**.
   - Value (quotes stripped) differs from `$GMCC_PLUGIN_ROOT` → finding **kind: stale**, include both values.
   - A leftover `export GMCC_PROJECTS_INDEX=` line (retired in v16) → finding **kind: retired-line**, default: remove the line.

**Resolution (per-finding AskUserQuestion):**

```
Stale GMCC_PLUGIN_ROOT in ~/.zshrc

  current ($GMCC_PLUGIN_ROOT): {actual}
  persisted in ~/.zshrc:        {persisted or "(missing)"}

How would you like to resolve this?

- Update to current value - Rewrite the export line in place (default)
- Keep existing - Leave ~/.zshrc unchanged
- Remove the line - Delete just the export line, keep the rest of the block
```

**Apply:** edit only between the markers — never touch lines outside them. After applying Update, remind the user to `source ~/.zshrc` (or restart the affected GUI app).

---

## Persistent Permissions: CKFS allow rules in `~/.claude/settings.json`

`/gm_init` writes a one-time grant giving the plugin read/edit access under `$GMCC_CKFS_ROOT` (`Read(path)` rules cover all file-reading tools, `Edit(path)` rules cover all file-editing tools — no separate `Write`/`Glob` rules exist), an `additionalDirectories` entry, and a `Bash(~/gmcc/bin/gm *)` allowlist entry for the gm CLI.

**Detection rules** (one finding max):

1. If `$GMCC_CKFS_ROOT` is unset → skip; log `[GMB] Skipping CKFS permission grant check — session not booted`.
2. If `~/.claude/settings.json` doesn't exist or is unparseable → no finding (`/gm_init` owns creation).
3. Expected entries:
   - dir: `$GMCC_CKFS_ROOT` in `.permissions.additionalDirectories`
   - allow: `Read($GMCC_CKFS_ROOT/**)`, `Edit($GMCC_CKFS_ROOT/**)`, `Bash($HOME/gmcc/bin/gm *)`
4. Any missing → finding **kind: missing-entries** with the exact list.
5. Stale `Write($GMCC_CKFS_ROOT/**)` / `Glob($GMCC_CKFS_ROOT/**)` entries present (written by pre-v16 /gm_init; Claude Code ignores them and warns on startup) → finding **kind: stale-entries**.

**Resolution:** Add missing entries and remove stale ones (default — the same idempotent jq merge `/gm_init` uses scrubs stale `Write`/`Glob` rules while adding what's missing; preserves all other keys) or skip. If `jq` is unavailable, print install instructions + the exact entries instead of hand-editing JSON. Remind the user the grant takes effect on the **next** Claude Code restart.

---

## Walk Strategy

The walk is bounded — never recurses into git repos, kbite resource trees, or `_archive/` (except the archive-hygiene surface check). Order:

1. **Daemon health**: `gm ping`, `gm status`, `gm context get --json`.
2. **Top-level of `$GMCC_CKFS_ROOT`** — anything other than `README.md`, `projects/`, `kbites/`, `_archive/` is a finding.
3. **`projects/` tree** — walk `projects/{p}/instances/{i}/sessions/{s}/`:
   - any pre-daemon runtime yaml (see table) → ONE aggregate archive finding (listing all hits), not one per file;
   - session dirs should contain only `prompts/`.
4. **Per-session db cross-check** (for sessions resolvable to db rows): `gm prompt list --session-uuid U` vs on-disk `prompts/{seq}_{name}/` folders; `gm artifact list --prompt-uuid U` vs `memory/*.md` files, in both directions.
5. **`_archive/`** — surface-level only: entries outside `cold_storage/`.
6. **Kbite provenance** — stale `**Source**:` lines in `*_chewed.md` under `kbites/digested/`.
7. **Host config** — zshrc block + settings.json grant.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is always the recommended default. Standard option set:

| Option | What it does |
|--------|--------------|
| **Archive** (default for cruft) | `mv` the path into `~/gmcc_ckfs/_archive/cold_storage/{relative_path}` (structure-preserving). |
| **Register/repair** (default for db-vs-disk drift) | The matching `gm` call (`artifact add`, `context ensure`) or `mkdir -p`. |
| **Skip** | Leave the finding in place. Always available. |

Bulk actions (e.g. "archive all cruft") are offered after the first 3 similar findings, with an extra confirmation.

---

## Output Format

After the walk, before any prompts:

```
[GMB] GMCC Environment Audit

Daemon: {reachable pid N, schema vX | UNREACHABLE}
Scanned: $GMCC_CKFS_ROOT
Total findings: {n}
- Daemon/db health: {n}
- Pre-daemon yaml runtime files: {n}
- Orphan memory artifacts (unregistered): {n}
- Dangling artifact pointers: {n}
- Archive hygiene: {n}
- Cruft: {n}
- Stale chewed provenance: {n}
- Host config drift (zshrc/settings.json): {n}

Beginning interactive resolution. You can abort at any time — completed actions are NOT rolled back.
```

After resolution, print a resolved/skipped tally. The audit trail lives in
the daemon event log (`gm events`) for db writes; filesystem actions are
reported in chat only.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete** — the destructive option is Archive (reversible, structure-preserving under `_archive/cold_storage/`). `rm` is never offered.
- **Never write the db directly** — all db repairs go through `gm`.
- **Never touch the live current-session paths**: if the walk encounters `$GMCC_SESSION_PATH` or its parents, those are excluded from findings even if they look unusual (they belong to the running session).
- **Bulk actions** require an extra confirmation prompt.
