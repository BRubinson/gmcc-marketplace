---
name: gmcc_daemon
description: How to invoke the GMCC daemon system - the gm CLI at ~/gmcc/bin/gm, its subcommands (context, session, prompt, clarify, arch, explore, review, artifact, file-change, kbite, events, config/paths, backup), the single-writer SQLite model, and the self-heal rule when binaries are missing or stale. Use whenever recording file changes to the daemon db, managing prompts/clarifications/architectures/artifacts/kbites over the daemon, searching kbite knowledge, checking daemon/db health, or building the daemon.
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
v8, schema m0003, one spec-named message per handler). Clients autostart the daemon when
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
| `gm status` | Daemon + db health: pid, protocol, socket, schema version, per-table row counts, and `last_event_id` — the REAL event-log horizon (highest daemon_event.id). `table_counts` is a row census and MUST NOT be used as an event cursor. |
| `gm setup [--launchd]` | Client-side init of `~/gmcc/` dirs + daemon autostart. `--launchd` installs a login agent. |
| `gm daemon start\|stop\|restart\|status` | Lifecycle. `stop` = SHUTDOWN: drain, WAL checkpoint, pidfile + socket removal, exit 0. |
| `gm backup` | SQLite online backup to a timestamped copy under `~/gmcc/backups/`. |
| `gm events [--kind K] [--subject-uuid U] [--since-id N] [--since-time T] [--until-time T] [--limit N] [--follow]` | Query the daemon_event audit log; `--follow` streams live (with `--since-id` replay — no missed events across reconnects). |
| `gm context ensure [--from-ckfs <projects/p/instances/i/sessions/s>]` | Upsert project → instance → session from the current repo/branch (idempotent; reuses ckfs uuids; seeds kbite inheritance at create time). Returns the uuid triple. `--from-ckfs` builds the chain from a legacy ckfs session directory instead of cwd git — the /import_legacy_yaml_gmcc backfill path. |
| `gm context get` | Read-only resolution of the current gmcc environment (never creates rows). |
| `gm project list` | All projects (full rows incl. ckfs paths), ordered by code — the Landing browse entry point. |
| `gm instance list [--project-uuid U]` | Instances, ordered by code. Omit the filter to list ALL instances (rows carry their project uuid); an unknown supplied uuid ⇒ NOT_FOUND. |
| `gm session list [--instance-uuid U]` | Session stubs (full scalars minus backstory/goal bodies), ordered by code, each carrying `last_activity_at` (latest of session update, prompt update, file change — the landing recency key). Same optional-filter contract as `gm instance list`. `status` is retired from the wire (v7); checked-out state is git-derived via `gm session resolve`. |
| `gm session resolve [--session-uuid U]` | Session row + git-derived checked-out state (reads `.git/HEAD` directly; worktree `gitdir:` handled; detached ⇒ none). Defaults to the current repo/branch session. Returns `current_branch` (the RAW branch, nil unless `head_state` is "branch") alongside the slugged `current_session_code` — the two are never interconverted client-side. |
| `gm instance current-session --instance-uuid U` | The session matching the instance's checked-out branch, or none (`head_state`: branch/detached/unavailable). Also returns `current_branch` (raw, nil unless on a branch). |
| `gm catalog search <query> [--project-uuid U] [--limit N]` | Tokenized OR name/code search over instances + sessions (case-insensitive literal substrings; wildcards escaped). An instance match returns ALL its sessions; every returned session's parent instance rides along. Unknown supplied project uuid ⇒ NOT_FOUND; whitespace-only query ⇒ BAD_REQUEST. |
| `gm session get [--session-uuid U]` | Session row + prompt stubs + change summaries (per-prompt where attributed). Always singular; the uuid defaults to the current repo/branch session. |
| `gm session update --expected-version N [--session-uuid U] [--name] [--backstory] [--goal]` | Guarded scalar update (at least one field required); stale version ⇒ VERSION_CONFLICT. Always singular; the uuid defaults to the current repo/branch session. |
| `gm prompt create --name N [--session-uuid U] [--code] [--backstory] [--goal] [--detail] [--command] [--uuid]` | Create a prompt; the daemon allocates the next per-session seq atomically. Session defaults to the current repo/branch. |
| `gm prompt list [--session-uuid U] [--all] [--with-reports]` | Lightweight stubs (uuid, session_uuid, seq, code, name, status, version, ckfs_relative_storage_path, `is_legacy`, created_at, updated_at). Session defaults to the current repo/branch — **not** every session in the db; `--all` lists every prompt in the db (stubs carry `session_uuid` for grouping; seq is only unique per session). `--all` is not combinable with `--session-uuid`; an unknown supplied uuid ⇒ NOT_FOUND, never a silent empty list. `--with-reports` attaches each prompt's clarification + architecture + exploration + review summary stubs (status, refined_goal/backstory_note, verdict, summary versions, question/change/finding counts incl. sub-100, unranked, and open-finding resume signals) — ONE call for the whole session's report state, replacing the per-prompt get fan-out. A nil report + `is_legacy: true` means pre-m0002 (read ckfs artifacts); nil + `is_legacy: false` means simply not opened yet (for exploration/review a pre-m0004 prompt's real report may be a file artifact — the mandatory migrate pass moves those into rows). |
| `gm prompt get --prompt-uuid U` | Full prompt + artifact pointers + kbites + change summary. |
| `gm prompt update-content --prompt-uuid U --expected-version N [--backstory] [--goal] [--detail]` | Draft-only edit of the STAY TRUE triple; CONTENT_LOCKED past draft (the ONE exemption: `gm clarify finalize` copies the refined goal into `prompt.goal` daemon-side). |
| `gm prompt set-status --prompt-uuid U --expected-version N --status S` | Lifecycle v2, forward-only + adjacent-only: draft → clarifying → architecting → implementing → reviewing → done, with one skip edge implementing → done (reviewing optional). THE single door for prompt transitions (clarify/arch verbs never move the prompt). Gates enforced in-transaction: entering `clarifying` creates the clarification summary; `clarifying → architecting` requires it `complete` (and creates the architecture summary); `architecting → implementing` requires the architecture `approved`. Pre-m0002 prompts bypass absent-backing-row gates (no synthetic rows are ever fabricated — the bot falls back to ckfs artifacts via `gm artifact list`). |
| `gm clarify open --prompt-uuid U` | Create-or-return the clarification summary (status `building`). Idempotent; never transitions the prompt. On a legacy prompt this is the explicit adoption path. |
| `gm clarify ask --summary-uuid S --category goal\|detail\|yeet_type --question Q [--answer A --source bot_inferred]` | Insert a question while `building` (pre-answered rows for confidently-resolved detections). |
| `gm clarify seal --summary-uuid S --expected-version N` | `building → answering`: lock the question list. |
| `gm clarify answer --clarification-uuid C --expected-version N [--answer A] [--source user\|bot_inferred] [--skip]` | Answer (or skip) one row; summary must be `answering`; `--expected-version` targets the clarification ROW. Revives a skipped row. |
| `gm clarify reopen --summary-uuid S --expected-version N` | `complete → answering`: the revision edge (re-finalize after). |
| `gm clarify finalize --summary-uuid S --expected-version N --refined-goal G --refined-detail D [--backstory-note]` | `answering → complete`: every non-skipped question must be answered, both refined fields non-empty; copies refined_goal into `prompt.goal`. |
| `gm clarify get --prompt-uuid U` | Summary + ordered clarification rows. A prompt with no summary ⇒ `SUMMARY_ABSENT` (see error codes): `prompt_is_legacy: true` ⇒ read the `qualified` artifact, never fabricate rows; `false` ⇒ `gm clarify open`. Plain NOT_FOUND now means only the uuid itself is unknown. |
| `gm arch open --prompt-uuid U` | Create-or-return the architecture summary (status `drafting`). Idempotent; never transitions the prompt. |
| `gm arch summarize --summary-uuid S --expected-version N --body B` | Concept-level body only (approach/components/flow/tradeoffs — file specifics belong in change rows). Drafting only. |
| `gm arch persist-add --summary-uuid S --class-name C --file-path P --reason R` | Persistence-layer change row (ORM/schema class). Paths are normalized repo-relative; absolute-outside-instance ⇒ BAD_REQUEST. |
| `gm arch field-add --persistence-uuid PC --field-name F --data-type T --reason R --purpose P --nullable\|--no-nullable [--foreign-key --fk-target t.col] [--indexed]` | Field-level row under a persistence change. |
| `gm arch general-add --summary-uuid S --file-path P [--class-name C] --reason R --depth pseudo\|draft\|actual --code CODE` | Non-persistence change with its change code (2 MB cap). |
| `gm arch propose --summary-uuid S --expected-version N` | `drafting → proposed`: change rows sealed for review. |
| `gm arch approve --summary-uuid S --expected-version N` | `proposed → approved` (terminal): unlocks `architecting → implementing`. |
| `gm arch revise --summary-uuid S --expected-version N` | `proposed → drafting`: the revision edge. |
| `gm arch get --prompt-uuid U` | Summary + ordered changes (persistence FIRST — the implementation order contract) each decorated with derived implementation state (`file_change_count`, `first/last_changed_at` from the path join), plus `unplanned_changes` (touched but not planned — scope drift) and `ordering_respected` (persistence-first audit). Comparison joins on daemon-normalized repo-relative paths and sees only file changes recorded with `--prompt-uuid`. No summary ⇒ `SUMMARY_ABSENT` with `prompt_is_legacy` (same branch rule as `gm clarify get`). |
| `gm explore open --prompt-uuid U` | Create-or-return the exploration summary (status `exploring`). Idempotent, EXPLICIT-only — prompt transitions never create it (exploration runs while the prompt is still `draft`); never transitions the prompt. |
| `gm explore key-file-add --summary-uuid S --file-path P` | Add one key file (summary must be `exploring`). Deduped set: a duplicate path is an idempotent upsert-ignore returning the existing row (`created: false`), never an error. Paths normalized repo-relative. |
| `gm explore finding-add --summary-uuid S --kind persistence_model\|implementation_pattern\|existing_functionality\|scope_creep_risk\|general_relevant_change\|other --title T --body B --agent-name A [--rating 0-999]` | Insert a finding while `exploring`. Rating optional — NULL marks it unranked (work-in-progress); bodies capped at 2 MB. `--agent-name` is the producing persona (self-reported). |
| `gm explore rank --summary-uuid S --rating <finding-uuid>:<0-999> ...` | Atomic version-less batch rank (0 = critical … 999 = always-false-positive tombstone; read threshold 100). Whole batch validates first — one bad pair (range, duplicate, or finding not belonging to this summary) rejects everything. Refused once `complete` (reopen first); re-running re-ranks (last write wins — the team re-ranker's contract). |
| `gm explore complete --summary-uuid S --expected-version N --overview O` | `exploring → complete`: REFUSES while any finding is unranked; the overview (2 MB cap) is writable ONLY here — primary-agent-only by write-path shape. |
| `gm explore reopen --summary-uuid S --expected-version N` | `complete → exploring`: the revision edge for re-runs. Everything is preserved (findings, ratings, key files, overview); the next complete must re-carry the overview. |
| `gm explore get --prompt-uuid U [--full \| --max-rating N \| --rating-range A:B]` | Summary + key files + findings, PARTITIONED server-side: full rows for ratings inside the window (default under 100) PLUS every unranked row (always full — the resume work-queue), title/kind/rating stubs outside it. No summary ⇒ `SUMMARY_ABSENT` with `prompt_is_legacy` (non-legacy message also steers pre-m0004 prompts with on-disk reports to the migrate pass). |
| `gm review open --prompt-uuid U` | Create-or-return the review summary (status `reviewing`). Idempotent, EXPLICIT-only — prompt status never creates or gates it (skip-to-done runs simply never open one). |
| `gm review finding-add --summary-uuid S --kind correctness_bug\|spec_deviation\|regression_risk\|security\|simplification\|other --title T --body B [--file-path P --line-start N [--line-end M]] --agent-name A [--rating 0-999]` | Insert a finding while `reviewing`. file/line fields optional (nil = cross-cutting); line_end requires line_start. |
| `gm review rank --summary-uuid S --rating <uuid>:<n> ...` | Same batch contract as `gm explore rank`. |
| `gm review resolve --finding-uuid F --expected-version N --status fixed\|accepted\|wont_fix` | Record one finding's fix-loop outcome. Pure child update (`--expected-version` targets the FINDING) and deliberately UNGATED on summary status — the fix loop runs AFTER complete. Edges: open → fixed\|accepted\|wont_fix + lateral corrections among resolved values, never back to open. |
| `gm review complete --summary-uuid S --expected-version N --overview O --verdict approved\|approved_with_nits\|changes_requested` | `reviewing → complete`: refuses unranked findings; requires the verdict. overview + verdict writable ONLY here (`legacy_unstated` is the migrate pass's verdict for files that never state one). |
| `gm review reopen --summary-uuid S --expected-version N` | `complete → reviewing`: revision edge, same preservation contract as explore. |
| `gm review get --prompt-uuid U [--full \| --max-rating N \| --rating-range A:B]` | Same partitioned read as explore get; stubs additionally carry each finding's resolution status for the fix loop. |
| `gm search "<query>" [--all] [--session-uuid U] [--kind K...] [--limit N]` | FTS5 full-text search over prompt name/goal/detail/backstory, clarification questions/answers/refined fields, architecture bodies/reasons/change code, exploration overviews/key files/findings, and review overviews/findings. bm25-ranked stubs with prompt lineage (prompt uuid/seq/name/status, session) and a bounded excerpt — never full content. Scope defaults to the current repo/branch session; `--all` for the whole db (not combinable with `--session-uuid`). Kinds: prompt, clarification, clarification_summary, architecture_summary, architecture_general_change, architecture_persistence_change, exploration_summary, exploration_key_file, exploration_finding, review_summary, review_finding. Whitespace-only query ⇒ BAD_REQUEST; unknown supplied session uuid ⇒ NOT_FOUND. Scores are comparable only within a kind. |
| `gm paths` | The daemon's typed roots: gmcc runtime, db, socket, backups (from conventions) + ckfs/kbite roots (from db-backed config). |
| `gm config set --key ckfs_root\|kbite_root\|kbite_open_root\|kbite_digested_root --value V` | Write one config key (enum-bound; unknown ⇒ BAD_REQUEST). The daemon never reads `$GMCC_*` env vars. |
| `gm artifact add --prompt-uuid U --file-path P --kind explore\|architecture\|review\|qualified\|other [--note]` | Register a bot-phase memory/ file pointer (content stays in the file). ALL four report kinds (`qualified`/`architecture`/`explore`/`review`) are RESERVED for pre-migration legacy files — NEVER write a qualified.md/architecture.md/explore.md/review.md mirror for a post-migration prompt (the db-native rows ARE the record; `gm clarify/arch/explore/review get` are the render). |
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
`NOT_FOUND` (the uuid itself is unknown), `VERSION_CONFLICT` (stale
`--expected-version`), `INVALID_TRANSITION` (illegal status jump — reasons
are now human-phrased and name the legal next states), `CONTENT_LOCKED`
(content edit outside Draft), `SUMMARY_ABSENT` (the prompt exists but has no
clarification/architecture/exploration/review summary; the payload's
`prompt_is_legacy` says which case: `true` ⇒ read the ckfs artifact via
`gm artifact list`, never fabricate rows; `false` ⇒ open one via the
family's `open` verb — except for exploration/review on a pre-m0004 prompt,
whose real report may be an on-disk file: check `gm artifact list` and run
the mandatory migrate pass instead of opening a fresh empty summary).

**Storage path contract (A4)**: `gm prompt create` derives and returns
`ckfs_relative_storage_path`, SLUGGING the name (forward-only and lossy, like
branch → session code). The memory watcher resolves prompts by EXACT
case-sensitive equality against that stored value, so clients MUST mkdir the
returned path verbatim (relative to `gm paths` → ckfs_root) and MUST NOT
re-derive `{seq}_{name}` themselves. Existing rows are untouched.

**Ephemeral events (id 0, never a daemon_event row, never a replay cursor)**:
`PROMPT_MEMORY_CHANGED` (a prompt's memory/ subtree changed on disk) and
`CHECKOUT_CHANGE` (an instance repo's HEAD changed; subject = instance uuid;
payload carries `head_state` / `current_branch` / `current_session_code`).
Clients subscribe instead of running their own .git watchers; on reconnect
ask `gm instance current-session` once rather than replaying. The watcher set
re-roots itself on `CONFIG_SET ckfs_root` and rebuilds on instance creation —
no daemon restart needed.

**GM task rule**: bot workflows record their file edits with
`gm file-change add` as they make them, **always passing `--prompt-uuid`** —
the `gm arch get` implementation-state comparison joins on prompt-attributed
changes only, so an unattributed change is invisible to it. Paths are
repo-relative (the daemon normalizes absolute-inside-instance and rejects
anything it can't anchor).

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

**Schema migration rule (the re-baseline era is OVER)**: since m0002 the db
is append-only — schema changes land as new migrations and existing databases
upgrade in place at daemon boot, preserving all data. **NEVER delete
`~/gmcc/gmcc.db*`** to fix a schema error. If prompt/kbite commands fail with
"no such column" DB_ERRORs after an upgrade, the running daemon predates the
installed binaries: run `/refresh_daemon_state` (rebuild + restart) so the new
daemon applies its pending migrations.

## Inspecting the db (read-only)

For debugging you may READ the db directly (`sqlite3 ~/gmcc/gmcc.db`), but
NEVER write to it from outside the daemon — all writes go through `gm`.
Schema: BaseEntity wrap (id serial PK, uuid v4 join key, version — the
optimistic-concurrency token, created_at/updated_at) on every domain table;
all FKs reference `uuid`. Tables: project, instance, session, prompt,
prompt_artifact, clarification_summary, clarification, architecture_summary,
architecture_persistence_change, architecture_persistence_field_change,
architecture_general_change, daemon_config, kbite,
{prompt,session,instance,project}_active_kbite,
keyword, kbite_keyword_junction, kbite_resource, kbite_resource_file,
resource_file_keyword_junction, kbite_resource_file_fts (FTS5 mirror backing
KBITE_SEARCH, trigger-synced), prompt_fts, clarification_summary_fts,
clarification_fts, architecture_summary_fts, architecture_general_change_fts,
architecture_persistence_change_fts (six FTS5 mirrors backing SEARCH,
trigger-synced, backfilled once by m0003), session_file, file_change,
file_change_range, daemon_event (append-only — its `id` is the SUBSCRIBE
replay cursor), schema_migrations (unwrapped ledger).

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
