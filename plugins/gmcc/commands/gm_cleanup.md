---
name: gm_cleanup
description: Audit $GMCC_CKFS_ROOT for non-compliant structure (legacy v5.x FAM, orphan registry entries, missing required files, malformed yaml) and interactively resolve each finding with the user.
argument-hint: ""
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gm_cleanup

Run the GM-CDE CKFS cleanup auditor. Walks `$GMCC_CKFS_ROOT`, reports non-compliant state, prompts per-finding for an action. Full spec in `$GMCC_PLUGIN_ROOT/skills/gmcc_cleanup/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify `$GMCC_CKFS_ROOT` exists. If not, suggest `/gm_init` and exit.

---

## Execution

Read the `gmcc_cleanup` skill (`$GMCC_PLUGIN_ROOT/skills/gmcc_cleanup/SKILL.md`) for the complete walk strategy and finding categories.

Follow that skill's protocol:

1. Walk `$GMCC_CKFS_ROOT` per the bounded strategy in the skill.
2. Collect findings.
3. Print the audit report.
4. **NEVER auto-fix.** For each finding, AskUserQuestion with the per-category options (default first, always non-destructive).
5. Apply the user's chosen action.
6. Print the cleanup-complete summary.

---

## Special Modes

**Bulk action for legacy v5.x FAM**: after surfacing the first 3 `fam/` findings individually, offer:
```
You have {N} legacy v5.x FAM branches remaining. How would you like to handle them?

- Archive all (recommended) - Move every legacy fam/ tree to ~/gmcc_ckfs/_archive/legacy_fam/
- Continue per-finding - Decide each one individually
- Skip all - Leave them in place
```

**Dry-run mode** (`/gm_cleanup --dry-run`): walks and reports findings, but skips the interactive resolution loop entirely. Useful for auditing without committing to changes.

---

## Output

See the skill file's "Output Format" section for the exact templates.
