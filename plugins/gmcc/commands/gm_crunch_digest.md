---
name: gm_crunch_digest
description: "Move chewed resources from maw to persistent kbite storage"
argument-hint: "<kbite_name>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, Grep, Task
---

# /gm_crunch_digest {kbite_name}

Finalizes a kbite by moving all chewed resources from the maw to persistent storage and generating the index file.

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
2. Verify maw exists at `$GMCC_KBITE_OPEN/{kbite_name}/`
3. Read MAW_INDEX.md - verify status is "ready_to_digest" or has chewed resources
4. Verify KBITE_PURPOSE.md exists at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md`

### If Maw Missing
```
[GMB] Error: No maw found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} and /gm_crunch_chew {kbite_name} first.
```
Exit without changes.

### If No Chewed Resources
```
[GMB] Error: No chewed resources found in maw

Run /gm_crunch_chew {kbite_name} to process crunchables first.
```
Exit without changes.

### If KBITE_PURPOSE Missing
```
[GMB] Error: KBITE_PURPOSE.md not found

The kbite purpose file is required at:
$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md

Run /gm_crunch_open_maw {kbite_name} to create it.
```
Exit without changes.

---

## Directory Structure Reference

Per the **gmcc_kbite** skill:

**Source (open maw):**
```
$GMCC_KBITE_OPEN/{kbite_name}/
├── MAW_INDEX.md
├── {axis1}/{axis2}/{resource_name}/
└── {axis1}/{axis2}/{resource_name}_chewed.md
```

**Destination (digested index):**
```
$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md       # identity-level (created at open-maw time)
$GMCC_KBITE_DIGESTED/{kbite_name}/
├── KBITE_INDEX.md
├── KBITE_RELATIONSHIPS.md
├── {axis1}/{axis2}/{resource_name}/
└── {axis1}/{axis2}/{resource_name}_chewed.md
```

---

## Execution Steps

### Step 1: Review Chewed Resources

1. Read all `*_chewed.md` files from the maw
2. Collect all keywords and takeaways
3. Read existing KBITE_INDEX.md (if exists) for merge

### Step 2: Spawn Architect Agents

Spawn 4 `gmcc:agent:code_architect` agents with different methodologies to determine optimal:
- Index structure
- Keyword cross-reference organization

```
gmcc:agent:code_architect(
  goal: "Design optimal kbite index structure for {kbite_name}",
  methodology: "{conservative|aggressive|pragmatic|alternative}",
  context: {
    kbite_purpose: "{KBITE_PURPOSE contents}",
    chewed_resources: [{list of chewed file summaries}],
    existing_index: "{KBITE_INDEX contents if exists}"
  }
)
```

**Architect Output Expected:**
- Recommended KBITE_INDEX structure
- Keyword cross-reference suggestions
- Any resources to exclude or flag

### Step 3: Synthesize Architect Recommendations

Combine insights from all 4 architects:
1. Use consensus for index structure (>2 architects agree)
2. Take highest-confidence keyword mappings
3. Flag disagreements for review

### Step 4: Create/Update Persisted KBite Directory

Ensure directory structure exists:

```bash
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/primary/documentation"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/primary/example_project"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/primary/api_reference"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/primary/blogs"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/primary/all_others"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/secondary/documentation"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/secondary/example_project"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/secondary/api_reference"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/secondary/blogs"
mkdir -p "$GMCC_KBITE_DIGESTED/{kbite_name}/secondary/all_others"
```

### Step 5: Move Resources

For each chewed resource in the maw:

```bash
# Move source folder
cp -r "$GMCC_KBITE_OPEN/{kbite_name}/{axis1}/{axis2}/{resource_name}" \
      "$GMCC_KBITE_DIGESTED/{kbite_name}/{axis1}/{axis2}/"

# Move chewed file
cp "$GMCC_KBITE_OPEN/{kbite_name}/{axis1}/{axis2}/{resource_name}_chewed.md" \
   "$GMCC_KBITE_DIGESTED/{kbite_name}/{axis1}/{axis2}/"
```

### Step 6: Generate KBITE_INDEX.md

Per the **gmcc_kbite** skill KBITE_INDEX format:

```markdown
# KBite Index: {kbite_name}

**Purpose**: See [KBITE_PURPOSE.md](../{kbite_name}/KBITE_PURPOSE.md) (at the kbite root)
**Last Updated**: {ISO timestamp}
**Total Resources**: {count}

## Resource Index

| Resource | Axis | Path | Keywords | Relevance | Confidence | Unique Keywords |
|----------|------|------|----------|-----------|------------|-----------------|
| {name} | {axis1}/{axis2} | {path} | {keywords} | {0-100} | {0-100} | {unique_kw} |

## Keyword Cross-Reference

| Keyword | Resources | Best Resource |
|---------|-----------|---------------|
| {keyword} | {res1, res2} | {highest_relevance} |
```

### Step 7: Initialize KBITE_RELATIONSHIPS.md

If not exists, create per the **gmcc_kbite** skill format:

```markdown
# KBite Relationships: {kbite_name}

## Outgoing Relationships

| Target KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| *None yet* | - | - |

## Incoming Relationships

| Source KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| *None yet* | - | - |
```

### Step 8: Delete Open Maw

After successful migration:

```bash
rm -rf "$GMCC_KBITE_OPEN/{kbite_name}"
```

---

## Final Report

```
Digest Complete: {kbite_name}

**KBite Location**: $GMCC_KBITE_DIGESTED/{kbite_name}/

## Digest Summary

| Metric | Count |
|--------|-------|
| Resources Moved | {n} |
| Keywords Indexed | {n} |

## Generated Files

- KBITE_INDEX.md - Master resource index
- KBITE_RELATIONSHIPS.md - Cross-kbite relationships

## Maw Cleanup

The open maw at `$GMCC_KBITE_OPEN/{kbite_name}/` has been deleted.

## Next Steps

1. Add relationships with `/gm_kbite_relate {kbite_name} {other_kbite} {description}`
2. Review KBITE_INDEX.md and refine as needed
```

---

## Error Handling

**Maw not found:**
```
[GMB] Error: Maw not found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} and /gm_crunch_chew {kbite_name} first.
```

**No chewed resources:**
```
[GMB] Error: No chewed resources in maw

Run /gm_crunch_chew {kbite_name} to process crunchables.
```

**Move failure:**
```
[GMB] Error: Failed to move {resource_name}

Error: {error message}

The maw has NOT been deleted. Fix the issue and run /gm_crunch_digest {kbite_name} again.
```

**Architect agent failure:**
```
[GMB] Warning: Architect agent failed

Proceeding with basic index structure. Review and refine the index manually.
```
