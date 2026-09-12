# CKFS Detailed Structure Reference

Read this file on-demand when performing ckfs operations.

Prompt/session/instance/project data AND all four bot reports live in the
daemon's SQLite db at `~/gmcc/gmcc.db`, accessed exclusively through the
`gm` CLI (see `skills/gmcc_daemon/SKILL.md`). The ckfs on disk is a **file
tree only** — prompt-scoped scratch files under `memory/`, plus the kbite
content store.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest
├── skills/
│   ├── gmcc/SKILL.md              # Core rules (slim)
│   ├── gmcc/ref/                  # Reference files (read on-demand)
│   ├── gmcc_daemon/               # gm CLI + daemon invocation reference
│   ├── gmcc_kbite/                # KBite knowledge system
│   ├── gmcc_maw/                  # KBite web-fetch skill
│   ├── gmcc_boot/                 # Boot validation
│   └── gmcc_cleanup/              # Environment auditing
├── commands/gm_*.md               # All GM commands
├── agents/*.md                    # Native agent defs (gmcc:code-explorer, doper, …) — identity + pen contract
├── prompts/gmcc_agent_*.md        # Crunch/maw agent prompts (the bot roles moved to agents/)
├── scripts/gmcc_session_startup.sh         # SessionStart hook script
├── scripts/gmcc_hook.sh                    # Every non-SessionStart hook; event as argv, payload to `gm hook`
├── scripts/build_daemon.sh        # Daemon/gm build + install
├── scripts/check_daemon_stale.sh  # SessionStart staleness warning
├── daemon/                        # Swift package: gmcc_daemon + gm + GMCCDaemonKit
└── hooks/hooks.json               # Hook configuration (SessionStart, SubagentStart, PreToolUse, PostToolUse)
```

## Runtime Layout (Per-User)
```
~/gmcc/                                                       # daemon runtime (NOT in git)
├── bin/{gm, gmcc_daemon}
├── gmcc.db                                                   # SQLite — single source of truth for runtime data
├── daemon.sock · daemon.log · daemon.pid · backups/

~/gmcc_ckfs/                                                  # $GMCC_CKFS_ROOT — file artifacts only
├── README.md
├── _archive/cold_storage/                                    # universal archive bucket (structure-preserving)
├── projects/
│   └── {project_name}/                                       # project ckfs_relative_storage_path (gm context get --json)
│       └── instances/
│           └── {project_name}_{hash4}/                       # instance ckfs_relative_storage_path
│               └── sessions/
│                   └── {sanitized_branch}/                   # session's artifact home (ckfs_relative_storage_path from gm session get --json)
│                       └── prompts/
│                           └── {id}_{name}/                  # one folder per prompt
│                               └── memory/                  # usually empty — every report
│                                                             # is a db row
└── kbites/                                                   # kbite_root (gm paths --json)
    ├── {kbite_name}/KBITE_PURPOSE.md                         # identity-level
    ├── digested/{kbite_name}/...                             # kbite_digested_root — raw-source archive (text is db-canonical)
    └── open/{kbite_name}/...                                 # kbite_open_root — in-progress maws
```

The db stores **pointers + captions** to the `memory/*.md` files
(`prompt_artifact` rows) — never their bodies. The daemon never writes
files; bot workflows create the folders and write the markdown, then
register each file with `gm artifact add`.

## Identity Resolution (How a path becomes a session)

Identity is derived daemon-side by `gm context ensure`
(`GitContext`/`ContextBuilder` in Swift). Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `gmcc-marketplace` |
| `instance_code` | `{project_name}_{4-char hash of abs path}` | e.g. `gmcc-marketplace_a3f2` |
| `session_code` | Sanitized current git branch | e.g. `v4_2`, `feature__login` |

### Instance Code Algorithm

```
INSTANCE_CODE = "{basename($REPO_ROOT)}_{first 4 chars of md5($REPO_ROOT)}"
```

- Deterministic from `$REPO_ROOT` (always re-derivable).
- Collision-resistant: requires two repos with the same basename AND the same 4-char hash.
- Machine-safe by construction: only `[a-z0-9\-_]` characters from the basename + hex hash.

### Branch Slugification Rules
- Replace every `/` with `__` (literal two underscores).
- Implementation uses `sed 's|/|__|g'` — NOT `tr`, because `tr` is char-to-char and would collapse `/` into a single `_`.

A project corresponds to exactly one git repo (by basename). An instance is a unique filesystem checkout of that repo — moving the checkout to a new path creates a new instance. A session is one git branch within an instance.

## Lazy Creation on SessionStart

On every SessionStart, `gmcc_session_startup.sh`:

1. Confirms the git repo, locates the plugin root, and locates the right
   `gm` binary (prod runtime, or the sandbox runtime named by a
   `.gmcc_sandbox` marker). It computes nothing the daemon computes.
2. Calls `gm context ensure` (best-effort): idempotently upserts the
   project → instance → session rows in the db (reusing existing uuids,
   seeding kbite inheritance at create time), creates the session's
   artifact home (`{ckfs_relative_storage_path}/prompts/` under
   `$GMCC_CKFS_ROOT` — the physical home for prompt `memory/` folders),
   and runs the dope boot sync. If the daemon/binary is unavailable it
   warns and continues.
3. Emits the session env via `gm context env` into `$CLAUDE_ENV_FILE`:
   `GMCC_BOOTED`, `GMCC_PLUGIN_ROOT`, `GMCC_CKFS_ROOT`, `PATH` (so bare
   `gm` resolves to the correct prod/sandbox binary), plus `GMCC_ROOT`
   when sandboxed. Per-level path vars are retired — roots come from
   `gm paths` and per-row locations from `ckfs_relative_storage_path`.

This means **commands can always assume the env + session dir exist**;
db rows exist whenever the daemon was reachable at SessionStart (and
`gm context ensure` may be re-run by any command at any time — it is
idempotent).

## Db-Backed Data Model

Rows follow the BaseEntity wrap (`id` serial PK, `uuid` v4 join key,
`version` optimistic-concurrency token, `created_at`/`updated_at`).
Hierarchy: `project → instance → session → prompt`, plus
`prompt_artifact` (file pointers), `session_file`/`file_change`/
`file_change_range` (edit tracking), `kbite` + `*_active_kbite`
junctions (registry), `daemon_event` (append-only audit log).

Key reads (all support `--json`):

```bash
gm context get                       # uuid triple + kbite codes for cwd
gm session get [--session-uuid U]    # session row + prompt stubs + change summaries
gm prompt list [--session-uuid U]    # stubs: uuid, seq, code, name, status, version
gm prompt get --prompt-uuid U        # full content + artifacts + kbites + change summary
gm artifact list --prompt-uuid U
gm file-change list [--prompt-uuid U] [--path P]
```

### Optimistic concurrency (`--expected-version`)

Every mutation (`gm session update`, `gm prompt update-content`,
`gm prompt set-status`) requires `--expected-version N` — the row
version the edit was based on. Capture `.version` from the `--json`
output of the previous `create`/`get`/mutation (a fresh `create` returns
`version: 0`; each mutation returns the incremented version). A stale
version yields `VERSION_CONFLICT`: re-`get` and retry.

## Prompt Folder Layout (v19)

Each prompt is a folder whose `memory/` subdir is usually EMPTY now:

```
prompts/{id}_{name}/
    memory/                          # prompt-scoped scratch files only
```

(All four phase reports are DB-NATIVE — `gm clarify` / `gm arch` /
`gm explore` / `gm review` rows. NEVER write a report as a file here. The
mkdir of memory/ at prompt creation stays: it is where any other
prompt-scoped file you register with `gm artifact add` lands.)

`{id}` is the db prompt row's `seq`; `{name}` its `name`. All identity,
content (`backstory`/`goal`/`detail`), status, and command live on the
prompt row. Any file you write under `memory/` is registered with:

```bash
gm artifact add --prompt-uuid U --file-path <abs path> \
  --note "<one-sentence caption>"
```

(Upserts on `(prompt_uuid, file_path)` — last-run-wins overwrite of the
file is fine; re-register to refresh the note.)

## Prompt Lifecycle (v16)

Statuses are lowercase (lifecycle v2): `draft → clarifying → architecting
→ implementing → reviewing → done`, forward-only + adjacent-only with one
skip edge `implementing → done` (reviewing optional); `INVALID_TRANSITION`
otherwise. Content edits are draft-only (`CONTENT_LOCKED` after; the one
exemption is `gm clarify finalize`'s daemon-side refined-goal copy).
Gates: entering `clarifying` creates the clarification summary;
`clarifying → architecting` requires it complete; `architecting →
implementing` requires the architecture approved. There is no bypass — an
absent backing row fails the gate.

1. **draft** — `/gm_bot*` runs:
   ```bash
   gm prompt create --name {name} --detail "<passed prompt, verbatim>" \
     [--backstory "<inherited session backstory>"] --command /gm_bot* --json
   ```
   STAY TRUE: `detail` = the entire passed prompt verbatim; `goal` = ""
   (human/Clarify input only); `backstory` inherited from the session row.
   Never split, infer, or author these fields. Then
   `mkdir -p prompts/{seq}_{name}/memory/`.
2. **clarifying** — enter with `gm prompt set-status ... --status
   clarifying` (a gate verb with no pen tool — the primary's door, not an
   agent write path; it locks content and the daemon creates the summary).
   The clarifier then pens `mcp__plugin_gmcc_pen__clarify_question_add`
   (+ option rows) and `mcp__plugin_gmcc_pen__clarify_note_add`; `gm
   clarify seal`; user answers via `gm clarify answer` (--select /
   --answer); optional care package; `gm clarify finalize` is a PURE GATE
   — nothing ever writes prompt content past draft (STAY TRUE).
3. **architecting → implementing → reviewing → done** — `gm arch`
   authoring (persistence rows first) → propose/approve → implement
   (file changes always `--prompt-uuid`) → optional review → done,
   threading `--expected-version` through each step.

Resume across sessions relies on `gm prompt get` (status, content,
artifact pointers) plus the persisted `memory/` files.

## File Change Tracking

After each Edit/Write to a tracked file, bot workflows record through the
pen — `file_change_add` is the write path for anything spawned:

```
mcp__plugin_gmcc_pen__file_change_add
  path: <repo-relative>   kind: edit|create|delete|rename
  [ranges: start:end ...] [content: "<note>"] prompt_uuid: <U>
```

Run from inside the repo — git context is auto-detected. `--content`
requires EXACTLY ONE `--range`. There is no `phase_history` equivalent —
run completion is prompt status `done` plus the clarification/architecture/
exploration/review rows and registered artifacts.
`gm arch get` derives per-change implementation state from these records.

## KBite Registry

Kbites are inherited at create time down the chain
(project → instance → session → prompt) into the `*_active_kbite`
junction tables; after seeding, each level is independent. The db is the
sole registry. Read the active list from `gm context get` / `gm session get` / `gm prompt get`
(`kbite_codes`) or `gm kbite list --scope ...` (`--all` for every kbite
row in the db). Kbites are added only on explicit user request
(`gm kbite add`) — see `ref/kbite_awareness.md`. Digested kbite text is
db-canonical: load it via `gm kbite get / search / file-get`, not from
the filesystem.
