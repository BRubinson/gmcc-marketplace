---
name: gm_kbite_export
description: "Export one digested kbite to a portable gmcc_kbite zip"
argument-hint: "<kbite_code> [output_dir]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob
---

# /gm_kbite_export {kbite_code} [output_dir]

Exports one kbite from this machine's daemon db + digested archive into a
single portable zip: `gmcc_kbite_{code}_{YYYYMMDD}.zip`. The whole flow is
one `gm kbite export` call — the daemon serializes the db rows (paths
scrubbed to machine-neutral placeholders), the CLI stages root docs and the
`.git`-stripped digested sources, and zips with macOS `ditto`. Move the zip
between machines however you like (mail, drive, airdrop); the other side
runs `/gm_kbite_import`.

One kbite per zip. Kbite relationships are NOT resolved on the other side —
`KBITE_RELATIONSHIPS.md` travels as an inert document.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify the kbite exists in the db: `gm kbite get --code {kbite_code} --json`

### If KBite Unknown
```
[GMB] Error: kbite {kbite_code} not found in the db

gm kbite list --all shows every digested kbite on this machine.
```
Exit without changes.

---

## Export

```bash
gm kbite export --code {kbite_code} [--output-dir {output_dir}] --json
```

- Default output dir is the current directory; pass the second argument
  through as `--output-dir` when given.
- A missing digested source tree is fine — the command warns and exports db
  content only (`has_digested: false` in the zip's MANIFEST).
- Large kbites print a size warning before zipping; let it run.

## Report

```
[GMB] KBite exported: {kbite_code}

Zip: {zip_path from the JSON response}
Contents: {resource_count} resources, {file_count} files,
          {kbite_keyword_count + file_keyword_count} keyword attachments
Root docs: {included|none} — Digested sources: {included|none}

Import on the other machine with /gm_kbite_import {zip file}.
```
