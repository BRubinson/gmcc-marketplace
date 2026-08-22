---
name: gm_crunch_digest
description: "Digest chewed maw resources into the daemon db and archive raw sources"
argument-hint: "<kbite_name>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, Grep
---

# /gm_crunch_digest {kbite_name}

Finalizes a kbite: one `gm kbite digest` call imports every chewed analysis
into the daemon db (the canonical home for digested text, keywords, and
search), then the raw source folders are archived under
`$GMCC_KBITE_DIGESTED/{kbite_name}/` and the open maw is deleted.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_KBITE` is set)
2. Verify maw exists at `$GMCC_KBITE_OPEN/{kbite_name}/`
3. Read MAW_INDEX.md - verify status is "ready_to_digest" or has chewed resources
4. Verify KBITE_PURPOSE.md exists at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md`

### If Maw Missing
```
[GMB] Error: No maw found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} and /gm_crunch_chew {kbite_name} first.
```
Exit without changes.

### If No Chewed Resources
```
[GMB] Error: No chewed resources found in maw

Run /gm_crunch_chew {kbite_name} to process crunchables first.
```
Exit without changes.

### If KBITE_PURPOSE Missing
```
[GMB] Error: KBITE_PURPOSE.md not found

The kbite purpose file is required at:
$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md

Run /gm_crunch_open_maw {kbite_name} to create it.
```
Exit without changes.

---

## Storage Model Reference

Per the **gmcc_kbite** skill:

**Source (open maw):**
```
$GMCC_KBITE_OPEN/{kbite_name}/
├── MAW_INDEX.md
├── {axis1}/{axis2}/{resource_name}/           # raw source files
└── {axis1}/{axis2}/{resource_name}_chewed.md  # analysis (digest input)
```

**Destination:**
- **Daemon db** (canonical): resources, per-file summaries + inline text
  content, keywords, FTS5 search — written by `gm kbite digest`, read back
  via `gm kbite get / file-get / search`.
- **`$GMCC_KBITE_DIGESTED/{kbite_name}/`** (raw-source archive): the raw
  source folders, moved there client-side after the db import. No
  KBITE_INDEX.md is generated — `gm kbite get` is the index.
- **`$GMCC_KBITE/{kbite_name}/`** (identity): KBITE_PURPOSE.md and, if
  relationships exist, KBITE_RELATIONSHIPS.md (managed by `/gm_kbite_relate`).

---

## Execution Steps

### Step 1: Review Chewed Resources

1. List all `*_chewed.md` files under the maw (`{axis1}/{axis2}/`)
2. Sanity-check each has the required sections (Contents Overview, Key
   Learnings, Detailed Analysis, Keywords) — a malformed chewed file digests
   as a thin resource rather than erroring

### Step 2: Digest into the DB

One call — the daemon parses every chewed file into resource / file /
keyword rows (full text inlined for text-type files), then deletes the
chewed `.md` files after the transaction commits:

```bash
~/gmcc/bin/gm kbite digest --code {kbite_name} --json
```

The response reports `resource_count`, `file_count`, `keyword_count`, and
`deleted_chewed_files`. Re-digesting a resource replaces its rows.

### Step 3: Archive Raw Sources

Move the raw source folders from the maw into the digested archive
(client-side — the daemon never moves raw sources):

```bash
for axis1 in primary secondary; do
  for axis2 in documentation example_project api_reference blogs all_others; do
    src="$GMCC_KBITE_OPEN/{kbite_name}/$axis1/$axis2"
    dst="$GMCC_KBITE_DIGESTED/{kbite_name}/$axis1/$axis2"
    if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
      mkdir -p "$dst"
      mv "$src"/* "$dst"/
    fi
  done
done
```

### Step 4: Delete Open Maw

```bash
rm -rf "$GMCC_KBITE_OPEN/{kbite_name}"
```

### Step 5: Verify

```bash
~/gmcc/bin/gm kbite get --code {kbite_name} --json
```

Confirm the resource/file/keyword counts match Step 2's response.

---

## Final Report

```
Digest Complete: {kbite_name}

**Canonical knowledge**: daemon db (gm kbite get/search/file-get)
**Raw-source archive**: $GMCC_KBITE_DIGESTED/{kbite_name}/

## Digest Summary

| Metric | Count |
|--------|-------|
| Resources | {resource_count} |
| Files | {file_count} |
| Keywords | {keyword_count} |
| Chewed files imported + deleted | {len(deleted_chewed_files)} |

## Maw Cleanup

The open maw at `$GMCC_KBITE_OPEN/{kbite_name}/` has been deleted.

## Next Steps

1. Query: `gm kbite search "<topic>"` then `gm kbite file-get --file-uuid U`
2. Add relationships with `/gm_kbite_relate {kbite_name} {other_kbite} {description}`
```

---

## Error Handling

**Maw not found:**
```
[GMB] Error: Maw not found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} and /gm_crunch_chew {kbite_name} first.
```

**No chewed resources:**
```
[GMB] Error: No chewed resources in maw

Run /gm_crunch_chew {kbite_name} to process crunchables.
```

**Digest failure (gm exits non-zero):**
```
[GMB] Error: gm kbite digest failed

{gm stderr}

Nothing was deleted — the db transaction rolled back and chewed files are
only removed after a successful commit. Fix the issue and re-run
/gm_crunch_digest {kbite_name}.
```

**Raw-source move failure:**
```
[GMB] Error: Failed to archive raw sources for {resource_name}

The db import already succeeded (knowledge is safe). The maw has NOT been
deleted — move the remaining folders manually or re-run Step 3, then delete
the maw.
```
