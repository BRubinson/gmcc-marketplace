---
name: gm_bot_v4_migrate_kbite
description: "One-shot v4 → current kbite layout migration. Lands KBITE_PURPOSE.md at the kbite root, other indexes under digested/, and pulls legacy FAM maws into $GMCC_KBITE_OPEN."
argument-hint: ""
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gm_bot_v4_migrate_kbite

Migrates the on-disk kbite layout from any pre-current version (v4 flat, v5.3 digested/open) to the current layout. Idempotent — safe to re-run.

**Before** (v4 / v5.2):
```
$GMCC_CKFS_ROOT/kbites/{name}/{KBITE_*.md, primary/, secondary/}
$GMCC_CKFS_ROOT/{repo}/fam/{branch}/maw/{name}/...
```

**Before** (v5.3):
```
$GMCC_KBITE_DIGESTED/{name}/{KBITE_PURPOSE.md, KBITE_*.md, primary/, secondary/}
$GMCC_KBITE_OPEN/{name}/...
```

**After** (current):
```
$GMCC_KBITE/{name}/KBITE_PURPOSE.md             # identity-level (above lifecycle)
$GMCC_KBITE_DIGESTED/{name}/{KBITE_INDEX.md, KBITE_RELATIONSHIPS.md, primary/, secondary/}
$GMCC_KBITE_OPEN/{name}/...
```

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository so detect_repo.sh exports
GMCC_KBITE / GMCC_KBITE_DIGESTED / GMCC_KBITE_OPEN.
```
Exit without proceeding.

1. Verify `$GMCC_KBITE`, `$GMCC_KBITE_DIGESTED`, `$GMCC_KBITE_OPEN` are set (if any are empty, instruct the user to restart Claude Code).
2. Verify `$GMCC_KBITE` exists. If not, nothing to migrate — report and exit.
3. `mkdir -p "$GMCC_KBITE_DIGESTED" "$GMCC_KBITE_OPEN"`.

---

## Phase 1: Per-Kbite Layout Migration

Two sub-steps per kbite: (a) v4-flat layout → digested split, (b) `KBITE_PURPOSE.md` → kbite root.

### Phase 1a: Flat v4 → digested (skip if already migrated)

For each entry in `$GMCC_KBITE/`:

```bash
for entry in "$GMCC_KBITE"/*/; do
    name=$(basename "$entry")
    # Skip the lifecycle subdirs themselves.
    if [ "$name" = "digested" ] || [ "$name" = "open" ]; then
        continue
    fi
    src="$entry"
    dst="$GMCC_KBITE_DIGESTED/$name"

    # If digested dir already exists for this kbite, this kbite is already
    # past Phase 1a — only Phase 1b (PURPOSE relocation) may still apply.
    if [ -d "$dst" ]; then
        echo "phase1a-skip $name — already split"
        continue
    fi

    mkdir -p "$dst"
    # Move index files and resource trees into digested/.
    # Note: KBITE_PURPOSE.md is intentionally NOT in this list — Phase 1b lands it at the kbite root.
    # Legacy KBITE_TRIGGERS.md / KBITE_TRIGGER_MAP.md are intentionally NOT migrated — the
    # trigger-activation paradigm is retired (kbites are inherited via the kbite: registries).
    for item in KBITE_INDEX.md KBITE_RELATIONSHIPS.md \
                primary secondary; do
        if [ -e "$src$item" ]; then
            mv "$src$item" "$dst/"
        fi
    done
    # Phase 1b will handle KBITE_PURPOSE.md below; leave it at $src for now.
done
```

### Phase 1b: Relocate KBITE_PURPOSE.md to kbite root

`KBITE_PURPOSE.md` is identity-level and now lives at `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` (above the digested/open split). Find it in any of its possible legacy locations and land it at the root.

```bash
for entry in "$GMCC_KBITE"/*/; do
    name=$(basename "$entry")
    if [ "$name" = "digested" ] || [ "$name" = "open" ]; then
        continue
    fi
    root_purpose="$GMCC_KBITE/$name/KBITE_PURPOSE.md"
    legacy_in_digested="$GMCC_KBITE_DIGESTED/$name/KBITE_PURPOSE.md"
    legacy_in_root="$entry/KBITE_PURPOSE.md"  # left here by Phase 1a, or already at root

    # If the purpose file is already at the kbite root, nothing to do.
    if [ -f "$root_purpose" ] && [ ! -f "$legacy_in_digested" ]; then
        echo "phase1b-skip $name — purpose already at kbite root"
        continue
    fi

    mkdir -p "$GMCC_KBITE/$name"

    # Prefer the digested copy if present (it's the v5.3 location).
    if [ -f "$legacy_in_digested" ]; then
        if [ -f "$root_purpose" ]; then
            echo "warn $name — KBITE_PURPOSE.md exists at BOTH root and digested; left both in place for manual review"
        else
            mv "$legacy_in_digested" "$root_purpose"
            echo "phase1b-moved $name — digested → root"
        fi
    fi

    # If the file is at the kbite root already (legacy v4 path equals new path), it's fine.
done

# Phase 1c: clean up any now-empty legacy kbite folders left behind by Phase 1a.
for entry in "$GMCC_KBITE"/*/; do
    name=$(basename "$entry")
    if [ "$name" = "digested" ] || [ "$name" = "open" ]; then
        continue
    fi
    # Only rmdir if empty — never delete content.
    rmdir "$entry" 2>/dev/null || true
done
```

Track per-kbite outcome: `migrated`, `phase1a-skipped`, `phase1b-moved`, `phase1b-skipped`, `warn_both_locations`, or `error_left_in_place`.

---

## Phase 2: (removed in v6.0.0)

Phase 2 used to migrate legacy per-branch FAM maws (`$GMCC_CKFS_ROOT/{repo}/fam/{branch}/maw/`) into `$GMCC_KBITE_OPEN/`. That code path is removed in v6.0.0: FAM directories no longer exist as a runtime concept, and any leftover `fam/` data is now handled by `/gm_cleanup` (which can archive or delete it interactively).

If you have a pre-v5.3 install with FAM maws still on disk, run `/gm_cleanup` after this command — it surfaces every legacy `fam/` tree as a finding.

---

## Phase 3: Final Report

```
KBite Migration Complete

## Digested (Phase 1)
| KBite | Outcome |
|-------|---------|
| {name} | {migrated | phase1a-skipped | phase1b-moved | phase1b-skipped | warn_both_locations | error_left_in_place} |

## Next Steps

- Verify with: ls $GMCC_KBITE_DIGESTED/ and ls $GMCC_KBITE/
- Re-run safely: this command is idempotent.
- Run `/gm_cleanup` to audit any remaining legacy state (FAM dirs, etc.)
- Update ~/.zshrc gmcc env block (see plugins/gmcc/MIGRATION.md).
```

---

## Error Handling

**Env vars missing:**
```
[GMB] Error: $GMCC_KBITE_DIGESTED / $GMCC_KBITE_OPEN not set

Restart Claude Code so detect_repo.sh exports the new vars.
```

**`mv` failure on a specific item:**
Skip the offending item, leave the source in place, mark the kbite as `error_left_in_place` in the final report. Do not abort the whole run — other kbites may still migrate cleanly.
