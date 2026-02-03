# Chewed: checkpointing

**Source**: primary/documentation/checkpointing
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| checkpointing.md | md | Official Claude Code documentation on checkpointing feature - automatic tracking and rewinding of Claude's edits |

---

## 2. Key Learnings Summary

1. **Automatic Safety Net**: Claude Code automatically creates checkpoints before each edit at every user prompt, providing a session-level undo mechanism that persists across sessions for 30 days.

2. **Granular Rewind Options**: Users can selectively restore conversation only, code only, or both together using Esc+Esc or /rewind command, enabling flexible recovery strategies.

3. **Scope and Limitations**: Checkpointing only tracks direct file edits from Claude's file editing tools, NOT bash command modifications or external changes, and is designed as session-level recovery not a replacement for version control.

---

## 3. Detailed Analysis

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use checkpointing as a safety net for ambitious, wide-scale refactoring tasks |
| 2 | BAD | Do not rely on checkpointing to track file modifications made through bash commands (rm, mv, cp, etc.) |
| 3 | GOOD | Access rewind menu quickly via Esc+Esc keyboard shortcut or /rewind command |
| 4 | GOOD | Use "Code only" rewind option to experiment with implementation variations while preserving conversation context |
| 5 | BAD | Do not treat checkpointing as a replacement for version control - still commit to Git |
| 6 | GOOD | Leverage checkpoints for exploring alternative implementation approaches |
| 7 | GOOD | Use "Conversation only" rewind to backtrack conversation direction while keeping code changes |
| 8 | BAD | Do not expect checkpoints to capture manual file edits made outside Claude Code |

---

## 4. Keywords and Triggers

### Primary Keywords
checkpointing, rewind, undo, session recovery, automatic tracking, file edits, checkpoint restoration, Esc+Esc, /rewind command, 30-day cleanup, conversation rollback, code rollback

### Suggested Triggers
checkpoint, rewind, undo, rollback, restore, Esc+Esc, session recovery, automatic tracking, bash commands not tracked, version control complement

---

## Cross-References

- Interactive mode documentation (keyboard shortcuts, session controls)
- Built-in commands documentation (/rewind command details)
- CLI reference (command-line options)
- Version control workflows (Git integration context)
