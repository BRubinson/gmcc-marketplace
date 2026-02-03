---
name: gm_fam_fmt
description: Formats the FAM Purpose.md file - reorganizes syntax and cleans up without changing meaning. Human content is preserved.
argument-hint:
disable-model-invocation: true
allowed-tools: Read, Write
---

# Format FAM Purpose

You are formatting the Purpose.md file for the current FAM.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: fam-fmt | STATE: in_progress
```

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized
2. Read current Purpose.md

## Formatting Rules

**PRESERVE:**
- All human-written content
- The meaning of all sections
- All goals and criteria

**IMPROVE:**
- Consistent heading levels
- Consistent list formatting (- vs *)
- Remove extra blank lines
- Fix markdown syntax issues
- Ensure proper checkbox format `- [ ]`
- Standardize date formats

## Standard Format

Reorganize to this structure:

```markdown
# Branch Purpose: {branch_name}

## Why This Branch Exists
{Human description - preserve exactly}

## Goals
- [ ] {Goal 1}
- [ ] {Goal 2}
- [ ] {Goal 3}

## Completion Criteria
- [ ] {Criterion 1}
- [ ] {Criterion 2}

## Notes
{Any additional context - if present}

---
*Created: {date}*
*This file is human-editable. GMB may format but not change meaning.*
```

## Process

1. Read current Purpose.md
2. Parse sections and content
3. Reorganize into standard format
4. Preserve all human content exactly
5. Write formatted version

## Report

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Purpose.md formatted.

Changes:
- {what was reorganized}

Content preserved. Review the file to verify.
```
