---
name: gmcc_kbite
description: GM-CDE Knowledge Bite System - Defines persistent knowledge directories (kbites) that store pre-tokenized, indexed reference material for efficient lookup by GMCC agents and contexts. Includes the crunchable maw workflow for ingesting new knowledge sources.
user-invocable: false
disable-model-invocation: true
# [FIX #3] Added disable-model-invocation to prevent auto-loading on every prompt.
# This skill is only needed during /gm_crunch_* operations, not general conversation.
# Saves ~478 lines (~2,800 tokens) of context per message when not doing kbite work.
---

# GMCC KBite System

The KBite (Knowledge Bite) system provides persistent, indexed knowledge storage for GM-CDE. KBites are pre-analyzed reference materials that GMCC agents can efficiently query during development tasks.

---

## What is a KBite?

A **KBite** is a persisted analysis directory format that is:
- **Pre-tokenized**: Content has been analyzed and summarized for efficient consumption
- **Indexed**: Searchable via keywords and relationships
- **Persistent**: Stored at the system level, shared across all repositories
- **Referenced**: GMCC agents and contexts can efficiently lookup relevant information

KBites transform raw reference materials (documentation, examples, APIs) into structured knowledge that GMB can leverage during development.

---

## KBite Storage Location

KBites are stored at the **system level**, shared across all repositories. The kbites root has two top-level lifecycle subfolders — `digested/` for persisted indexes and `open/` for in-progress maws — plus one identity-level file (`KBITE_PURPOSE.md`) per kbite that lives at the kbite root, above the lifecycle split:

```
$GMCC_KBITE/                                # = $GMCC_CKFS_ROOT/kbites/
├── {kbite_name}/
│   └── KBITE_PURPOSE.md                    # identity-level — defined once, lives above digested/open
├── digested/                               # = $GMCC_KBITE_DIGESTED — canonical active indexes
│   └── {kbite_name}/...
└── open/                                   # = $GMCC_KBITE_OPEN — in-progress maws
    └── {kbite_name}/...
```

Example: `~/gmcc_ckfs/kbites/claude_code_sdk/KBITE_PURPOSE.md` (purpose), `~/gmcc_ckfs/kbites/digested/claude_code_sdk/` (digested index).

### Env vars

| Var | Value | Per-kbite usage |
|-----|-------|-----------------|
| `GMCC_KBITE` | `$GMCC_CKFS_ROOT/kbites` | — |
| `GMCC_KBITE_DIGESTED` | `$GMCC_CKFS_ROOT/kbites/digested` | `$GMCC_KBITE_DIGESTED/{name}/...` |
| `GMCC_KBITE_OPEN` | `$GMCC_CKFS_ROOT/kbites/open` | `$GMCC_KBITE_OPEN/{name}/...` |

The list of known kbites is `ls $GMCC_KBITE_DIGESTED/`.

---

## Directory Structure

### Digested KBite Structure (Persisted, Active Index)

`KBITE_PURPOSE.md` lives at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md` (above the lifecycle split). The digested folder holds only generated indexes and the resource tree:

```
$GMCC_KBITE_DIGESTED/{kbite_name}/
├── KBITE_INDEX.md                      # Master index of all digested resources
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

### Open Maw Structure (Temporary Processing)

The **open maw** is a temporary holding area for resources being processed ("crunched") into the digested index. It lives under `$GMCC_KBITE_OPEN/{kbite_name}/` — there is at most one open maw per kbite, system-wide:

```
$GMCC_KBITE_OPEN/{kbite_name}/
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
- `{$GMCC_KBITE_DIGESTED}/{kbite}/{axis1}/{axis2}/{resource}/{file}`

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

## 4. Keywords

### Primary Keywords
{keyword1}, {keyword2}, {keyword3}
```

---

## KBITE_PURPOSE.md

Defines the purpose and scope of a kbite. Lives at `$GMCC_KBITE/{kbite_name}/KBITE_PURPOSE.md` (above the digested/open lifecycle split — purpose is identity-level, not lifecycle-level):

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

## Export / Import Archive Format

KBites can be moved between ckfs installations as a single zip archive via
`/gm_kbite_export` and `/gm_kbite_import`. The archive is **self-describing and
ckfs-relocatable**: it stores no absolute source paths, so import rebuilds every
path from the *importing* machine's `$GMCC_KBITE` / `$GMCC_KBITE_DIGESTED`.

Export carries each kbite's **root** (identity files such as `KBITE_PURPOSE.md`)
and its **digested** index. **Open maws are not exported** — only finalized
knowledge travels.

Because raw `example_project` sources and `.git` history can make a kbite many GB,
export asks for a **payload scope** each run (default **everything_minus_git**):

| Scope | Includes | Excludes |
|-------|----------|----------|
| `knowledge_only` | indexes, `KBITE_PURPOSE.md`, all `*_chewed.md` | raw sources, `.git` |
| `everything_minus_git` *(default)* | raw sources + chewed analysis + indexes | `.git` |
| `everything` | byte-for-byte | nothing |

```
~/Desktop/gmcc_kbites_{YYYYMMDD-HHMMSS}.zip
├── MANIFEST.yaml                  # exported kbites + which components are present
└── kbites/
    └── {kbite_name}/
        ├── root/...               # contents of $GMCC_KBITE/{name}/ (sans digested/ open/)
        └── digested/...           # contents of $GMCC_KBITE_DIGESTED/{name}/
```

### MANIFEST.yaml

A plain index file (like `MAW_INDEX.md` / `KBITE_INDEX.md`, it is **not** a
registered yeet type):

```yaml
gmcc_export_version: 1
gmcc_plugin_version: "{plugin.json version}"
exported_at: {ISO 8601}
source_ckfs: {basename of source ckfs, informational only}
scope: everything_minus_git       # knowledge_only | everything_minus_git | everything
kbites:
  - name: {kbite_name}
    has_root: true                # true if root/ is present in the archive
    has_digested: true            # true if digested/ is present in the archive
```

### Import collision policy

When an imported kbite's name already exists in the target ckfs, the user is
asked **per kbite**: **overwrite** (clears destination first — no stale merge),
**skip** (leave existing untouched), or **import as renamed** (`{name}_imported`,
deduped with a numeric suffix). Nothing is ever overwritten silently.

---

## Crunchable Workflow

### 1. Open Maw (`/gm_crunch_open_maw {kbite_name}`)

Creates the maw structure at `$GMCC_KBITE_OPEN/{kbite_name}/` for collecting crunchables.

### 2. Add Crunchables (Manual)

User places raw source files in appropriate `{axis1}/{axis2}/{resource_name}/` directories.

### 3. Chew (`/gm_crunch_chew {kbite_name}`)

Processes each crunchable:
1. Indexes untracked crunchables in MAW_INDEX
2. Spawns `gmcc:agent:kbite_crunch_chew()` for each pending crunchable
3. Generates `{resource_name}_chewed.md` files
4. Updates MAW_INDEX with status

### 4. Digest (`/gm_crunch_digest {kbite_name}`)

Moves chewed resources from the open maw into the digested index:
1. Reviews all chewed crunchables
2. Spawns architects to determine optimal index structure
3. Moves resources from `$GMCC_KBITE_OPEN/{kbite_name}/` to `$GMCC_KBITE_DIGESTED/{kbite_name}/`
4. Updates KBITE_INDEX
5. Deletes the `open/` folder

---

## GMB Behavioral Rules for KBites

### KBite Awareness (CRITICAL)

KBites are **inherited, not trigger-matched**. The kbites relevant to the current
work are declared up the ckfs hierarchy — project → instance → session → prompt —
and recorded in each level's `kbite:` registry. When operating in GM-CDE mode,
GMB MUST:

1. **Read the Registry**: the active kbites are listed in
   `$GMCC_SESSION_PATH/session_data.gmcc.yaml`'s `kbite:` field (and a prompt's
   own `kbite:` list). There is no per-prompt keyword scan.
2. **Load Registered KBites**: for a registered kbite, read its
   `KBITE_PURPOSE.md` + `KBITE_INDEX.md` and the relevant chewed files.
3. **Reference in Responses**: when using kbite knowledge, cite the source
   (e.g., "Per the swift_code_edit kbite...").
4. **Explicit Add Only**: add a kbite to a registry only when the user explicitly
   asks for it. Never add one on your own initiative.

### KBite Load Protocol

```
1. Read the kbite: registry from session_data.gmcc.yaml (and the active prompt)
2. For each registered kbite in $GMCC_KBITE_DIGESTED/:
   a. Read $GMCC_KBITE/{name}/KBITE_PURPOSE.md + KBITE_INDEX.md
   b. Load the relevant chewed files (explore with find/cat/rg as needed)
   c. Include knowledge in context
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
| `/gm_kbite_export [kbite_name ...]` | Zip selected kbites (root + digested) to a portable archive on the Desktop |
| `/gm_kbite_import {zip_path}` | Import a kbite archive into the current ckfs (asks per name-collision) |

---

## Agent Reference

| Agent | Purpose |
|-------|---------|
| `gmcc:agent:kbite_crunch_chew()` | Analyze crunchable and produce chewed file |

---

## Integration with GMCC

The kbite system integrates with core GMCC:

1. **Environment**: Uses `$GMCC_KBITE`, `$GMCC_KBITE_DIGESTED`, `$GMCC_KBITE_OPEN` for path resolution
2. **System-Level Storage**: Open maws live next to digested indexes under the same kbite folder — independent of FAM/branch
3. **Agent System**: Uses GMCC agent framework for chewing
4. **Registry System**: Active kbites are declared in the `kbite:` registries of the project/instance/session/prompt data files

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
4. **Keep the Index Current**: Regularly review and refine KBITE_INDEX as resources change
5. **Cross-Reference**: Use KBITE_RELATIONSHIPS to connect related knowledge
6. **Cite Sources**: Always reference kbite knowledge with attribution
