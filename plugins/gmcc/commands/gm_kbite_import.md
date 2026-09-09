---
name: gm_kbite_import
description: "Import a gmcc_kbite zip into this machine's daemon db"
argument-hint: "<zip_path> [overwrite]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# /gm_kbite_import {zip_path} [overwrite]

Imports a `gmcc_kbite_{code}_{date}.zip` produced by `/gm_kbite_export` on
any gmcc machine: db rows land in one transaction (keywords remapped by text
into the shared vocabulary, placeholder paths rehydrated to this machine's
roots), the digested source tree is restored under the local
`kbite_digested_root`, and root docs land under `kbite_root`.

The import NEVER registers the kbite at any scope — registration is always
an explicit `gm kbite add`.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify the zip exists at `{zip_path}`.
2. `gm backup` — the documented pre-flight before any content-mutating
   import.

### If Zip Missing
```
[GMB] Error: no zip at {zip_path}
```
Exit without changes.

---

## Import

```bash
gm kbite import --zip-file {zip_path} --json
```

The default collision policy is **skip**: if the kbite code already exists
on this machine, nothing changes and the response says so. When that
happens, ask via AskUserQuestion whether to overwrite (overwrite replaces
the kbite's CONTENT under its existing uuid — scope registrations survive;
the previous digested tree is moved to `_archive/cold_storage/`, never
deleted). On approval (or when the `overwrite` argument was passed
up-front):

```bash
gm kbite import --zip-file {zip_path} --on-collision overwrite --json
```

## Report

```
[GMB] KBite imported: {code}

{resource_count} resources, {file_count} files, {keyword_count} keywords
Digested sources: {restored path | archive carried none}

The kbite is NOT registered anywhere yet. To activate it here:
  gm kbite add --code {code}            (session scope)
  gm kbite add --code {code} --scope instance|project
```

If the import was skipped:
```
[GMB] KBite {code} already exists — import skipped (non-destructive default)

Re-run with overwrite to replace its content.
```
