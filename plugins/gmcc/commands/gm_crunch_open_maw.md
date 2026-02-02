---
name: gm_crunch_open_maw
description: Create a maw structure in FAM for collecting crunchable resources to process into a kbite
argument-hint: {kbite_name}
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob
---

# /gm_crunch_open_maw {kbite_name}

Opens a "maw" (processing directory) in the current FAM for collecting crunchable resources that will be processed into a kbite.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: crunch-open-maw | STATE: creating
```

**Write state:** `{"task": "crunch-open-maw", "state": "creating"}` to `.claude/GMB_STATE.json`

---

## Pre-Flight Checks

1. Verify GM-CDE is initialized (`$GMCC_CKFS_ROOT` exists)
2. Verify current branch has a FAM (`$GMCC_FAM_PATH` exists)
3. Parse `{kbite_name}` argument

### If FAM Missing
```
[GMB] Error: No FAM found for current branch

Run /gm_load_branch first to initialize the branch FAM.
```
Exit without changes.

---

## Directory Structure Reference

Per the **gmcc_kbite** skill, the maw structure is:

```
$GMCC_FAM_PATH/maw/{kbite_name}/
├── MAW_INDEX.md
├── primary/
│   ├── documentation/
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
└── secondary/
    ├── documentation/
    ├── example_project/
    ├── api_reference/
    ├── blogs/
    └── all_others/
```

---

## Execution Steps

### Step 1: Check for Existing Maw

```bash
if [ -d "$GMCC_FAM_PATH/maw/{kbite_name}" ]; then
    echo "Maw already exists for {kbite_name}"
fi
```

If maw exists, ask user:
- **Continue**: Use existing maw (report current status)
- **Reset**: Delete and recreate maw

### Step 2: Check for Parent KBite

Check if the target kbite already exists at `$GMCC_CKFS_ROOT/kbites/{kbite_name}/`:

```bash
if [ ! -d "$GMCC_CKFS_ROOT/kbites/{kbite_name}" ]; then
    # Parent kbite doesn't exist - need to create KBITE_PURPOSE
fi
```

### Step 3: Create Directory Structure

Create the maw directory tree:

```bash
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/primary/documentation"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/primary/example_project"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/primary/api_reference"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/primary/blogs"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/primary/all_others"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/secondary/documentation"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/secondary/example_project"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/secondary/api_reference"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/secondary/blogs"
mkdir -p "$GMCC_FAM_PATH/maw/{kbite_name}/secondary/all_others"
```

### Step 4: Create MAW_INDEX.md

Per the **gmcc_kbite** skill MAW_INDEX format:

```markdown
# Maw Index: {kbite_name}

**Target KBite**: {kbite_name}
**Opened**: {ISO timestamp}
**Status**: open

## Crunchable Index

| Resource | Path | Status | Keywords | Relevance | Uniqueness | Unique Keywords | Expansion Weight |
|----------|------|--------|----------|-----------|------------|-----------------|------------------|
| *No crunchables yet* | - | - | - | - | - | - | - |

## Status Legend
- **pending**: Resource added, not yet analyzed
- **chewing**: Agent currently processing
- **chewed**: Analysis complete, ready for digest

## Next Steps
1. Add raw source files to appropriate `{axis1}/{axis2}/{resource_name}/` directories
2. Run `/gm_crunch_chew {kbite_name}` to process crunchables
3. Run `/gm_crunch_digest {kbite_name}` to finalize the kbite
```

### Step 5: Create KBITE_PURPOSE.md (If Parent Missing)

If the target kbite doesn't exist at `$GMCC_CKFS_ROOT/kbites/{kbite_name}/`, create the parent structure with KBITE_PURPOSE:

```bash
mkdir -p "$GMCC_CKFS_ROOT/kbites/{kbite_name}"
```

Per the **gmcc_kbite** skill KBITE_PURPOSE format, use AskUserQuestion to gather:
- Why this kbite exists
- What's in scope / out of scope
- Target use cases

Then create:

```markdown
# KBite Purpose: {kbite_name}

## Why This KBite Exists
{User-provided purpose}

## Scope
- **In Scope**: {User-provided scope}
- **Out of Scope**: {User-provided exclusions}

## Target Use Cases
1. {Use case 1}
2. {Use case 2}

## Related KBites
| KBite | Relationship |
|-------|--------------|
| *None yet* | - |

## Success Criteria
- [ ] Contains primary documentation sources
- [ ] Chewed files cover all key concepts
- [ ] Trigger words accurately identify when to use this kbite
```

---

## Final Report

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Maw Opened: {kbite_name}

**Location**: $GMCC_FAM_PATH/maw/{kbite_name}/
**Target KBite**: $GMCC_CKFS_ROOT/kbites/{kbite_name}/

## Directory Structure Created

```
maw/{kbite_name}/
├── MAW_INDEX.md
├── primary/
│   ├── documentation/
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
└── secondary/
    └── (same structure)
```

{If KBITE_PURPOSE created: "Created KBITE_PURPOSE.md for new kbite"}

## Next Steps

1. **Add crunchables**: Place raw source files in appropriate directories
   - Official docs → `primary/documentation/{name}/`
   - Example repos → `primary/example_project/{name}/` or `secondary/example_project/{name}/`
   - API references → `primary/api_reference/{name}/`
   - Blog posts → `secondary/blogs/{name}/`

2. **Chew**: Run `/gm_crunch_chew {kbite_name}` to analyze crunchables

3. **Digest**: Run `/gm_crunch_digest {kbite_name}` to finalize the kbite
```

---

## Error Handling

**FAM path not found:**
```
[GMB] Error: FAM not initialized

Run /gm_load_branch to create FAM for current branch.
```

**Invalid kbite name:**
```
[GMB] Error: Invalid kbite name

Kbite names must be lowercase with underscores only (e.g., "claude_code_sdk").
```

**Write permission denied:**
```
[GMB] Error: Cannot create maw directory

Check permissions on $GMCC_FAM_PATH
```
