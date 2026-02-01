---
name: gm_famalogue
description: Compiles all thoughts from the current branch into an updated Famalouge.md - creates a coherent narrative of decisions and context.
argument-hint:
disable-model-invocation: true
allowed-tools: Read, Write, Glob
---

# Compile Famalouge

You are compiling all thoughts into a coherent Famalouge for the current branch.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: famalogue | STATE: compiling
```

## Pre-Flight

1. Verify GM-CDE is initialized
2. Load current FAM

## Gather Thoughts

Read all files in `$GMCC_FAM_PATH/thoughts/`:
- Sort by timestamp (oldest first)
- Parse each thought for key information

## Compile Famalouge

Create a narrative that includes:

1. **Current Understanding** - Latest state of the branch
2. **Key Decisions** - Major decisions and their reasoning
3. **Context for New Sessions** - What someone (or future Claude) needs to know

### Compilation Rules

- Preserve the essence of each thought
- Combine related decisions
- Remove redundancy
- Keep chronological flow where relevant
- Focus on "why" over "what"

## Write Famalouge.md

```markdown
# Famalouge: {branch}

## Current Understanding
{Synthesized understanding of where the branch is now}

## Key Decisions

### {Decision Category 1}
- **Decision**: {what was decided}
- **Reasoning**: {why}
- **Date**: {when}

### {Decision Category 2}
- **Decision**: {what was decided}
- **Reasoning**: {why}
- **Date**: {when}

{etc.}

## Timeline

### {timestamp 1} - {topic}
{Brief summary of thought}

### {timestamp 2} - {topic}
{Brief summary of thought}

{etc.}

## Context for New Sessions
{Bullet points of essential context}
- {context 1}
- {context 2}
- {context 3}

---
*Compiled from {n} thoughts by: GMB*
*Last compiled: {NOW}*
```

## Report

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Famalouge compiled from {n} thoughts.

Key decisions captured:
- {decision 1}
- {decision 2}

Famalouge is ready for context restoration.
```
