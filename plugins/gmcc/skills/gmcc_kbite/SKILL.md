---
name: gmcc_kbite
description: GM-CDE Knowledge Bite System - Defines persistent knowledge directories (kbites) that store pre-tokenized, indexed reference material for efficient lookup by GMCC agents and contexts. Includes the crunchable maw workflow for ingesting new knowledge sources.
user-invocable: false
---

# GMCC KBite System

The KBite (Knowledge Bite) system provides persistent, indexed knowledge storage for GM-CDE. KBites are pre-analyzed reference materials that GMCC agents can efficiently query during development tasks.

---

## What is a KBite?

A **KBite** is a persisted analysis directory format that is:
- **Pre-tokenized**: Content has been analyzed and summarized for efficient consumption
- **Indexed**: Searchable via keywords, triggers, and relationships
- **Persistent**: Stored at the system level, shared across all repositories
- **Referenced**: GMCC agents and contexts can efficiently lookup relevant information

KBites transform raw reference materials (documentation, examples, APIs) into structured knowledge that GMB can leverage during development.

---

## KBite Storage Location

KBites are stored at the **system level**, shared across all repositories:

```
$GMCC_CKFS_ROOT/kbites/
└── {kbite_name}/
    └── ... (structure below)
```

Example: `~/gmcc_ckfs/kbites/claude_code_sdk/`

---

## Directory Structure

### Persisted KBite Structure

```
$GMCC_CKFS_ROOT/kbites/{kbite_name}/
├── KBITE_PURPOSE.md                    # Why this kbite exists
├── KBITE_INDEX.md                      # Master index of all digested resources
├── KBITE_TRIGGERS.md                   # Trigger words that activate this kbite
├── KBITE_TRIGGER_MAP.md                # Trigger → Index entry mappings
├── KBITE_RELATIONSHIPS.md              # Relationships to other kbites
│
├── primary/                            # Axis 1: Primary sources
│   ├── documentation/                  # Axis 2: Source types
│   │   ├── {resource_name}/
│   │   │   └── {source_files...}
│   │   └── {resource_name}_chewed.md   # Chewed file alongside source folder
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
│
└── secondary/                          # Axis 1: Secondary sources
    ├── documentation/
    ├── example_project/
    ├── api_reference/
    ├── blogs/
    └── all_others/
```

### Crunchable Maw Structure (Temporary Processing)

The **maw** is a temporary holding area for resources being processed ("crunched") into a kbite. Located within the FAM:

```
$GMCC_FAM_PATH/maw/{kbite_name}/
├── MAW_INDEX.md                        # Index of crunchables in this maw
│
├── primary/
│   ├── documentation/
│   │   ├── {crunchable_name}/
│   │   │   └── {raw_source_files...}
│   │   └── {crunchable_name}_chewed.md     # Chewed file alongside source folder
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
│
└── secondary/
    ├── documentation/
    ├── example_project/
    ├── api_reference/
    ├── blogs/
    └── all_others/
```

---

## Two-Axis Classification System

Resources are classified along two axes:

### Axis 1: Source Authority

| Type | Description | Weight Modifier |
|------|-------------|-----------------|
| **primary** | Official authority on the content (official docs, first-party examples) | +20 relevance |
| **secondary** | Knowledgeable but non-official (community tutorials, third-party analysis) | +0 relevance |

### Axis 2: Content Type

| Type | Description | Example |
|------|-------------|---------|
| **documentation** | Official functionality and capability docs | SDK reference guides |
| **example_project** | Complete implementations or code samples | GitHub example repos |
| **api_reference** | Raw API/function/library references | TypeScript definitions |
| **blogs** | Less structured commentary and tutorials | Dev.to articles |
| **all_others** | Anything else | Forum posts, videos |

### Classification Path

Resources are stored at: `{axis1}/{axis2}/{resource_name}/`

Example: `primary/documentation/claude_code_hooks/`

---

## Index File Formats

### KBITE_INDEX.md (Persisted KBite)

The master index for a digested kbite:

```markdown
# KBite Index: {kbite_name}

**Purpose**: {link to KBITE_PURPOSE.md}
**Last Updated**: {ISO timestamp}
**Total Resources**: {count}

## Resource Index

| Resource | Axis | Path | Keywords | Relevance | Confidence | Unique Keywords |
|----------|------|------|----------|-----------|------------|-----------------|
| {name} | {primary/secondary}/{type} | {full_path} | {keyword1, keyword2} | {0-100} | {0-100} | {kw1, kw2, kw3} |

## Keyword Cross-Reference

| Keyword | Resources | Best Resource |
|---------|-----------|---------------|
| {keyword} | {resource1, resource2} | {highest relevance} |
```

### MAW_INDEX.md (Temporary Processing)

Tracks crunchables during processing:

```markdown
# Maw Index: {kbite_name}

**Target KBite**: {kbite_name}
**Opened**: {ISO timestamp}
**Status**: {open | chewing | ready_to_digest}

## Crunchable Index

| Resource | Path | Status | Keywords | Relevance | Uniqueness | Unique Keywords | Expansion Weight |
|----------|------|--------|----------|-----------|------------|-----------------|------------------|
| {name} | {axis1/axis2/name} | {pending | chewing | chewed} | {kw1, kw2} | {0-100} | {0-100} | {kw1, kw2, kw3} | {0-100} |

### Status Values
- **pending**: Resource added, not yet analyzed
- **chewing**: Agent currently processing
- **chewed**: Analysis complete, ready for digest

### Weight Columns
- **Relevance**: 0-100 score of relevance to KBITE_PURPOSE
- **Uniqueness**: 0-100 score of how unique this resource is vs existing
- **Unique Keywords**: Top 3 keywords this resource adds that others don't have
- **Expansion Weight**: 0-100 score of new info this adds to existing keywords
```

---

## Chewed File Format

When a crunchable is "chewed" by `gmcc:agent:kbite_crunch_chew()`, it produces a `{resource_name}_chewed.md` file:

```markdown
# Chewed: {resource_name}

**Source**: {axis1}/{axis2}/{resource_name}
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: {ISO timestamp}
**Confidence**: {0-100}

---

## 1. Contents Overview

A glossary/table of contents of the raw source contents:

| File | Type | Description |
|------|------|-------------|
| {filename} | {md/ts/json/etc} | {what this file contains} |

**Full Paths**:
- `{$GMCC_CKFS_ROOT}/kbites/{kbite}/{axis1}/{axis2}/{resource}/{file}`

---

## 2. Key Learnings Summary

The most important things that can be learned for the general purpose:

1. **{Learning 1}**: {description}
2. **{Learning 2}**: {description}
3. **{Learning 3}**: {description}

---

## 3. Detailed Analysis

### Snippets and References

| Location | Importance | Confidence | Summary |
|----------|------------|------------|---------|
| {file:line} | {0-100} | {0-100} | {what this teaches} |

### Takeaways

Each takeaway is marked as GOOD (do this) or BAD (avoid this):

| # | Type | Takeaway | Source |
|---|------|----------|--------|
| 1 | GOOD | {thing to do} | {file:line or description} |
| 2 | BAD | {thing to avoid} | {file:line or description} |
| 3 | GOOD | {thing to do} | {file:line or description} |
| 4 | GOOD | {thing to do} | {file:line or description} |
| 5 | BAD | {thing to avoid} | {file:line or description} |

**Minimum 5 takeaways required per chewed file.**

---

## 4. Keywords and Triggers

### Primary Keywords
{keyword1}, {keyword2}, {keyword3}

### Suggested Triggers
Words that should cause GMB to reference this resource:
- {trigger1}: {why}
- {trigger2}: {why}
```

---

## Trigger System

### KBITE_TRIGGERS.md

Lists trigger words that should activate this kbite:

```markdown
# KBite Triggers: {kbite_name}

When any of these concepts appear in a prompt or project context, GMB should check this kbite.

## Trigger Words

| Trigger | Confidence | Context |
|---------|------------|---------|
| {word} | {0-100} | {when this trigger applies} |

## Anti-Triggers

Words that might seem related but should NOT activate this kbite:

| Word | Reason |
|------|--------|
| {word} | {why it's not relevant} |
```

### KBITE_TRIGGER_MAP.md

Maps triggers to the most relevant index entries:

```markdown
# KBite Trigger Map: {kbite_name}

Quick lookup from trigger word to relevant resources.

| Trigger | Best Resource | Path | Relevance |
|---------|---------------|------|-----------|
| {trigger} | {resource_name} | {axis1/axis2/name} | {0-100} |
```

---

## KBITE_PURPOSE.md

Defines the purpose and scope of a kbite:

```markdown
# KBite Purpose: {kbite_name}

## Why This KBite Exists
{Clear statement of what knowledge this kbite captures}

## Scope
- **In Scope**: {what this kbite covers}
- **Out of Scope**: {what this kbite does NOT cover}

## Target Use Cases
1. {use case 1}
2. {use case 2}

## Related KBites
| KBite | Relationship |
|-------|--------------|
| {name} | {how they relate} |

## Success Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}
```

---

## KBITE_RELATIONSHIPS.md

Tracks relationships between kbites:

```markdown
# KBite Relationships: {kbite_name}

## Outgoing Relationships

| Target KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {target} | {depends_on | extends | complements | supersedes} | {description} |

## Incoming Relationships

| Source KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {source} | {depends_on | extends | complements | supersedes} | {description} |
```

### Relationship Types

| Type | Meaning |
|------|---------|
| **depends_on** | This kbite requires knowledge from target |
| **extends** | This kbite builds upon target with more detail |
| **complements** | Related but distinct knowledge areas |
| **supersedes** | This kbite replaces outdated target |

---

## Crunchable Workflow

### 1. Open Maw (`/gm_crunch_open_maw {kbite_name}`)

Creates the maw structure in FAM for collecting crunchables.

### 2. Add Crunchables (Manual)

User places raw source files in appropriate `{axis1}/{axis2}/{resource_name}/` directories.

### 3. Chew (`/gm_crunch_chew {kbite_name}`)

Processes each crunchable:
1. Indexes untracked crunchables in MAW_INDEX
2. Spawns `gmcc:agent:kbite_crunch_chew()` for each pending crunchable
3. Generates `{resource_name}_chewed.md` files
4. Updates MAW_INDEX with status

### 4. Digest (`/gm_crunch_digest {kbite_name}`)

Moves chewed resources to persisted kbite:
1. Reviews all chewed crunchables
2. Spawns architects to determine optimal index structure
3. Moves resources from maw to `$GMCC_CKFS_ROOT/kbites/{kbite_name}/`
4. Updates KBITE_INDEX
5. Generates KBITE_TRIGGERS and KBITE_TRIGGER_MAP
6. Deletes the maw

---

## GMB Behavioral Rules for KBites

### Trigger Awareness (CRITICAL)

When operating in GM-CDE mode, GMB MUST:

1. **Check Triggers on Every Prompt**: Before beginning any task, scan the user prompt for kbite trigger words
2. **Load Relevant KBites**: When triggers match, read the KBITE_TRIGGER_MAP and relevant chewed files
3. **Reference in Responses**: When using kbite knowledge, cite the source (e.g., "Per claude_code_sdk kbite...")
4. **Update Triggers**: When discovering new relevant terms during work, note them for future trigger updates

### Trigger Check Protocol

```
1. Parse user prompt for keywords
2. For each kbite in $GMCC_CKFS_ROOT/kbites/:
   a. Read KBITE_TRIGGERS.md
   b. Check for keyword matches
   c. If match found with confidence > 70:
      - Read KBITE_TRIGGER_MAP.md
      - Load relevant chewed files
      - Include knowledge in context
3. Proceed with task using loaded knowledge
```

### When to Create New KBites

GMB should suggest creating a kbite when:
- User repeatedly references the same external documentation
- A new SDK/library/tool is being integrated
- Complex domain knowledge needs persistent reference
- Current context would benefit from pre-analyzed material

---

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_crunch_open_maw {kbite_name}` | Create maw structure for collecting crunchables |
| `/gm_crunch_chew {kbite_name}` | Process crunchables and generate analysis |
| `/gm_crunch_digest {kbite_name}` | Move chewed resources to persistent kbite |
| `/gm_kbite_relate {from} {to} {description}` | Define relationship between kbites |

---

## Agent Reference

| Agent | Purpose |
|-------|---------|
| `gmcc:agent:kbite_crunch_chew()` | Analyze crunchable and produce chewed file |

---

## Integration with GMCC

The kbite system integrates with core GMCC:

1. **Environment**: Uses `$GMCC_CKFS_ROOT` for storage location
2. **FAM Integration**: Maw is stored in current FAM during processing
3. **Agent System**: Uses GMCC agent framework for chewing
4. **Trigger System**: Adds behavioral rule to core GMCC skill

---

## Syntax Reference

### KBite Invocation

```
gmcc:agent:kbite_crunch_chew(
  kbite: "{kbite_name}",
  crunchable: "{resource_name}",
  axis1: "primary" | "secondary",
  axis2: "documentation" | "example_project" | "api_reference" | "blogs" | "all_others"
)
```

---

## Best Practices

1. **One Topic Per KBite**: Keep kbites focused on a single SDK/tool/domain
2. **Primary First**: Prioritize official documentation over secondary sources
3. **Quality Over Quantity**: Better to have 5 excellent chewed resources than 20 shallow ones
4. **Update Triggers**: Regularly review and refine trigger words based on usage
5. **Cross-Reference**: Use KBITE_RELATIONSHIPS to connect related knowledge
6. **Cite Sources**: Always reference kbite knowledge with attribution
