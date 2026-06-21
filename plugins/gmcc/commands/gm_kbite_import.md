---
name: gm_kbite_import
description: "Import a kbite archive produced by /gm_kbite_export into the current ckfs"
argument-hint: "<zip_path>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gm_kbite_import <zip_path>

Reconstructs kbites from a zip archive created by `/gm_kbite_export` (on this or
any other ckfs) into the **current** ckfs. Paths are rebuilt from this machine's
`$GMCC_KBITE` / `$GMCC_KBITE_DIGESTED` — the archive carries no absolute source
paths, so it imports cleanly regardless of where it was exported.

On a name collision with an existing kbite, you are asked **per kbite** whether to
overwrite, skip, or import under a renamed copy. Nothing is overwritten silently.

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
2. Parse the `{zip_path}` argument.

---

## Archive Format Reference

Per the **gmcc_kbite** skill ("Export / Import Archive Format"), a conforming
archive has a top-level `MANIFEST.yaml` and a `kbites/{name}/{root,digested}/`
tree.

---

## Execution Steps

### Step 1: Resolve and Validate the Archive

```bash
ZIP="{zip_path}"
# If omitted, default to the most recent export on the Desktop:
if [ -z "$ZIP" ]; then
  ZIP=$(ls -t "$HOME/Desktop"/gmcc_kbites_*.zip 2>/dev/null | head -n1)
fi
```

- If no path was given and none was found on the Desktop:
  ```
  [GMB] Error: No archive specified

  Usage: /gm_kbite_import <zip_path>
  (No gmcc_kbites_*.zip found on ~/Desktop to default to.)
  ```
  Exit.
- If the path does not exist or is not a file → error and exit.
- Validate it is a conforming archive by confirming `MANIFEST.yaml` is present:
  ```bash
  unzip -l "$ZIP" | grep -q ' MANIFEST.yaml$' || echo "INVALID"
  ```
  If invalid:
  ```
  [GMB] Error: Not a GMCC kbite archive

  {zip_path} has no MANIFEST.yaml. Only archives produced by /gm_kbite_export
  can be imported.
  ```
  Exit without changes.

### Step 2: Unpack to a Temp Dir and Read the Manifest

```bash
TMP=$(mktemp -d)
unzip -q "$ZIP" -d "$TMP"
```

Read `$TMP/MANIFEST.yaml`. Show the user a summary (export date, source ckfs,
plugin version, and the list of kbites with their `has_root` / `has_digested`
flags) before importing.

### Step 3: Import Each KBite (Per-Collision Resolution)

For each kbite `{name}` in the manifest:

1. **Detect collision**: a collision exists if either destination is already
   present:
   ```bash
   [ -e "$GMCC_KBITE/{name}" ] || [ -e "$GMCC_KBITE_DIGESTED/{name}" ]
   ```

2. **If a collision**, use AskUserQuestion (one question per colliding kbite, or
   batch up to 4 per call) with options:
   - **Overwrite** — replace the existing kbite's root + digested contents.
   - **Skip** — leave the existing kbite untouched; do not import this one.
   - **Import as renamed** — import under `{name}_imported` (append `_2`, `_3`, …
     until the name is free). Original is untouched.

   `finalname` = `{name}` for overwrite, or the deduped renamed value.

3. **Place the components** that the manifest flags as present:
   ```bash
   # Overwrite: clear destinations first so no stale files survive a merge
   # (only when resolving "Overwrite"; for renamed/new the dirs don't exist yet)
   rm -rf "$GMCC_KBITE/{finalname}" "$GMCC_KBITE_DIGESTED/{finalname}"

   if [ -d "$TMP/kbites/{name}/root" ]; then
     mkdir -p "$GMCC_KBITE/{finalname}"
     cp -R "$TMP/kbites/{name}/root/." "$GMCC_KBITE/{finalname}/"
   fi
   if [ -d "$TMP/kbites/{name}/digested" ]; then
     mkdir -p "$GMCC_KBITE_DIGESTED/{finalname}"
     cp -R "$TMP/kbites/{name}/digested/." "$GMCC_KBITE_DIGESTED/{finalname}/"
   fi
   ```
   For "Skip", do nothing for this kbite.

   > If a kbite was renamed, note that its `KBITE_INDEX.md` /
   > `KBITE_RELATIONSHIPS.md` still reference the original name internally — fine
   > for lookup, but flag it in the report so the user can run
   > `/gm_kbite_relate` fixups if desired.

### Step 4: Clean Up and Report

```bash
rm -rf "$TMP"
```

```
KBites Imported

**Archive**: {zip_path}
**Source ckfs**: {source_ckfs from manifest}

## Results
- {name} → imported (root: ✓, digested: ✓)
- {name} → renamed to {name}_imported (collision)
- {name} → skipped (collision, left existing)

## Active Now
Imported kbites are immediately available at:
  $GMCC_KBITE/{finalname}/  +  $GMCC_KBITE_DIGESTED/{finalname}/

Add one to a session with its `kbite:` registry (see the gmcc_kbite skill) to
have GMB load it.
```

---

## Error Handling

**Archive not found / not a file:**
```
[GMB] Error: Archive not found: {zip_path}
```

**Missing MANIFEST.yaml:** see Step 1.

**unzip failure / corrupt archive:**
```
[GMB] Error: Failed to unpack {zip_path}

The archive may be corrupt. Clean up: nothing was written to the ckfs.
```
Remove the temp dir; make no partial writes to `$GMCC_KBITE*`.

**Component missing for a manifest entry:**
If the manifest flags a component present but the directory is absent in the
archive, skip that component and note it in the report (import what is available).

---

## Examples

```bash
# Import a specific archive
/gm_kbite_import ~/Desktop/gmcc_kbites_20260621-201500.zip

# Import the most recent export on the Desktop
/gm_kbite_import
```
