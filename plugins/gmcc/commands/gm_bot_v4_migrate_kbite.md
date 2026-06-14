---
name: gm_bot_v4_migrate_kbite
description: "One-shot v4 → v5.3 kbite layout migration. Flips existing kbites into the digested/open split and pulls legacy FAM maws into $GMCC_KBITE_OPEN."
argument-hint: ""
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gm_bot_v4_migrate_kbite

Migrates the on-disk kbite layout from pre-v5.3 to the new digested/open split. Idempotent — safe to re-run.

**Before** (v5.2):
```
$GMCC_CKFS_ROOT/kbites/{name}/{KBITE_*.md, primary/, secondary/}
$GMCC_CKFS_ROOT/{repo}/fam/{branch}/maw/{name}/...
```

**After** (v5.3):
```
$GMCC_KBITE_DIGESTED/{name}/{KBITE_*.md, primary/, secondary/}
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

## Phase 1: Per-Kbite Digested Migration

For each entry in `$GMCC_KBITE/`:

```bash
for entry in "$GMCC_KBITE"/*/; do
    name=$(basename "$entry")
    # Skip the new top-level subdirs themselves.
    if [ "$name" = "digested" ] || [ "$name" = "open" ]; then
        continue
    fi
    src="$entry"
    dst="$GMCC_KBITE_DIGESTED/$name"

    if [ -d "$dst" ]; then
        echo "skip $name — already migrated"
        continue
    fi

    mkdir -p "$dst"
    # Move kbite-level files and resource trees that exist.
    for item in KBITE_PURPOSE.md KBITE_INDEX.md KBITE_TRIGGERS.md \
                KBITE_TRIGGER_MAP.md KBITE_RELATIONSHIPS.md \
                primary secondary; do
        if [ -e "$src$item" ]; then
            mv "$src$item" "$dst/"
        fi
    done

    # Remove the now-empty legacy kbite folder.
    rmdir "$src" 2>/dev/null || echo "warn: $src not empty after migration, left in place"
done
```

Track per-kbite outcome: `migrated`, `skipped`, or `error_left_in_place`.

---

## Phase 2: Legacy FAM Maw Migration

```bash
for legacy in "$GMCC_CKFS_ROOT"/*/fam/*/maw/*/; do
    [ -d "$legacy" ] || continue
    kbite_name=$(basename "$legacy")
    dst="$GMCC_KBITE_OPEN/$kbite_name"
    ...
done
```

For each legacy maw:

1. If `$dst` does not exist → `mv "$legacy" "$dst"`. Record `moved`.
2. If `$dst` exists → use AskUserQuestion:
   - **Skip** — leave the legacy maw in place (default).
   - **Replace** — `rm -rf "$dst" && mv "$legacy" "$dst"`. Existing open maw is overwritten.
   - **Merge** — `cp -rn "$legacy"/* "$dst"/` (no-clobber merge), then `rm -rf "$legacy"`.
   - **Abort** — stop migration immediately.
3. After moving, try to `rmdir` the parent `$GMCC_CKFS_ROOT/{repo}/fam/{branch}/maw/` if empty.

Track per-maw outcome.

---

## Phase 3: Final Report

```
KBite Migration Complete

## Digested (Phase 1)
| KBite | Outcome |
|-------|---------|
| {name} | {migrated | skipped | error_left_in_place} |

## Open Maws (Phase 2)
| Legacy Path | KBite | Outcome |
|-------------|-------|---------|
| {legacy} | {name} | {moved | skipped | replaced | merged} |

## Next Steps

- Verify with: ls $GMCC_KBITE_DIGESTED/ and ls $GMCC_KBITE_OPEN/
- Re-run safely: `/gm_bot_v4_migrate_kbite` is idempotent.
- Update ~/.zshrc gmcc env block (see plugins/gmcc/MIGRATION.md).
```

---

## Error Handling

**Env vars missing:**
```
[GMB] Error: $GMCC_KBITE_DIGESTED / $GMCC_KBITE_OPEN not set

Restart Claude Code so the v5.3 detect_repo.sh exports the new vars.
```

**`mv` failure on a specific item:**
Skip the offending item, leave the source in place, mark the kbite as `error_left_in_place` in the final report. Do not abort the whole run — other kbites may still migrate cleanly.

**Phase 2 abort:**
Phase 1 changes are already persisted (they don't depend on phase 2). Just report what was done and what remains.
