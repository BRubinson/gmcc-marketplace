---
name: gmcc_migrate_legacy
description: Legacy yaml-ckfs → daemon-db migration pathway. Imports pre-v16 yaml-based prompts into the SQLite db (/import_legacy_yaml_gmcc) and archives the migrated folders to _archive/cold_storage/ (/archive_legacy_yaml_gmcc). Default-inert — does nothing unless one of its commands is explicitly invoked.
user-invocable: false
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Legacy Migration Skill (v16.3.0)

Migrates a pre-v16 yaml-based ckfs into the daemon db, then cold-stores the
yamls. **Default-inert**: this skill never runs on its own — it acts only
when `/import_legacy_yaml_gmcc` or `/archive_legacy_yaml_gmcc` is invoked,
so the existing setup is untouched until you deliberately beta-test the
migration.

Two phases, two commands, always in this order:

1. `/import_legacy_yaml_gmcc` — read-only over the yamls; backfills db rows.
2. `/archive_legacy_yaml_gmcc` — moves successfully-imported material to
   `$GMCC_CKFS_ROOT/_archive/cold_storage/`, structure-preserving.

The daemon recreates from the yaml structure everything it natively models
(context chains, prompt rows, artifact pointers); file bodies stay in files
— the db stores pointers + one-sentence captions, never content.

---

## Scope Rules (both phases)

- **Only current-shape prompts**: a `prompts/{id}_{name}/` folder with a
  parseable `{id}_{name}_data.gmcc.yaml` (the v10+ folder layout). Anything
  else (loose yamls at `prompts/` root, unparseable/older shapes) is
  **reported and left in place** for manual triage — never guessed at.
- **Nothing under `_archive/` is ever touched.** Skip it in every walk.
- Idempotent: `gm context ensure --from-ckfs` upserts; `gm prompt create
  --uuid <reused>` on an existing uuid is skipped (the row already exists —
  detect via `gm prompt list` first); `gm artifact add` upserts on
  `(prompt_uuid, file_path)`. Re-running import after a partial run is safe.

---

## Phase 1: Import (`/import_legacy_yaml_gmcc`)

Walk `$GMCC_CKFS_ROOT/projects/` (skipping `_archive/` and anything that is
not a `projects/{p}/instances/{i}/sessions/{s}` tree):

### 1. Ensure the context chain per session

For each session directory found:

```bash
~/gmcc/bin/gm context ensure --from-ckfs "projects/{p}/instances/{i}/sessions/{s}" --json
```

This builds the chain from the legacy yamls (reusing their `uuid:` values
and `kbite:` registries) instead of cwd git, and returns `session_uuid`.
This is the only path in gm that still reads yaml `kbite:` lists — the
registry material is carried into the db at create-time seed; kbite
*content* is migrated in step 4 below.

### 2. Import each prompt folder

For each `prompts/{id}_{name}/` with a parseable data yaml, extract from
the yaml triad:

- `{id}_{name}_data.gmcc.yaml` → `uuid`, `code`, `name`, `command`,
  `prompt_status` (map `Draft/Clarifying/Clarified` → lowercase)
- `{id}_{name}_initial.yaml` → `backstory`, `goal`, `detail` (block scalars,
  verbatim)

Check `gm prompt list --session-uuid U --json` — if a stub with this uuid
already exists, skip creation (already imported). Otherwise:

```bash
~/gmcc/bin/gm prompt create --session-uuid {session_uuid} \
  --uuid {reused ckfs uuid} --code {code} --name {name} \
  --backstory "<verbatim>" --goal "<verbatim>" --detail "<verbatim>" \
  --command "{command}" --json
```

Then advance the row's status to match the legacy `prompt_status`, mapped
onto lifecycle v2 best-effort (threading `--expected-version` from each
response). Old terminal `Clarified` → `done` (its pipeline finished under
the old contract); in-flight `Draft`/`Clarifying` carry over unchanged. Do
NOT fabricate clarification/architecture rows for migrated prompts — the
daemon's legacy gate bypass lets pre-m0002 prompts advance without them:

```bash
gm prompt set-status ... --status clarifying     # if legacy was Clarifying or Clarified
gm prompt set-status ... --status architecting   # ┐
gm prompt set-status ... --status implementing   # │ only if legacy was Clarified
gm prompt set-status ... --status done           # ┘ (walk to the new terminal)
```

Note: the db `seq` is allocated fresh per session; the legacy `id` is
preserved in the folder name and the reused `uuid` is the durable join key.

### 3. Register artifacts (at their POST-ARCHIVE location)

For each file in the folder — `memory/explore.md`, `memory/architecture.md`,
`memory/review.md`, the `_initial.yaml`, `_clarified.yaml`, and
`_data.gmcc.yaml` yamls, and any other files present:

```bash
gm artifact add --prompt-uuid U \
  --file-path "$GMCC_CKFS_ROOT/_archive/cold_storage/projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}/{relative}" \
  --kind {explore|architecture|review|other} \
  --note "<one brief standard sentence describing the content>"
```

- `memory/explore.md` → `--kind explore`, note e.g. "Exploration report from the legacy yaml-era run."
- `memory/architecture.md` → `--kind architecture`, note e.g. "Approved architecture from the legacy yaml-era run."
- `memory/review.md` → `--kind review`, note e.g. "Code review report from the legacy yaml-era run."
- `{id}_{name}_clarified.yaml` → `--kind qualified`, note e.g. "Legacy clarified prompt yaml (Q&A suites + refined goal/detail)."
- everything else (`_initial.yaml`, `_data.gmcc.yaml`, misc) → `--kind other` with a one-sentence caption.

**The registered `file_path` is the archive DESTINATION** (where Phase 2
will move the folder), so pointers stay valid after archiving. The note is
the file pointer's caption — content stays inside the file, never in the db.

### 3b. Transfer explore/review reports into db rows (m0004 — MANDATORY, all eras)

Since m0004 the exploration/review record is db-native, and this transfer
pass is **mandatory** — it covers BOTH the yaml-era prompts imported above
AND the mid-era population: prompts created between m0002 and m0004
(`is_legacy: false`) whose explore.md/review.md live on disk behind
artifact pointers. Until a mid-era prompt is migrated, `gm explore/review
get` on it returns `SUMMARY_ABSENT` guidance that steers here.

**Execution: spawn Sonnet 5 agents** (`model: sonnet` — a user-directed
standing rule for this pass) — one agent can batch many prompts.

Per prompt with an on-disk `explore.md`:

```bash
gm explore open --prompt-uuid U --json                      # → summary uuid S (created)
gm explore complete --summary-uuid S --expected-version 0 \
  --overview-file .../memory/explore.md                       # VERBATIM — zero findings
                                                              # (never $(cat ...) into argv:
                                                              # >1 MB files exceed ARG_MAX)
```

Per prompt with an on-disk `review.md`:

```bash
gm review open --prompt-uuid U --json
gm review complete --summary-uuid S --expected-version 0 \
  --overview-file .../memory/review.md --verdict legacy_unstated
```

Rules — **verbatim transfer, never interpretation**:
- `overview` := the file content verbatim. NO findings are fabricated from
  freeform markdown (the unranked gate passes vacuously with zero
  findings). This is a TRANSFER, not row fabrication — the "never
  fabricate backing rows" contract forbids inventing structured content,
  which this never does.
- Review verdict is `legacy_unstated` — inventing approved/changes_requested
  for a file that never states one WOULD fabricate. (If the file explicitly
  states a verdict in its own words, that exact verdict may be used.)
- An EMPTY report file: skip row creation (complete refuses empty
  overviews), keep the artifact pointer, note it in the run summary.
- The existing artifact pointers are KEPT as history; the files then follow
  the normal archive flow (Phase 2 / cold storage).

### 4. Digest legacy kbite content into the db

Pre-v16 kbites have their knowledge as `*_chewed.md` files under
`$GMCC_KBITE_DIGESTED/{name}/` (often with a `KBITE_INDEX.md`) and no db
rows. For each kbite dir under `$GMCC_KBITE_DIGESTED/` that contains chewed
files but whose `gm kbite get --code {name} --json` shows no resources:

1. **Archive first** (universal cold-storage convention): copy the chewed
   `.md` files — plus `KBITE_INDEX.md` / `KBITE_RELATIONSHIPS.md` if present
   in the digested dir — to
   `$GMCC_CKFS_ROOT/_archive/cold_storage/kbites/digested/{name}/`,
   preserving the relative structure. (`KBITE_RELATIONSHIPS.md` also moves
   to its current home at `$GMCC_KBITE/{name}/` if not already there.)
2. **Digest**: `gm kbite digest --code {name} --kbite-open-path
   "$GMCC_KBITE_DIGESTED/{name}" --json` — digest walks
   `{axis1}/{axis2}/*_chewed.md` under any scan root, so the digested tree
   works directly. The daemon imports the rows and deletes the chewed files
   from the digested tree; the raw source folders stay where they are (the
   digested tree is already the raw-source archive).
3. **Verify**: `gm kbite get --code {name} --json` counts match; then delete
   the now-stale `KBITE_INDEX.md` from the digested dir (archived in 1).

Raw legacy maws (pre-v5.3 FAM-era `maw/` folders or any maw material found
inside old trees, as opposed to live `$GMCC_KBITE_OPEN/{name}/` maws) go to
`$GMCC_CKFS_ROOT/_archive/cold_storage/`, structure preserved.

### 5. Report

```
[GMB] Legacy import complete

Sessions ensured: {n}
Prompts imported: {n} (uuids reused)
Artifacts registered: {n}
KBites digested into db: {n} (chewed files archived to cold storage)
Skipped (already in db): {n}
Left in place for manual triage (malformed/older shape): {n}
  - {path}: {reason}

Next: /archive_legacy_yaml_gmcc to cold-store the migrated folders.
```

Track the imported prompt folders (e.g. a manifest in chat context or
re-derivable by re-walking) — Phase 2 archives exactly the successfully
imported set.

---

## Phase 2: Archive (`/archive_legacy_yaml_gmcc`)

Walk `$GMCC_CKFS_ROOT/projects/` exactly as Phase 1 does — every
`projects/{p}/instances/{i}/sessions/{s}` tree, skipping `_archive/` — do
not limit the check to the current session. Get the whole db's
verified-imported uuids in one call with `gm prompt list --all --json`
(each stub carries `session_uuid`; group by it to match folders to their
sessions).

**Never call bare `gm prompt list` for verification.** With no flag it
silently defaults to the current repo/branch session and undercounts every
other session in the db — the whole-db query is `--all`, nothing less.

For each prompt folder whose uuid appears in its session's verified list,
move it to cold storage **keeping the shared folder structure and every
file intact**:

```bash
DEST="$GMCC_CKFS_ROOT/_archive/cold_storage/projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}"
mkdir -p "$(dirname "$DEST")"
mv "$GMCC_CKFS_ROOT/projects/{p}/instances/{i}/sessions/{s}/prompts/{id}_{name}" "$DEST"
```

Then, for each session/instance/project level whose prompt folders are all
migrated, also archive the legacy per-level yamls (`session_data.gmcc.yaml`,
`gmcc_session_file_index.yaml`, `instance_data.gmcc.yaml`,
`project_data.gmcc.yaml`, and the top-level `project_index.gmcc.yaml`) to
the same relative locations under `_archive/cold_storage/`. Leave the bare
directory skeleton (`sessions/{s}/prompts/`) in place — it is the live
artifact home going forward.

**Safety**: never archive a folder whose import cannot be verified in the
db; report it instead. Never touch anything already under `_archive/`.
The current session's own folders (`$GMCC_SESSION_PATH`) are archived last
and only with explicit per-folder confirmation via AskUserQuestion (the
running session may still reference them).

Kbite trees under `$GMCC_KBITE` are NOT moved by this phase — registries
were carried into the db at context-ensure time, digested text was imported
by Phase 1 step 4 (chewed files archived there, not here), and the raw
sources under `$GMCC_KBITE_DIGESTED/{name}/` stay live as the raw-source
archive. Raw legacy maw material found in old trees was cold-stored in
Phase 1 step 4.

### Report

```
[GMB] Legacy archive complete

Sessions covered (whole-db `gm prompt list --all`, grouped by session_uuid): {n}
Prompt folders moved: {n}
Level yamls archived: {n}
Left in place (unverified import): {n}
  - {path}: {reason}

Cold storage: $GMCC_CKFS_ROOT/_archive/cold_storage/ (structure preserved)
```
