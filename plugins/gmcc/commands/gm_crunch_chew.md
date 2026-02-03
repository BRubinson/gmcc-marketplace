---
name: gm_crunch_chew
description: "Process crunchable resources in a maw to generate chewed analysis files"
argument-hint: "<kbite_name>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob, Grep, Task
---

# /gm_crunch_chew {kbite_name}

Processes all crunchable resources in the maw, generating analysis ("chewed") files for each one.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: crunch-chew | STATE: indexing
```

**Write state:** `{"task": "crunch-chew", "state": "indexing"}` to `.claude/GMB_STATE.json`

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_CKFS_ROOT` exists)
2. Verify maw exists at `$GMCC_FAM_PATH/maw/{kbite_name}/`
3. Read MAW_INDEX.md for current state
4. Read KBITE_PURPOSE.md from parent kbite (if exists) for context

### If Maw Missing
```
[GMB] Error: No maw found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} first to create the maw.
```
Exit without changes.

---

## Directory Structure Reference

Per the **gmcc_kbite** skill:

- Crunchables are at: `{axis1}/{axis2}/{crunchable_name}/`
- Chewed files go at: `{axis1}/{axis2}/{crunchable_name}_chewed.md` (alongside source folder)

---

## Execution Steps

### Step 1: Index Untracked Crunchables

**Update state:** `{"task": "crunch-chew", "state": "indexing"}`

Scan all axis1/axis2 directories for new crunchable folders:

```bash
# Find all directories that could be crunchables
for axis1 in primary secondary; do
    for axis2 in documentation example_project api_reference blogs all_others; do
        path="$GMCC_FAM_PATH/maw/{kbite_name}/$axis1/$axis2"
        if [ -d "$path" ]; then
            # List directories (crunchables) in this path
            for dir in "$path"/*/; do
                if [ -d "$dir" ]; then
                    crunchable_name=$(basename "$dir")
                    # Check if already in MAW_INDEX
                    # Check if chewed file exists
                fi
            done
        fi
    done
done
```

For each new crunchable found:
1. Add entry to MAW_INDEX with status "pending"
2. Leave Keywords, Relevance, Uniqueness, Expansion Weight as "-" (to be filled by chew agent)

### Step 2: Identify Pending Crunchables

Read MAW_INDEX.md and collect all entries with status "pending" or not yet chewed.

Also check for crunchables that have a folder but no corresponding `_chewed.md` file.

### Step 3: Update MAW_INDEX Status

**Update state:** `{"task": "crunch-chew", "state": "chewing"}`

Update MAW_INDEX.md to show overall status as "chewing".

### Step 4: Spawn Chew Agents

For each pending crunchable, spawn `gmcc:agent:kbite_crunch_chew()`:

Per the **gmcc_kbite** skill agent invocation:

```
gmcc:agent:kbite_crunch_chew(
  kbite: "{kbite_name}",
  crunchable: "{crunchable_name}",
  axis1: "{primary|secondary}",
  axis2: "{documentation|example_project|api_reference|blogs|all_others}"
)
```

**Implementation via Task tool:**

```
Task tool:
  subagent_type: gmcc:gmcc_agent_kbite_crunch_chew
  prompt: |
    Chew the crunchable resource for kbite "{kbite_name}".

    **Crunchable**: {crunchable_name}
    **Location**: $GMCC_FAM_PATH/maw/{kbite_name}/{axis1}/{axis2}/{crunchable_name}/
    **Output**: $GMCC_FAM_PATH/maw/{kbite_name}/{axis1}/{axis2}/{crunchable_name}_chewed.md

    **KBite Purpose** (if available):
    {Contents of KBITE_PURPOSE.md}

    Follow the gmcc_kbite skill chewed file format exactly.
```

**Parallelization**: If multiple crunchables are pending, spawn agents in parallel (up to 4 concurrent).

### Step 5: Write Chewed Files

Each agent returns the chewed content. Write to the correct location:

```
$GMCC_FAM_PATH/maw/{kbite_name}/{axis1}/{axis2}/{crunchable_name}_chewed.md
```

### Step 6: Update MAW_INDEX

After each chew completes, update MAW_INDEX.md:
1. Change status from "pending" to "chewed"
2. Extract Keywords from chewed file section 4
3. Assign Relevance score from chewed file Confidence
4. Calculate Uniqueness by comparing keywords to other chewed resources
5. List top 3 Unique Keywords
6. Calculate Expansion Weight based on new information added

### Step 7: Final Index Update

After all crunchables are processed:
1. Update MAW_INDEX.md status to "ready_to_digest"
2. Calculate summary statistics

---

## MAW_INDEX Update Format

Per the **gmcc_kbite** skill:

```markdown
| Resource | Path | Status | Keywords | Relevance | Uniqueness | Unique Keywords | Expansion Weight |
|----------|------|--------|----------|-----------|------------|-----------------|------------------|
| {name} | {axis1/axis2/name} | chewed | {kw1, kw2, kw3} | {0-100} | {0-100} | {kw1, kw2, kw3} | {0-100} |
```

---

## Final Report

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Chew Complete: {kbite_name}

**Maw Location**: $GMCC_FAM_PATH/maw/{kbite_name}/

## Processing Summary

| Metric | Count |
|--------|-------|
| Total Crunchables | {n} |
| Newly Indexed | {n} |
| Successfully Chewed | {n} |
| Failed | {n} |

## Chewed Resources

| Resource | Axis | Keywords | Relevance |
|----------|------|----------|-----------|
| {name} | {axis1}/{axis2} | {top 3 keywords} | {score} |

## Next Steps

1. Review chewed files for accuracy
2. Add more crunchables if needed, then run `/gm_crunch_chew {kbite_name}` again
3. When ready, run `/gm_crunch_digest {kbite_name}` to finalize the kbite
```

---

## Error Handling

**Maw not found:**
```
[GMB] Error: Maw not found for {kbite_name}

Run /gm_crunch_open_maw {kbite_name} first.
```

**No crunchables found:**
```
[GMB] Warning: No crunchables found in maw

Add raw source files to appropriate directories:
- primary/documentation/{name}/
- primary/example_project/{name}/
- secondary/blogs/{name}/
etc.

Then run /gm_crunch_chew {kbite_name} again.
```

**Agent failure:**
```
[GMB] Warning: Failed to chew {crunchable_name}

Error: {error message}

The crunchable remains in "pending" status. Review the source files and try again.
```

**Partial completion:**
```
[GMB] Partial completion: {n}/{total} crunchables processed

Failed crunchables:
- {name}: {error}

Run /gm_crunch_chew {kbite_name} again to retry failed items.
```
