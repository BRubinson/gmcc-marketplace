---
name: gmcc_environment_cleanup
description: Audit the GMCC environment — daemon/db health, db-vs-disk drift, leftover pre-daemon yaml runtime files, archive hygiene, host config drift — and interactively resolve each finding with the user. Environment-wide counterpart to /gmcc_session_cleanup.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gmcc_environment_cleanup

Run the GM-CDE environment auditor. Checks daemon/db health via `gm`, walks
`$GMCC_CKFS_ROOT` (bounded), reports non-compliant state, prompts per-finding
for an action. Full spec in `$GMCC_PLUGIN_ROOT/skills/gmcc_cleanup/SKILL.md`.

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

1. Check daemon health (`gm ping` / `gm status` / `gm context get`).
2. Walk `$GMCC_CKFS_ROOT` per the bounded strategy in the skill.
3. Collect findings.
4. Print the audit report.
5. **NEVER auto-fix.** For each finding, AskUserQuestion with the per-category options (default first, always non-destructive).
6. Apply the user's chosen action (db repairs via `gm` only; filesystem moves into `_archive/cold_storage/`).
7. Print the cleanup-complete summary.

---

## Special Modes

**Dry-run mode** (`/gmcc_environment_cleanup --dry-run`): walks and reports findings, but skips the interactive resolution loop entirely. Useful for auditing without committing to changes.

---

## Output

See the skill file's "Output Format" section for the exact templates.
