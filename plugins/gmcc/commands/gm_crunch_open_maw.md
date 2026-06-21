---
name: gm_crunch_open_maw
description: "Open a maw for collecting kbite resources"
argument-hint: "<kbite_name>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob
---

# /gm_crunch_open_maw {kbite_name}

Opens a "maw" (processing directory) under the kbite for collecting crunchable resources that will be processed into the digested index.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_KBITE` is set)
2. Parse `{kbite_name}` argument

---

## Directory Structure Reference

Per the **gmcc_kbite** skill, the open maw structure is:

```
$GMCC_KBITE_OPEN/{kbite_name}/
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
if [ -d "$GMCC_KBITE_OPEN/{kbite_name}" ]; then
    echo "Maw already exists for {kbite_name}"
fi
```

If maw exists, ask user:
- **Continue**: Use existing maw (report current status)
- **Reset**: Delete and recreate maw

### Step 2: Check for Parent KBite Purpose

Check if the target kbite already has a purpose file at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md`:

```bash
if [ ! -f "$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md" ]; then
    # New kbite — need to create KBITE_PURPOSE
fi
```

### Step 3: Create Directory Structure

Create the maw directory tree:

```bash
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/primary/documentation"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/primary/example_project"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/primary/api_reference"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/primary/blogs"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/primary/all_others"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/secondary/documentation"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/secondary/example_project"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/secondary/api_reference"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/secondary/blogs"
mkdir -p "$GMCC_KBITE_OPEN/{kbite_name}/secondary/all_others"
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

### Step 5: Create KBITE_PURPOSE.md (If New KBite)

If the target kbite doesn't yet have a purpose file at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md`, create it at the kbite root (above the digested/open lifecycle split):

```bash
mkdir -p "$GMCC_KBITE/{kbite_name}"
```

Per the **gmcc_kbite** skill KBITE_PURPOSE format, use AskUserQuestion to gather:
- Why this kbite exists
- What's in scope / out of scope
- Target use cases

Then create `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md`:

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
- [ ] KBITE_INDEX accurately reflects the digested resources
```

---

## Final Report

```
Maw Opened: {kbite_name}

**Location**: $GMCC_KBITE_OPEN/{kbite_name}/
**KBite Root** (purpose): $GMCC_KBITE/{kbite_name}/
**Digested Index** (created on first digest): $GMCC_KBITE_DIGESTED/{kbite_name}/

## Directory Structure Created

```
{kbite_name}/open/
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

{If KBITE_PURPOSE created: "Created $GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md for new kbite"}

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

**Invalid kbite name:**
```
[GMB] Error: Invalid kbite name

Kbite names must be lowercase with underscores only (e.g., "claude_code_sdk").
```

**Write permission denied:**
```
[GMB] Error: Cannot create maw directory

Check permissions on $GMCC_KBITE_OPEN/{kbite_name}
```
