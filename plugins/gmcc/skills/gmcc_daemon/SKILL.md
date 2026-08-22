---
name: gmcc_daemon
description: How to invoke the GMCC daemon system - the gm CLI at ~/gmcc/bin/gm, its subcommands (context, session, prompt, artifact, file-change, kbite, events, backup), the single-writer SQLite model, and the self-heal rule when binaries are missing or stale. Use whenever recording file changes to the daemon db, managing prompts/artifacts/kbites over the daemon, searching kbite knowledge, checking daemon/db health, or building the daemon.
---

# GMCC Daemon (gm CLI)

The GMCC daemon system is a Swift package at `$GMCC_PLUGIN_ROOT/daemon/`
shipping three products:

- **`gmcc_daemon`** — persistent background process; the ONLY process that
  touches the SQLite db at `~/gmcc/gmcc.db` (single-writer model; WAL,
  foreign_keys=ON).
- **`gm`** — the single CLI. Claude calls it directly; no per-command
  symlinks or shims. It is a socket client of the daemon.
- **`GMCCDaemonKit`** — shared library; GMVibes imports it as a local package
  and speaks the same protocol (typed facade on `DaemonClient`, event stream
  via `DaemonEventSubscription`).

Transport: NDJSON over a unix socket at `~/gmcc/daemon.sock` (wire protocol
v5, one spec-named message per handler). Clients autostart the daemon when
the socket is dead. The protocol handshake is DIRECTIONAL: a newer client
makes a stale daemon self-exit after rebuilds; an older client is rejected
while the daemon stays up — you never need to manage daemon lifecycle
manually.

Note: `~/gmcc/` (runtime: binaries, socket, db, log, pidfile, backups) is
distinct from `~/gmcc_ckfs/` (the CKFS yaml tree). Neither is in git. The
daemon writes the db ONLY — it never touches ckfs yamls.

## Invocation pattern

Always call the installed binary by absolute path:

```bash
~/gmcc/bin/gm <subcommand> [options]
```

All subcommands accept `--json` for the raw response. Subcommands (grouped by
message family):

| Subcommand | Purpose |
|------------|---------|
| `gm ping` | Liveness + build identity (sha/date stamped by build_daemon.sh), uptime. |
| `gm status` | Daemon + db health: pid, protocol, socket, schema version, per-table row counts. |
| `gm setup [--launchd]` | Client-side init of `~/gmcc/` dirs + daemon autostart. `--launchd` installs a login agent. |
| `gm daemon start\|stop\|restart\|status` | Lifecycle. `stop` = SHUTDOWN: drain, WAL checkpoint, pidfile + socket removal, exit 0. |
| `gm backup` | SQLite online backup to a timestamped copy under `~/gmcc/backups/`. |
| `gm events [--kind K] [--subject-uuid U] [--since-id N] [--since-time T] [--until-time T] [--limit N] [--follow]` | Query the daemon_event audit log; `--follow` streams live (with `--since-id` replay — no missed events across reconnects). |
| `gm context ensure [--from-ckfs <projects/p/instances/i/sessions/s>]` | Upsert project → instance → session from the current repo/branch (idempotent; reuses ckfs uuids; seeds kbite inheritance at create time). Returns the uuid triple. `--from-ckfs` builds the chain from a legacy ckfs session directory instead of cwd git — the /import_legacy_yaml_gmcc backfill path. |
| `gm context get` | Read-only resolution of the current gmcc environment (never creates rows). |
| `gm project list` | All projects (full rows incl. ckfs paths), ordered by code — the Landing browse entry point. |
| `gm instance list [--project-uuid U]` | Instances, ordered by code. Omit the filter to list ALL instances (rows carry their project uuid); an unknown supplied uuid ⇒ NOT_FOUND. |
| `gm session list [--instance-uuid U]` | Session stubs (full scalars minus backstory/goal bodies), ordered by code. Same optional-filter contract as `gm instance list`. |
| `gm catalog search <query> [--project-uuid U] [--limit N]` | Tokenized OR name/code search over instances + sessions (case-insensitive literal substrings; wildcards escaped). An instance match returns ALL its sessions; every returned session's parent instance rides along. Unknown supplied project uuid ⇒ NOT_FOUND; whitespace-only query ⇒ BAD_REQUEST. |
| `gm session get [--session-uuid U]` | Session row + prompt stubs + change summaries (per-prompt where attributed). Always singular; the uuid defaults to the current repo/branch session. |
| `gm session update --expected-version N [--session-uuid U] [--name] [--backstory] [--goal] [--status active\|closed]` | Guarded scalar update (at least one field required); stale version ⇒ VERSION_CONFLICT. Always singular; the uuid defaults to the current repo/branch session. |
| `gm prompt create --name N [--session-uuid U] [--code] [--backstory] [--goal] [--detail] [--command] [--uuid]` | Create a prompt; the daemon allocates the next per-session seq atomically. Session defaults to the current repo/branch. |
| `gm prompt list [--session-uuid U] [--all]` | Lightweight stubs (uuid, session_uuid, seq, code, name, status, version). Session defaults to the current repo/branch — **not** every session in the db; `--all` lists every prompt in the db (stubs carry `session_uuid` for grouping; seq is only unique per session). `--all` is not combinable with `--session-uuid`; an unknown supplied uuid ⇒ NOT_FOUND, never a silent empty list. |
| `gm prompt get --prompt-uuid U` | Full prompt + artifact pointers + kbites + change summary. |
| `gm prompt update-content --prompt-uuid U --expected-version N [--backstory] [--goal] [--detail]` | Draft-only edit of the STAY TRUE triple; CONTENT_LOCKED once Clarifying/Clarified. |
| `gm prompt set-status --prompt-uuid U --expected-version N --status S` | Forward-only draft → clarifying → clarified; anything else ⇒ INVALID_TRANSITION. |
| `gm artifact add --prompt-uuid U --file-path P --kind explore\|architecture\|review\|qualified\|other [--note]` | Register a bot-phase memory/ file pointer (content stays in the file). |
| `gm artifact list --prompt-uuid U` | Artifact pointers for a prompt. |
| `gm file-change add --path <repo-rel> [--kind edit\|create\|delete\|rename] [--range start:end]... [--content <text>] [--prompt-uuid <uuid>]` | Record a file edit: session_file + file_change + ranges + FILE_CHANGE event. Run from inside the repo — git context is auto-detected and ckfs uuids reused. |
| `gm file-change list [--session-uuid U] [--prompt-uuid] [--path] [--limit] [--all]` | Query changes for the current session with ranges joined. `--all` drops the current-session default and queries the whole db (`--prompt-uuid`/`--path` still narrow); not combinable with `--session-uuid`; an unknown supplied uuid ⇒ NOT_FOUND. |
| `gm kbite list [--scope project\|instance\|session\|prompt] [--owner-uuid U] [--all]` | Registered kbites at a scope, resolved through the inheritance chain at read time. Scope defaults to session; owner defaults to the current repo/branch context (prompt scope needs an explicit uuid). `--all` ignores scope and lists every kbite row in the db (the cleanup drift-check listing; not combinable with `--owner-uuid`). |
| `gm kbite add --code C [--scope S] [--owner-uuid U]` | Explicit-only registration at one scope (v11 model — never auto-add). Db-only — the db is the sole registry. Idempotent. |
| `gm kbite remove --code C [--scope S] [--owner-uuid U]` | Remove a kbite from one scope's registry. Db-only. |
| `gm kbite maw-open --name N [--maw-path P]` | Create the open-maw filesystem skeleton + MAW_INDEX.md (no db rows; maws are not tracked in the db). Path defaults to `$GMCC_KBITE_OPEN/{name}` — resolved client-side. KBITE_PURPOSE.md stays an interactive skill step. |
| `gm kbite digest --code C [--kbite-open-path P]` | One-step import: parse `*_chewed.md` under the scan root (default: the open maw) into kbite_resource / kbite_resource_file / keyword rows (full text inline for text types), then DELETE the chewed files. Raw sources are kept on disk; the db is canonical for digested text. Re-digesting a resource replaces its rows. The client-side follow-up (move raw sources open/ → digested/, delete the maw) lives in `/gm_crunch_digest`. |
| `gm kbite get --code C` | One kbite: resources, file stubs (names + summaries, NO content), keywords. |
| `gm kbite file-get --file-uuid U` | A single resource file including full content — the targeted load replacing "cat the chewed file". |
| `gm kbite search "<query>" [--kbite-uuids U...] [--limit N]` | FTS5 full-text search across kbite files; bm25-ranked stubs (name ≫ summary ≫ content) with attached keywords. Omit `--kbite-uuids` to search everything. |
| `gm kbite keyword-tag --level kbite\|file --target-uuid U --keywords K... [--detach]` | Attach/detach normalized snake_case keywords at kbite or resource-file level. |

Exit codes: `0` ok · `1` generic/db/domain error · `2` daemon unreachable
after autostart · `3` unrecoverable protocol mismatch · `64` bad flags/usage
(ArgumentParser validation).

Domain error codes (typed, branch on these — never parse messages):
`NOT_FOUND`, `VERSION_CONFLICT` (stale `--expected-version`),
`INVALID_TRANSITION` (illegal status jump), `CONTENT_LOCKED` (content edit
outside Draft).

**GM task rule**: bot workflows should record their file edits with
`gm file-change add` as they make them (mirrors the session_data
`changed_files:` bookkeeping into the db), passing `--prompt-uuid` when a
daemon-side prompt row exists so per-prompt change summaries populate.

## Self-heal rule

If `~/gmcc/bin/gm` is missing, or any `gm` call exits 2 with a
"daemon binary missing" message, build first:

```bash
bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
```

The script is staleness-checked (no-ops when binaries are current; `--force`
to override), stamps BuildInfo (git sha + date, returned by `gm ping`), and
installs both binaries into `~/gmcc/bin/`. After a rebuild, the next `gm`
command retires the stale daemon automatically via the handshake.

The SessionStart hook `scripts/check_daemon_stale.sh` prints a warning when
binaries are missing/stale — treat that warning as a prompt to run the build.

Two lifecycle commands wrap these rules end-to-end:
`/refresh_daemon_state` (build if stale + restart if the running build
predates the installed binaries + verify) and `/archive_gmcc_daemon_data`
(stop → move `gmcc.db*` + `daemon.log` to `~/gmcc/_archive/cold_storage/{ts}/`
→ restart on a fresh db; never touches the ckfs yaml tree).

**Schema re-baseline rule**: while the db is pre-trust, schema changes are
folded into the single m0001 migration — every re-baseline requires deleting
`~/gmcc/gmcc.db*` (db, -wal, -shm) before restarting the daemon. If
prompt/kbite commands fail with "no such column" DB_ERRORs after an upgrade,
the db predates the current re-baseline: stop the daemon, delete the db
files, and let the next `gm` call recreate everything.

## Inspecting the db (read-only)

For debugging you may READ the db directly (`sqlite3 ~/gmcc/gmcc.db`), but
NEVER write to it from outside the daemon — all writes go through `gm`.
Schema: BaseEntity wrap (id serial PK, uuid v4 join key, version — the
optimistic-concurrency token, created_at/updated_at) on every domain table;
all FKs reference `uuid`. Tables: project, instance, session, prompt,
prompt_artifact, kbite, {prompt,session,instance,project}_active_kbite,
keyword, kbite_keyword_junction, kbite_resource, kbite_resource_file,
resource_file_keyword_junction, kbite_resource_file_fts (FTS5 mirror backing
KBITE_SEARCH, trigger-synced), session_file, file_change, file_change_range,
daemon_event (append-only — its `id` is the SUBSCRIBE replay cursor),
schema_migrations (unwrapped ledger).

## KBite data model (v16 prompt 4)

- Maws are NOT in the db — `maw-open` is filesystem-only, chew stays an
  external step writing `{name}_chewed.md` files.
- `digest` is the db-import step: the ENTIRE chewed body lands verbatim in
  `kbite_resource.resource_summary`; each RAW source file gets a
  `kbite_resource_file` row (content inline for text types ≤ 2 MB, NULL for
  images/binaries/oversized — the filesystem keeps those raw); chewed
  Keywords become normalized vocabulary rows + junctions at both kbite and
  file level; the chewed files are deleted only after the commit.
- resource_type mirrors axis2 (documentation|example_project|api_reference|
  blogs|all_others); resource_trust mirrors axis1 (0 = primary,
  100 = secondary; ints in between reserved).
- Discovery is SEARCH-first: `gm kbite search` → ranked file stubs →
  `gm kbite file-get` for full content. Browsing the digested filesystem
  tree is the legacy path.
