# CKFS Detailed Structure Reference (v6.0.0)

Read this file on-demand when performing ckfs operations.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest (currently v6.0.0)
├── skills/
│   ├── gmcc/SKILL.md              # Core rules (slim)
│   ├── gmcc/ref/                  # Reference files (read on-demand)
│   ├── gmcc_agent/                # Agent system definition
│   ├── gmcc_kbite/                # KBite knowledge system
│   ├── gmcc_maw/                  # KBite web-fetch skill
│   ├── gmcc_boot/                 # Boot validation
│   └── gmcc_cleanup/              # CKFS structure auditing
├── commands/gm_*.md               # All GM commands
├── prompts/gmcc_agent_*.md        # Agent prompt files
├── scripts/detect_repo.sh         # SessionStart hook script
├── hooks/hooks.json               # Hook configuration
├── output-styles/                 # Methodology output styles
└── templates/projects/            # Runtime-tree templates (copied lazily by detect_repo.sh)
```

## Runtime CKFS (Per-User, Per-Project)
```
~/gmcc_ckfs/                                             # $GMCC_CKFS_ROOT
├── README.md
├── projects/                                            # $GMCC_PROJECTS
│   ├── project_index.gmcc.yaml                               # $GMCC_PROJECTS_INDEX
│   └── {project_name}/                                  # $GMCC_PROJECT_PATH
│       ├── project_data.gmcc.yaml
│       └── instances/
│           └── {slug_of_abs_path}/                      # $GMCC_INSTANCE_PATH
│               ├── instance_data.gmcc.yaml
│               └── sessions/
│                   └── {sanitized_branch}/              # $GMCC_SESSION_PATH
│                       ├── session_data.gmcc.yaml
│                       └── prompts/
│                           ├── {id}_{name}.yaml             # draft
│                           └── {id}_{name}_clarified.yaml   # clarified
└── kbites/                                              # $GMCC_KBITE
    ├── {kbite_name}/KBITE_PURPOSE.md                    # identity-level
    ├── digested/{kbite_name}/...                        # $GMCC_KBITE_DIGESTED
    └── open/{kbite_name}/...                            # $GMCC_KBITE_OPEN
```

## Identity Resolution (How a path becomes a session)

`scripts/detect_repo.sh` runs on every SessionStart. Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `gmcc-marketplace` |
| `instance_id` | Slugified absolute path to the repo checkout | e.g. `Users__brycerubinson__Dev__gmcc-marketplace` |
| `session_branch` | Sanitized current git branch | e.g. `v4_2`, `feature__login` |

### Slugification Rules
- Replace every `/` with `__` (literal two underscores).
- Strip leading `__` (introduced by absolute paths' leading `/`).
- Implementation uses `sed 's|/|__|g'` — NOT `tr`, because `tr` is char-to-char and would collapse `/` into a single `_`.

A project corresponds to exactly one git repo (by basename). An instance is a unique filesystem checkout of that repo — moving the checkout to a new path creates a new instance. A session is one git branch within an instance.

## Lazy Creation by `detect_repo.sh`

On every SessionStart, the hook ensures the following exist for the current git context. All steps are idempotent:

1. `$GMCC_PROJECTS/` (created if missing — `/gm_init` does this normally; the hook is a safety net)
2. `$GMCC_PROJECTS_INDEX` (copied from `templates/projects/project_index.gmcc.yaml`)
3. `$GMCC_PROJECT_PATH/{project_data.gmcc.yaml, instances/}` (filled from `templates/projects/PROJECT_TEMPLATE/project_data.gmcc.yaml` with placeholder substitution)
4. `$GMCC_INSTANCE_PATH/{instance_data.gmcc.yaml, sessions/}` (filled from `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.gmcc.yaml`)
5. `$GMCC_SESSION_PATH/{session_data.gmcc.yaml, prompts/}` (filled from `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.gmcc.yaml`)
6. Append a project entry to `$GMCC_PROJECTS_INDEX` if new (idempotent grep-then-append)

This means **commands can always assume the layout exists** — no per-command init logic is needed.

## session_data.gmcc.yaml (Current Schema — v6.1.0)

Conforms to `gmcc.gmcc_session_data_file`. The file body unwraps `has_base_fields`
(serial id, code, uuid, name, description, created/updated time) and
`has_ckfs_paths`, plus branch / instance_uuid / project_uuid back-references
and the prompt/changed-files lists.

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_session_data_file

id: 1
code: {sanitized_branch}                       # was: branch (slug form)
uuid: {v4}
name: {display name — usually equal to code at creation}
description: ""
created_time: {ISO 8601}                       # was: started_at
updated_time: {ISO 8601}
gmcc_ckfs_absolute_path: {GMCC_SESSION_PATH}
gmcc_ckfs_relative_path: projects/{project}/instances/{instance}/sessions/{branch}
branch: {sanitized_branch}
instance_uuid: {v4}                            # back-ref to the parent instance
project_uuid: {v4}                             # back-ref to the parent project

# Prompts authored by bot workflows. Files live in ./prompts/.
prompts:
  - id: {monotonic int}
    name: {kebab-case slug}
    status: draft | clarified
    draft_file: prompts/{id}_{name}.yaml
    clarified_file: prompts/{id}_{name}_clarified.yaml   # present when status == clarified

# Files modified during this session.
changed_files:
  - file: {relative path inside the instance}
    timestamp: {ISO 8601}
    lines:
      - [start, end]
    commit: {short sha or "uncommitted"}
```

The other three runtime yamls share the same outer shape: `yeet:` /
`yeet_type:` headers, then `has_base_fields` + `has_ckfs_paths` fields,
plus extras declared by their YEETS type. The hierarchy is **owner-local**
— each file owns its direct children, not a deep tree:

- `project_index.gmcc.yaml` → flat list of project entries (identity only).
- `project_data.gmcc.yaml` → repo metadata + list of that project's instances.
- `instance_data.gmcc.yaml` → `has_system_path` + `project_uuid` back-reference + list of that instance's sessions.
- `session_data.gmcc.yaml` → standalone (no children list); carries `branch`, `instance_uuid`, `project_uuid` back-references plus the `prompts` / `changed_files` lists.

## Yaml Files (Editable By)

| File | Purpose | Maintained by |
|------|---------|---------------|
| `project_index.gmcc.yaml` | Flat registry of all projects (identity only) | `detect_repo.sh` (registers); `/gm_cleanup` (prunes) |
| `project_data.gmcc.yaml` | Per-project identity, repo metadata, instance list | `detect_repo.sh` (creates + appends instances); user or future commands (edits) |
| `instance_data.gmcc.yaml` | Per-instance identity, system path, session list | `detect_repo.sh` (creates + appends sessions); rarely edited |
| `session_data.gmcc.yaml` | Per-branch session state (prompts, changed files) | Bot workflows (continuous updates) |
| `prompts/*.yaml` | Per-prompt content (draft + clarified) | Bot workflows (immutable once clarified) |

## Prompts Lifecycle

Bot workflows author prompts in two stages:

1. **Draft** — `/gm_bot*` writes `$GMCC_SESSION_PATH/prompts/{id}_{name}.yaml` with the user's raw input. session_data.gmcc.yaml entry status = `draft`.
2. **Clarified** — After the Clarify phase, write `$GMCC_SESSION_PATH/prompts/{id}_{name}_clarified.yaml` with the refined prompt + Q/A pairs. session_data.gmcc.yaml entry status = `clarified`. The draft file is **not** modified — the clarified file is the new source of truth from this point on.

Workflow intermediate artifacts (exploration reports, architecture docs, review reports) are **not persisted to disk**. They live in conversation context only. Resume across sessions relies on session_data.gmcc.yaml prompt statuses and clarified prompt files.
