# CKFS Detailed Structure Reference (v13.0.0)

Read this file on-demand when performing ckfs operations.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest (currently v13.0.0)
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
~/gmcc_ckfs/                                                  # $GMCC_CKFS_ROOT
├── README.md
├── projects/                                                 # $GMCC_PROJECTS
│   ├── project_index.gmcc.yaml                                    # $GMCC_PROJECTS_INDEX
│   └── {project_name}/                                       # $GMCC_PROJECT_PATH
│       ├── project_data.gmcc.yaml
│       └── instances/
│           └── {project_name}_{hash4}/                       # $GMCC_INSTANCE_PATH  (v10.0.0)
│               ├── instance_data.gmcc.yaml
│               └── sessions/
│                   └── {sanitized_branch}/                   # $GMCC_SESSION_PATH
│                       ├── session_data.gmcc.yaml
│                       ├── gmcc_session_file_index.yaml         # per-session catalog (gmcc_session_creation)
│                       └── prompts/
│                           └── {id}_{name}/                  # one folder per prompt (v10.0.0)
│                               ├── {id}_{name}_data.gmcc.yaml
│                               ├── {id}_{name}_initial.yaml
│                               ├── {id}_{name}_clarified.yaml      # when Clarified
│                               └── memory/
│                                   ├── explore.md
│                                   ├── architecture.md
│                                   └── review.md
└── kbites/                                                   # $GMCC_KBITE
    ├── {kbite_name}/KBITE_PURPOSE.md                         # identity-level
    ├── digested/{kbite_name}/...                             # $GMCC_KBITE_DIGESTED
    └── open/{kbite_name}/...                                 # $GMCC_KBITE_OPEN
```

## Identity Resolution (How a path becomes a session)

`scripts/detect_repo.sh` runs on every SessionStart. Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `gmcc-marketplace` |
| `instance_id` (v10.0.0) | `{project_name}_{4-char hash of abs path}` | e.g. `gmcc-marketplace_a3f2` |
| `session_branch` | Sanitized current git branch | e.g. `v4_2`, `feature__login` |

### Instance Code Algorithm (v10.0.0)

Instances use a machine-safe hash-suffixed code instead of the legacy
slugified-absolute-path form. The code IS the directory name:

```
INSTANCE_CODE = "{basename($REPO_ROOT)}_{first 4 chars of md5($REPO_ROOT)}"
```

- Deterministic from `$REPO_ROOT` (the hook can always re-derive it).
- Collision-resistant: requires two repos with the same basename AND the same 4-char hash.
- Machine-safe by construction: only `[a-z0-9\-_]` characters from the basename + hex hash.
- `instance_data.gmcc.yaml`'s `name:` field is the human-readable repo basename; `code:` is the hash-suffixed form.

Pre-v6.2 instances used the slugified absolute path (e.g.
`Users__brycerubinson__Dev__gmcc-marketplace`). `/gmcc_environment_cleanup` migrates
those to the new code-based directory + rewrites paths.

### Branch Slugification Rules
- Replace every `/` with `__` (literal two underscores).
- Implementation uses `sed 's|/|__|g'` — NOT `tr`, because `tr` is char-to-char and would collapse `/` into a single `_`.

A project corresponds to exactly one git repo (by basename). An instance is a unique filesystem checkout of that repo — moving the checkout to a new path creates a new instance. A session is one git branch within an instance.

## Lazy Creation by `detect_repo.sh`

On every SessionStart, the hook ensures the following exist for the current git context. All steps are idempotent:

1. `$GMCC_PROJECTS/` (created if missing — `/gm_init` does this normally; the hook is a safety net)
2. `$GMCC_PROJECTS_INDEX` (copied from `templates/projects/project_index.gmcc.yaml`)
3. `$GMCC_PROJECT_PATH/{project_data.gmcc.yaml, instances/}` (filled from `templates/projects/PROJECT_TEMPLATE/project_data.gmcc.yaml` with placeholder substitution; `kbite:` seeded from `$GMCC_PROJECTS_INDEX.kbite`)
4. `$GMCC_INSTANCE_PATH/{instance_data.gmcc.yaml, sessions/}` (filled from `templates/.../INSTANCE_TEMPLATE/instance_data.gmcc.yaml`; `kbite:` seeded from `project_data.kbite`)
5. `$GMCC_SESSION_PATH/{session_data.gmcc.yaml, prompts/}` (filled from `templates/.../SESSION_TEMPLATE/session_data.gmcc.yaml`; `kbite:` seeded from `instance_data.kbite`)
6. Append a project entry to `$GMCC_PROJECTS_INDEX` if new (idempotent grep-then-append)
7. Append instance and session entries similarly. Session entries include `branch:` (raw branch name).

This means **commands can always assume the layout exists** — no per-command init logic is needed.

## File-Level Kbite Inheritance (v10.0.0)

Every runtime file type unwraps `has_kbite_list`, exposing a top-level
`kbite: List<string>` field. The list is **seeded from the parent at
lazy-create time only**:

```
project_index.kbite → project_data.kbite → instance_data.kbite → session_data.kbite → prompt_data.kbite
```

After seeding, each level's list is fully independent. Editing
`project_data.kbite` does **not** propagate to existing instances or
sessions. Deletes do not propagate either — child lists keep what they
had at creation. Bot workflows are responsible for seeding the
prompt-level inheritance (session → prompt) at prompt-folder creation
time; `detect_repo.sh` handles the three upper levels.

## session_data.gmcc.yaml (v10.0.0 Schema)

Conforms to `gmcc.gmcc_session_data_file`. Unwraps `has_base_fields`,
`has_ckfs_paths`, `has_kbite_list`, plus branch / instance_uuid /
project_uuid back-references and the typed prompt/changed-files lists.

```yaml
yeet:
  - gmcc
yeet_type: gmcc.gmcc_session_data_file

id: 1
code: {sanitized_branch}
uuid: {v4}
name: {display name — usually equal to code at creation}
description: ""
created_time: {ISO 8601}
updated_time: {ISO 8601}
gmcc_ckfs_absolute_path: {GMCC_SESSION_PATH}
gmcc_ckfs_relative_path: projects/{project}/instances/{instance}/sessions/{branch}
kbite: []                                      # seeded from instance_data.kbite at create
branch: {raw branch name}
instance_uuid: {v4}
project_uuid: {v4}
backstory: ""                                  # session-level narrative (v11.0.0); seeded empty, prompts inherit it

# Lightweight stubs — follow `path:` to each prompt_data.gmcc.yaml.
prompts:
  - id: {monotonic int}
    name: {kebab-case slug}
    status: Draft | Clarifying | Clarified
    path: prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml

# Typed entries (conform to gmcc_session_data_file_changed_files_entry).
changed_files:
  - file: {relative path inside the instance}
    timestamp: {ISO 8601}
    lines:
      - [start, end]
    commit: {short sha or "uncommitted"}
    note: ""

# Optional audit trail of completed bot runs (absent until first completion;
# conforms to gmcc_session_data_file_phase_history_entry). review_status is
# null for the lightweight /gm_bot tier; teams_used is /gm_bot_team only.
# (The separate cleanup_actions: list is owned by the cleanup commands —
#  /gmcc_environment_cleanup and /gmcc_session_cleanup — not declared here.)
phase_history:
  - prompt_id: {int}
    command: /gm_bot_rpi
    completed_at: {ISO 8601}
    review_status: pass | pass_with_issues
```

The other four runtime yamls share the same outer shape: `yeet:` /
`yeet_type:` headers, base/ckfs/kbite unwraps, plus the extras declared
by their YEETS type. The hierarchy is **owner-local** — each file owns
its direct children, not a deep tree:

- `project_index.gmcc.yaml` → flat list of project entries (identity only).
- `project_data.gmcc.yaml` → repo metadata + list of that project's instances.
- `instance_data.gmcc.yaml` → `has_system_path` + `project_uuid` back-reference + list of that instance's sessions (each entry carries `branch:`).
- `session_data.gmcc.yaml` → standalone (no children list); carries `branch`, back-references, and typed `prompts` / `changed_files` lists.
- `prompt_data.gmcc.yaml` (new in v10.0.0) → identity + paths to sibling initial/clarified content + `prompt_status` enum.

## Prompt Folder Layout (v10.0.0)

Each prompt is a folder, not a loose file:

```
prompts/{id}_{name}/
    {id}_{name}_data.gmcc.yaml      # the gmcc_prompt_data_file (index, version: 3)
    {id}_{name}_initial.yaml        # prompt style: detail (verbatim) + empty goal/backstory (v11.0.0)
    {id}_{name}_clarified.yaml      # absent until prompt_status = Clarified
    memory/
        explore.md                   # Phase 2 artifact
        architecture.md              # Phase 4 artifact (after approval)
        review.md                    # Phase 6 artifact
```

`{id}_{name}_data.gmcc.yaml` is the single index. It carries identity
(`has_base_fields` + `has_ckfs_paths` + `has_kbite_list`), the two path
fields `initial_prompt_path` / `clarified_prompt_path` (paths relative
to the prompt folder), `prompt_status: Draft | Clarifying | Clarified`,
and `command:` recording which bot authored it.

`clarified_prompt_path` is empty-string until `prompt_status` becomes
`Clarified`.

### Typed prompt content files (v11.0.0)

Both content files keep the plain `.yaml` suffix but carry `yeet:` +
`yeet_type:` headers so `/gm_compile` validates them.

`{id}_{name}_initial.yaml` conforms to `gmcc.gmcc_initial_prompt_file` — the
"prompt style". `backstory`/`goal`/`detail` are **human-input only**; the bot
must **STAY TRUE** and never split, infer, or author them (a human editor is
coming). At create time the entire passed prompt is written **verbatim** to
`detail`; `goal` is left empty (`""`); `backstory` is inherited from the session.

- **`backstory`** — human input, inherited verbatim from the parent
  `session_data.gmcc.yaml`'s `backstory:` at draft-create time (empty `""` unless
  a session backstory was set). May diverge per prompt afterward.
- **`goal`** — human input; the desired outcome / acceptance criteria. Empty
  (`""`) at create time; built up later in the Clarify phase.
- **`detail`** — human input; the passed prompt verbatim (how to accomplish it).
- `kbites_loaded` (+ `kbite_context_summary` for the subagent/team tiers).

`{id}_{name}_clarified.yaml` conforms to `gmcc.gmcc_clarified_prompt_file` —
mirrors the split: `goal_clarifications` / `detail_clarifications` (separate
Q/A suites), `refined_goal` / `refined_detail`, the carried-through `backstory`,
`detected_yeet_types` (every YEETS type detected in the initial prompt and how
it resolved), `key_files`, `constraints`, `kbites_loaded`
(+ `patterns_to_follow` for subagent/team tiers; team adds per-clarification
`rating` and `key_files[].consensus`).

## Yaml Files (Editable By)

| File | Purpose | Maintained by |
|------|---------|---------------|
| `project_index.gmcc.yaml` | Flat registry of all projects (identity only) | `detect_repo.sh` (registers); `/gmcc_environment_cleanup` (prunes) |
| `project_data.gmcc.yaml` | Per-project identity, repo metadata, instance list | `detect_repo.sh` (creates + appends instances) |
| `instance_data.gmcc.yaml` | Per-instance identity, system path, session list | `detect_repo.sh` (creates + appends sessions, each with `branch:`) |
| `session_data.gmcc.yaml` | Per-branch session state (typed prompts, typed changed_files) | Bot workflows (continuous updates) |
| `prompts/{id}_{name}/{id}_{name}_data.gmcc.yaml` | Per-prompt index | Bot workflows (status flips, path fills) |
| `prompts/{id}_{name}/{id}_{name}_initial.yaml` | Prompt style (human-input backstory/goal/detail; passed prompt → detail verbatim, goal/backstory empty at create) | Bot workflows (immutable after Phase 1) |
| `prompts/{id}_{name}/{id}_{name}_clarified.yaml` | Clarified prompt | Bot workflows (immutable once written) |
| `prompts/{id}_{name}/memory/*.md` | Bot phase artifacts | Bot workflows (last-run-wins overwrite) |

## Prompts Lifecycle (v10.0.0)

Bot workflows author prompts in three stages:

1. **Draft** — `/gm_bot*` creates `prompts/{id}_{name}/` with `memory/`, writes `{id}_{name}_data.gmcc.yaml` (`prompt_status: Draft`, kbite seeded) and `{id}_{name}_initial.yaml`. Appends the session_data stub with `status: Draft`.
2. **Clarifying** — Phase 3 flips `prompt_status` to `Clarifying`. Its **first** step (v11.0.0) is YEET-type detection over the initial prompt's `goal` + `detail` — declared and structurally-inferred YEETS types are resolved (or the user is asked when they cannot be), then recorded in the clarified file's `detected_yeet_types`. The bot then runs **separate** goal and detail clarification suites. session_data stub follows.
3. **Clarified** — Once the Q/A is finalized, writes `{id}_{name}_clarified.yaml` (`refined_goal` / `refined_detail` + `detected_yeet_types`), sets `clarified_prompt_path`, flips `prompt_status` to `Clarified`. session_data stub follows. The `_initial.yaml` file is **not** modified — the clarified file is the new source of truth.

Intermediate artifacts (exploration, architecture, review) are persisted under `memory/` per `bot_workflows.md`. Resume across sessions can rely on both the typed session_data stubs and the persisted memory files.
