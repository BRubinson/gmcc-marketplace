---
name: gmcc_session_cleanup
description: Audit the CURRENT session folder ($GMCC_SESSION_PATH) for non-compliant state — prompt-folder integrity, index-file consistency, changed_files/phase_history integrity, and schema drift — and interactively resolve each finding. Session-scoped counterpart to /gmcc_environment_cleanup.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gmcc_session_cleanup

Run the GM-CDE **session-scoped** cleanup auditor. Walks only the current
session at `$GMCC_SESSION_PATH` (not the whole CKFS — that is
`/gmcc_environment_cleanup`), reports non-compliant state, and prompts
per-finding for an action. Full spec in
`$GMCC_PLUGIN_ROOT/skills/gmcc_session_cleanup/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify `$GMCC_SESSION_PATH` is set and exists. If not, the environment never
resolved a session — suggest restarting Claude Code from inside a git repo (or
running the `gmcc_session_creation` skill) and exit.

---

## Execution

Read the `gmcc_session_cleanup` skill
(`$GMCC_PLUGIN_ROOT/skills/gmcc_session_cleanup/SKILL.md`) for the complete
session-scoped walk strategy and finding categories.

Follow that skill's protocol:

1. Walk **only** `$GMCC_SESSION_PATH` per the bounded strategy in the skill.
2. Collect findings across the four categories (prompt folder integrity, index
   file consistency, changed_files & phase_history integrity, schema drift).
3. Print the audit report.
4. **NEVER auto-fix.** For each finding, AskUserQuestion with the per-category
   options (default first, always non-destructive).
5. Apply the user's chosen action; append a `cleanup_actions` entry to
   `$GMCC_SESSION_PATH/session_data.gmcc.yaml`.
6. Print the cleanup-complete summary.

---

## Special Modes

**Dry-run mode** (`/gmcc_session_cleanup --dry-run`): walks and reports findings,
but skips the interactive resolution loop entirely. Useful for auditing the
session without committing to changes.

---

## Output

See the skill file's "Output Format" section for the exact templates.
