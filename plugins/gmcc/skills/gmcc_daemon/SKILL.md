---
name: gmcc_daemon
description: How to invoke the GMCC daemon system - the gm CLI on the session PATH, its subcommands (context, session, prompt, clarify, arch, explore, review, artifact, file-change, kbite, events, config/paths, backup), the single-writer SQLite model, and the self-heal rule when binaries are missing or stale. Use whenever recording file changes to the daemon db, managing prompts/clarifications/architectures/artifacts/kbites over the daemon, searching kbite knowledge, checking daemon/db health, or building the daemon.
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
  and speaks the same protocol.

Transport: NDJSON over a unix socket at `~/gmcc/daemon.sock`. Clients
autostart the daemon when the socket is dead. The protocol handshake is
DIRECTIONAL: a newer client makes a stale daemon self-exit after rebuilds;
an older client is rejected while the daemon stays up — you never manage
daemon lifecycle manually. (The current wire version is whatever the
cheatsheet header says — never hardcode it in docs.)

Note: `~/gmcc/` (runtime: binaries, socket, db, log, pidfile, backups) is
distinct from `~/gmcc_ckfs/` (the CKFS tree). Neither is in git. The
daemon writes the db ONLY — it never touches ckfs files.

## Invocation pattern

Call the bare `gm` command — the session PATH (emitted by `gm context env`
at SessionStart) resolves it to the correct prod or sandbox binary:

```bash
gm <subcommand> [options]
```

Every subcommand accepts `--json` (the raw wire response — the form
skills/bots should parse).

**The signature reference is `gm cheatsheet --full`** — one exact-signature
line per verb plus the invariants, compiled into the binary so it cannot
drift from installed capabilities (pure client-side, works with the daemon
down; drift-guarded by `CheatsheetTests`). Bare `gm cheatsheet` is the
compact core (family index + agent pen verbs + invariants) that
SessionStart injects into every session — it is NOT the full surface.
Consult the sheet instead of `gm ... --help` roundtrips; never guess
flags, and never copy signatures from prose docs (including this one).

Exit codes: `0` ok · `1` generic/db/domain error · `2` daemon unreachable
after autostart · `3` unrecoverable protocol mismatch · `64` bad
flags/usage.

Domain error codes (typed, branch on these — never parse messages):
`NOT_FOUND` (the uuid itself is unknown), `VERSION_CONFLICT` (stale
`--expected-version` — re-run the matching get, take `.version`, retry),
`INVALID_TRANSITION` (illegal status jump; the reason names the legal next
states), `CONTENT_LOCKED` (content edit outside draft), `SUMMARY_ABSENT`
(the owner exists but that summary/scope was never opened — open it via
the family's `open`/`init` verb; never fall back to a file).

Workflow semantics (prompt lifecycle, pen contract, briefings, ratings)
live in `skills/gmcc/ref/bot_workflows.md`, not here. For editing the
repo's `.gmcc` dope files directly, load `skills/gmcc/ref/doped_files.md`.

## Build / self-heal

If `gm` is not found on the PATH, or any `gm` call exits 2 with a
"daemon binary missing" message, build first:

```bash
bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
```

The script is staleness-checked (no-ops when binaries are current;
`--force` to override), stamps BuildInfo (git sha + date, returned by
`gm ping`), and installs both binaries into `~/gmcc/bin/`. After a
rebuild, the next `gm` command retires the stale daemon automatically via
the handshake. The SessionStart hook `scripts/check_daemon_stale.sh`
prints a warning when binaries are missing/stale — treat it as a prompt
to run the build.

The full dev loop when changing daemon code:

```bash
cd $GMCC_PLUGIN_ROOT/daemon && swift test      # full suite; must stay green
bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh # release build → ~/gmcc/bin/
gm daemon restart                              # pick up the new daemon
```

Two lifecycle commands wrap these rules end-to-end:
`/refresh_daemon_state` (build if stale + restart if the running build
predates the installed binaries + verify) and `/archive_gmcc_daemon_data`
(stop → move `gmcc.db*` + `daemon.log` to `~/gmcc/_archive/cold_storage/{ts}/`
→ restart on a fresh db; never touches the ckfs tree).

**Schema migration rule (the re-baseline era is OVER)**: the db is
append-only — schema changes land as new migrations and existing databases
upgrade in place at daemon boot, preserving all data. **NEVER delete
`~/gmcc/gmcc.db*`** to fix a schema error; `gm backup` before risky work.
If commands fail with "no such column" DB_ERRORs after an upgrade, the
running daemon predates the installed binaries: run `/refresh_daemon_state`
so the new daemon applies its pending migrations.

## Inspecting the db (read-only)

For debugging you may READ the db directly (`sqlite3 ~/gmcc/gmcc.db`), but
NEVER write to it from outside the daemon — all writes go through `gm`.
Every domain table carries the BaseEntity wrap (id serial PK, uuid v4 join
key, version — the optimistic-concurrency token, created_at/updated_at);
all FKs reference `uuid`; `daemon_event.id` is the append-only event-log
replay cursor (`gm events --since-id`).
