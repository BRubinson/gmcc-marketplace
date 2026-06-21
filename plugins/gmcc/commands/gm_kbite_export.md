---
name: gm_kbite_export
description: "Zip up selected kbites (root + digested index) into a portable archive on the Desktop"
argument-hint: "[kbite_name ...]"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gm_kbite_export [kbite_name ...]

Packages one or more kbites into a single self-describing zip archive on the
Desktop so they can be moved to another ckfs and re-imported with
`/gm_kbite_import`.

Each exported kbite carries its **root** (identity files such as
`KBITE_PURPOSE.md`) and its **digested** index. In-progress **open maws are NOT
exported** — only finalized knowledge travels.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_KBITE` and `$GMCC_KBITE_DIGESTED` are set).
2. Parse optional `{kbite_name ...}` arguments (names to export without prompting).

---

## Archive Format Reference

Per the **gmcc_kbite** skill ("Export / Import Archive Format"), the produced zip
is self-describing and ckfs-relocatable — no absolute source paths are stored:

```
~/Desktop/gmcc_kbites_{YYYYMMDD-HHMMSS}.zip
├── MANIFEST.yaml                  # exported kbites + which components are present
└── kbites/
    └── {kbite_name}/
        ├── root/...               # contents of $GMCC_KBITE/{name}/ (sans digested/ open/)
        └── digested/...           # contents of $GMCC_KBITE_DIGESTED/{name}/
```

---

## Execution Steps

### Step 1: Enumerate Available KBites

A kbite may exist at the root (purpose written) and/or as a digested index. Build
the candidate list as the union of both locations, excluding the `digested` and
`open` lifecycle folders themselves:

```bash
{
  ls -1 "$GMCC_KBITE" 2>/dev/null | grep -vx -e digested -e open
  ls -1 "$GMCC_KBITE_DIGESTED" 2>/dev/null
} | sort -u
```

If the list is empty:
```
[GMB] Error: No kbites found to export

Nothing exists under $GMCC_KBITE_DIGESTED/. Create a kbite first with
/gm_crunch_open_maw {name} → /gm_crunch_chew → /gm_crunch_digest.
```
Exit without changes.

### Step 2: Select Which KBites to Export

- **If kbite names were passed as arguments**: validate each against the
  enumerated list. Report any unknown names and exit if any are invalid. Use the
  valid set as the selection (no prompt).
- **Otherwise, present a select menu** with AskUserQuestion (`multiSelect: true`):
  - List the kbites as selectable options. AskUserQuestion allows up to 4 options
    per question and up to 4 questions per call — chunk the kbites into groups of
    4 across multiple questions (handles up to 16 kbites in one call). Include an
    **"Export ALL kbites"** option as the first option of the first question.
  - If more than 16 kbites exist, instead show the numbered list and ask the user
    to re-run with explicit names: `/gm_kbite_export {name1} {name2} ...`.
  - The union of all selected options across questions is the selection. If
    "Export ALL kbites" is chosen, select every enumerated kbite.

If the resulting selection is empty (user picked nothing), report "No kbites
selected — nothing exported." and exit.

### Step 3: Choose Payload Scope

KBites can be very large — the chewed analysis is tiny, but `example_project`
sources carry raw repos/zips and `.git` history (often many GB per kbite). Ask the
user (AskUserQuestion, single-select) which scope to archive, defaulting to
**Everything minus .git**:

| Scope | Includes | Excludes |
|-------|----------|----------|
| **knowledge_only** | indexes (`KBITE_*.md`), `KBITE_PURPOSE.md`, all `*_chewed.md` analysis | raw `example_project` source payloads, `.git` |
| **everything_minus_git** *(default)* | raw sources + chewed analysis + indexes | `.git` directories |
| **everything** | byte-for-byte copy | nothing |

Open maws are excluded in every scope.

### Step 4: Stage the Archive Contents

```bash
TS=$(date +%Y%m%d-%H%M%S)
STAGE=$(mktemp -d)
mkdir -p "$STAGE/kbites"
```

For each selected `{name}`, copy the two components that exist, applying the
chosen scope. Copy first, then prune so the scope rules apply uniformly to both
root and digested:

```bash
# Root identity files (exclude the digested/ open/ lifecycle subfolders)
if [ -d "$GMCC_KBITE/{name}" ]; then
  mkdir -p "$STAGE/kbites/{name}/root"
  ( cd "$GMCC_KBITE/{name}" && \
    find . -maxdepth 1 -mindepth 1 ! -name digested ! -name open \
      -exec cp -R {} "$STAGE/kbites/{name}/root/" \; )
fi

# Digested index
if [ -d "$GMCC_KBITE_DIGESTED/{name}" ]; then
  mkdir -p "$STAGE/kbites/{name}/digested"
  cp -R "$GMCC_KBITE_DIGESTED/{name}/." "$STAGE/kbites/{name}/digested/"
fi

# --- Apply scope pruning to the staged copy of this kbite ---
KB="$STAGE/kbites/{name}"
case "$SCOPE" in
  knowledge_only)
    # keep only markdown knowledge (indexes, purpose, *_chewed.md); drop the rest
    find "$KB" -type f ! -name '*.md' -delete
    find "$KB" -depth -type d -empty -delete
    ;;
  everything_minus_git)
    find "$KB" -type d -name .git -prune -exec rm -rf {} +
    ;;
  everything)
    : # keep as-is
    ;;
esac
```

> Note: `$GMCC_KBITE/{name}` normally contains only `KBITE_PURPOSE.md`, but the
> `find ... ! -name digested ! -name open` guard keeps the export correct even if
> the per-kbite root and the lifecycle folders ever share a parent.
>
> `knowledge_only` keeps every `.md` (chewed analyses + indexes + purpose are all
> markdown) and discards raw source payloads, which restores small and fast.

### Step 5: Write MANIFEST.yaml

Record one entry per selected kbite with booleans for which components were
staged, plus the chosen `scope`. Read the plugin version from
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`.

```yaml
gmcc_export_version: 1
gmcc_plugin_version: "{version from plugin.json}"
exported_at: {ISO 8601}
source_ckfs: {basename of $GMCC_CKFS_ROOT, informational only}
scope: everything_minus_git   # knowledge_only | everything_minus_git | everything
kbites:
  - name: {name}
    has_root: true            # true if root/ was staged
    has_digested: true        # true if digested/ was staged
```

Write it to `$STAGE/MANIFEST.yaml`.

### Step 6: Zip to Desktop

```bash
DEST="$HOME/Desktop/gmcc_kbites_${TS}.zip"
( cd "$STAGE" && zip -r -q -X "$DEST" . -x '*.DS_Store' '__MACOSX/*' )
rm -rf "$STAGE"
```

If `$HOME/Desktop` does not exist, fall back to `$HOME` and note it in the report.

> For the `knowledge_only` scope the archive is small. For the other scopes it can
> be multi-GB; the `-q` flag keeps zip quiet, and re-compressing already-compressed
> source `.zip`s is slow — warn the user before zipping if the staging dir exceeds
> ~1 GB (`du -sh "$STAGE"`).

### Step 7: Final Report

```
KBites Exported

**Archive**: ~/Desktop/gmcc_kbites_{TS}.zip
**Scope**: {scope}
**Size**: {human-readable size}
**KBites** ({count}):
- {name}  (root: ✓, digested: ✓)
- {name}  (root: ✓, digested: ✗)

Open maws were not included.

## Import elsewhere
Copy the zip to the destination machine and run:
  /gm_kbite_import ~/Desktop/gmcc_kbites_{TS}.zip
```

---

## Error Handling

**No kbites found:** see Step 1.

**Unknown kbite name passed as argument:**
```
[GMB] Error: Unknown kbite(s): {names}

Available kbites:
- {enumerated list}
```
Exit without creating an archive.

**zip command unavailable / write failure:**
```
[GMB] Error: Failed to create archive

Could not write {DEST}. Check that `zip` is installed and ~/Desktop is writable.
```
Leave no partial archive (remove `$DEST` if it was partially written) and clean
up the staging dir.

---

## Examples

```bash
# Interactive select menu
/gm_kbite_export

# Export specific kbites without prompting
/gm_kbite_export iterm swift_ui

# Export everything (or choose "Export ALL kbites" in the menu)
/gm_kbite_export
```
