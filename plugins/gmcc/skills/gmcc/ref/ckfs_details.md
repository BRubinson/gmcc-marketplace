# CKFS Detailed Structure Reference (v16.3.0)

Read this file on-demand when performing ckfs operations.

**v16 model**: prompt/session/instance/project DATA lives in the daemon's
SQLite db at `~/gmcc/gmcc.db`, accessed exclusively through the `gm` CLI
(see `skills/gmcc_daemon/SKILL.md`). The ckfs on disk is now a **file
artifact tree only** — bot phase artifacts under `memory/`, plus the kbite
content store. The runtime yamls (`session_data.gmcc.yaml`, the prompt
yaml triad, `project_index`/`project_data`/`instance_data`,
`gmcc_session_file_index.yaml`) are RETIRED: nothing creates or updates
them anymore. Legacy trees are imported/archived by
`/import_legacy_yaml_gmcc` + `/archive_legacy_yaml_gmcc`.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest
├── skills/
│   ├── gmcc/SKILL.md              # Core rules (slim)
│   ├── gmcc/ref/                  # Reference files (read on-demand)
│   ├── gmcc_agent/                # Agent system definition
│   ├── gmcc_daemon/               # gm CLI + daemon invocation reference
│   ├── gmcc_kbite/                # KBite knowledge system
│   ├── gmcc_maw/                  # KBite web-fetch skill
│   ├── gmcc_boot/                 # Boot validation
│   ├── gmcc_cleanup/              # Environment auditing
│   └── gmcc_migrate_legacy/       # Legacy yaml → db import/archive (inert)
├── commands/gm_*.md               # All GM commands
├── prompts/gmcc_agent_*.md        # Agent prompt files
├── scripts/detect_repo.sh         # SessionStart hook script
├── scripts/build_daemon.sh        # Daemon/gm build + install
├── scripts/check_daemon_stale.sh  # SessionStart staleness warning
├── daemon/                        # Swift package: gmcc_daemon + gm + GMCCDaemonKit
├── hooks/hooks.json               # Hook configuration
└── output-styles/                 # Methodology output styles
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
├── projects/                                                 # $GMCC_PROJECTS
│   └── {project_name}/                                       # $GMCC_PROJECT_PATH
│       └── instances/
│           └── {project_name}_{hash4}/                       # $GMCC_INSTANCE_PATH
│               └── sessions/
│                   └── {sanitized_branch}/                   # $GMCC_SESSION_PATH
│                       └── prompts/
│                           └── {id}_{name}/                  # one folder per prompt
│                               └── memory/
│                                   ├── explore.md            # Phase 2 artifact
│                                   ├── qualified.md          # Phase 3 (Clarify) artifact
│                                   ├── architecture.md       # Phase 4 artifact
│                                   └── review.md             # Phase 6 artifact
└── kbites/                                                   # $GMCC_KBITE
    ├── {kbite_name}/KBITE_PURPOSE.md                         # identity-level
    ├── digested/{kbite_name}/...                             # $GMCC_KBITE_DIGESTED — raw-source archive (text is db-canonical)
    └── open/{kbite_name}/...                                 # $GMCC_KBITE_OPEN — in-progress maws
```

The db stores **pointers + captions** to the `memory/*.md` files
(`prompt_artifact` rows) — never their bodies. The daemon never writes
files; bot workflows create the folders and write the markdown, then
register each file with `gm artifact add`.

## Identity Resolution (How a path becomes a session)

`scripts/detect_repo.sh` runs on every SessionStart. Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `gmcc-marketplace` |
| `instance_code` | `{project_name}_{4-char hash of abs path}` | e.g. `gmcc-marketplace_a3f2` |
| `session_code` | Sanitized current git branch | e.g. `v4_2`, `feature__login` |

### Instance Code Algorithm

```
INSTANCE_CODE = "{basename($REPO_ROOT)}_{first 4 chars of md5($REPO_ROOT)}"
```

- Deterministic from `$REPO_ROOT` (the hook can always re-derive it).
- Collision-resistant: requires two repos with the same basename AND the same 4-char hash.
- Machine-safe by construction: only `[a-z0-9\-_]` characters from the basename + hex hash.

The `gm` CLI independently re-derives the same codes in Swift
(`GitContext`/`ContextBuilder`) — the bash and Swift implementations MUST
stay in lockstep.

### Branch Slugification Rules
- Replace every `/` with `__` (literal two underscores).
- Implementation uses `sed 's|/|__|g'` — NOT `tr`, because `tr` is char-to-char and would collapse `/` into a single `_`.

A project corresponds to exactly one git repo (by basename). An instance is a unique filesystem checkout of that repo — moving the checkout to a new path creates a new instance. A session is one git branch within an instance.

## Lazy Creation on SessionStart

On every SessionStart, `detect_repo.sh`:

1. Derives all `GMCC_*` paths (string logic only — no db round-trip) and
   exports them to `$CLAUDE_ENV_FILE`.
2. `mkdir -p "$GMCC_SESSION_PATH/prompts"` — the physical home for
   prompt `memory/` folders.
3. Calls `~/gmcc/bin/gm context ensure` (best-effort): idempotently
   upserts the project → instance → session rows in the db, reusing
   existing uuids and seeding kbite inheritance at create time. If the
   daemon/binary is unavailable it warns and continues — env export is
   never blocked.

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

## Prompt Folder Layout (v16)

Each prompt is a folder holding ONLY phase artifacts:

```
prompts/{id}_{name}/
    memory/
        explore.md                   # Phase 2 artifact
        qualified.md                 # Phase 3 (Clarify) output — Q/A suites, refined goal/detail, detected yeet types
        architecture.md              # Phase 4 artifact (after approval)
        review.md                    # Phase 6 artifact
```

`{id}` is the db prompt row's `seq`; `{name}` its `name`. All identity,
content (`backstory`/`goal`/`detail`), status, and command live on the
prompt row. Each `memory/*.md` write is registered with:

```bash
gm artifact add --prompt-uuid U --file-path <abs path> \
  --kind explore|architecture|review|qualified|other --note "<one-sentence caption>"
```

(Upserts on `(prompt_uuid, file_path)` — last-run-wins overwrite of the
file is fine; re-register to refresh the note.)

## Prompt Lifecycle (v16)

Statuses are lowercase: `draft → clarifying → clarified` (forward-only;
`INVALID_TRANSITION` otherwise). Content edits are draft-only
(`CONTENT_LOCKED` after).

1. **draft** — `/gm_bot*` runs:
   ```bash
   gm prompt create --name {name} --detail "<passed prompt, verbatim>" \
     [--backstory "<inherited session backstory>"] --command /gm_bot* --json
   ```
   STAY TRUE: `detail` = the entire passed prompt verbatim; `goal` = ""
   (human/Clarify input only); `backstory` inherited from the session row.
   Never split, infer, or author these fields. Then
   `mkdir -p prompts/{seq}_{name}/memory/`.
2. **clarifying/clarified** — Phase 3's first step is YEET-type detection
   over the prompt row's `goal` + `detail`; then separate goal and detail
   clarification suites. While still `draft` (content unlocked):
   - write `memory/qualified.md` (clarifications, refined_goal,
     refined_detail, detected_yeet_types, key_files, constraints) and
     register it (`--kind qualified`);
   - `gm prompt update-content --expected-version N --goal "<refined_goal>"`
     — goal only; `detail` stays the verbatim original (STAY TRUE).
     `refined_detail` lives in `qualified.md`, the from-Clarify source of
     truth;
   - `gm prompt set-status ... --status clarifying` then
     `... --status clarified`, threading `--expected-version` through each
     step.

Resume across sessions relies on `gm prompt get` (status, content,
artifact pointers) plus the persisted `memory/` files.

## File Change Tracking

After each Edit/Write to a tracked file, bot workflows record:

```bash
gm file-change add --path <repo-relative> --kind edit|create|delete|rename \
  [--range start:end]... [--content "<note>"] --prompt-uuid <U>
```

Run from inside the repo — git context is auto-detected. This replaces
the retired `changed_files:` yaml list. There is no `phase_history`
equivalent — run completion is represented by prompt status `clarified`
plus registered artifacts.

## KBite Registry

Kbites are inherited at create time down the chain
(project → instance → session → prompt) into the `*_active_kbite`
junction tables; after seeding, each level is independent. The db is the
sole registry — the only remaining yaml `kbite:` reads are inside
`gm context ensure --from-ckfs` (the legacy-import seed). Read the
active list from `gm context get` / `gm session get` / `gm prompt get`
(`kbite_codes`) or `gm kbite list --scope ...` (`--all` for every kbite
row in the db). Kbites are added only on explicit user request
(`gm kbite add`) — see `ref/kbite_awareness.md`. Digested kbite text is
db-canonical: load it via `gm kbite get / search / file-get`, not from
the filesystem.
