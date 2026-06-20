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
│   ├── project_index.yaml                               # $GMCC_PROJECTS_INDEX
│   └── {project_name}/                                  # $GMCC_PROJECT_PATH
│       ├── Project_Data.yaml
│       └── instances/
│           └── {slug_of_abs_path}/                      # $GMCC_INSTANCE_PATH
│               ├── instance_data.yaml
│               └── sessions/
│                   └── {sanitized_branch}/              # $GMCC_SESSION_PATH
│                       ├── session_data.yaml
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
2. `$GMCC_PROJECTS_INDEX` (copied from `templates/projects/project_index.yaml`)
3. `$GMCC_PROJECT_PATH/{Project_Data.yaml, instances/}` (filled from `templates/projects/PROJECT_TEMPLATE/Project_Data.yaml` with placeholder substitution)
4. `$GMCC_INSTANCE_PATH/{instance_data.yaml, sessions/}` (filled from `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/instance_data.yaml`)
5. `$GMCC_SESSION_PATH/{session_data.yaml, prompts/}` (filled from `templates/projects/PROJECT_TEMPLATE/instances/INSTANCE_TEMPLATE/sessions/SESSION_TEMPLATE/session_data.yaml`)
6. Append a project entry to `$GMCC_PROJECTS_INDEX` if new (idempotent grep-then-append)

This means **commands can always assume the layout exists** — no per-command init logic is needed.

## session_data.yaml (Current Schema)

Minimal v6.0.0 schema. Fuller schema design is deferred to a follow-up release.

```yaml
version: 1
branch: {sanitized_branch}
instance: {instance_id}
project: {project_name}
started_at: {ISO 8601}

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

## Yaml Files (Editable By)

| File | Purpose | Maintained by |
|------|---------|---------------|
| `project_index.yaml` | Registry of every project + instance | `detect_repo.sh` (registers); `/gm_cleanup` (prunes) |
| `Project_Data.yaml` | Per-project identity, metadata | `detect_repo.sh` (creates); user or future commands (edits) |
| `instance_data.yaml` | Per-instance identity, abs path | `detect_repo.sh` (creates); rarely edited |
| `session_data.yaml` | Per-branch session state (prompts, changed files) | Bot workflows (continuous updates) |
| `prompts/*.yaml` | Per-prompt content (draft + clarified) | Bot workflows (immutable once clarified) |

## Prompts Lifecycle

Bot workflows author prompts in two stages:

1. **Draft** — `/gm_bot*` writes `$GMCC_SESSION_PATH/prompts/{id}_{name}.yaml` with the user's raw input. session_data.yaml entry status = `draft`.
2. **Clarified** — After the Clarify phase, write `$GMCC_SESSION_PATH/prompts/{id}_{name}_clarified.yaml` with the refined prompt + Q/A pairs. session_data.yaml entry status = `clarified`. The draft file is **not** modified — the clarified file is the new source of truth from this point on.

Workflow intermediate artifacts (exploration reports, architecture docs, review reports) are **not persisted to disk in v6.0.0**. They live in conversation context only. Resume across sessions relies on session_data.yaml prompt statuses and clarified prompt files.

## Removed in v6.0.0 (no migration)

| Removed | What replaced it |
|---------|------------------|
| `$GMCC_FAM_PATH` | `$GMCC_SESSION_PATH` |
| `$GMCC_REPO_PATH` | `$GMCC_PROJECT_PATH` (note: per-project, not per-repo-checkout) |
| `$GMCC_REPO_ID` | `basename $GMCC_PROJECT_PATH` if needed |
| `$GMCC_ACTIVE_BRANCH` | `basename $GMCC_SESSION_PATH` if needed |
| `ChangedFiles.md` | `changed_files:` section in `session_data.yaml` |
| `thoughts/mem_{N}_{name}/` | `prompts/{id}_{name}.yaml` + clarified variant |
| `plugins/gmcc/ckfs_templates/` | `plugins/gmcc/templates/projects/` |

Old data on disk is left untouched. Use `/gm_cleanup` to audit and resolve it.
