# GMCC Migration Guide: v3.x to v4.0.0

This guide covers breaking changes and migration steps for upgrading from GMCC v3.x to v4.0.0.

## Overview

v4.0.0 is a major refactor that adopts native Claude Code patterns for better integration, model selection, and hook lifecycle management.

### Key Changes

| Area | v3.x | v4.0.0 |
|------|------|--------|
| Agent Location | `agents/*.md` | `prompts/*.prompt.md` |
| Agent Model | sonnet (default) | opus (all agents) |
| Hooks | SessionStart only | SessionStart, UserPromptSubmit, PostToolUse, Stop |
| KBite Triggers | Manual checking | Automated via hooks |
| Output Styles | None | 4 methodology styles |
| FAM Sync | Manual `/gm_fam_sync` | Auto on Edit/Write |

---

## Breaking Changes

### 1. Agent Directory Migration

**v3.x**: Agents lived in `plugins/gmcc/agents/`
**v4.0.0**: Agents now live in `plugins/gmcc/prompts/` with `.prompt.md` extension

If you have custom agents, migrate them:

```bash
# Old location
plugins/gmcc/agents/my_custom_agent.md

# New location
plugins/gmcc/prompts/my_custom_agent.prompt.md
```

Update the frontmatter to include `model: opus`:

```yaml
---
name: my_custom_agent
description: My custom agent description
model: opus
tools: Read, Grep, Glob
---
```

### 2. Agent Invocation Syntax

**v3.x**: Custom syntax
```
gmcc:agent:code_explorer(target: "src/", methodology: "pragmatic")
```

**v4.0.0**: Native Task tool invocation
```
Task tool:
  subagent_type: gmcc:gmcc_agent_code_explorer
  model: opus
  prompt: |
    Explore src/ directory.
    Methodology: pragmatic
```

### 3. Model Selection

**v3.x**: Default model (sonnet) for all agents
**v4.0.0**: opus for all agents (quality-first strategy)

To override per-session, set environment variable:
```bash
export CLAUDE_CODE_SUBAGENT_MODEL=sonnet
```

### 4. Hook Configuration

**v3.x**: Only `SessionStart` hook configured
**v4.0.0**: Full hook lifecycle

New hooks added:
- `UserPromptSubmit`: Checks kbite triggers on every prompt
- `PostToolUse`: Auto-syncs FAM on Edit/Write operations
- `Stop`: Validates ECLAIR workflow state before stopping

If you have custom hooks, merge them with the new hooks.json:

```json
{
  "hooks": {
    "SessionStart": [...],
    "UserPromptSubmit": [...],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

---

## New Features

### Automated KBite Trigger Loading

v4.0.0 automatically scans user prompts for kbite trigger keywords and loads matching context.

**How it works**:
1. `SessionStart` caches all kbite triggers from `KBITE_TRIGGERS.md` files
2. `UserPromptSubmit` hook matches prompt against cached triggers
3. Matching kbites are exported to `$GMCC_MATCHED_KBITES` environment variable

**Requirements**:
- Kbites must have `KBITE_TRIGGERS.md` with trigger keywords
- Format: lines starting with `- ` are trigger words

### Output Styles

Four methodology output styles are available:

```
/output-style gmcc-conservative  # Stability-first
/output-style gmcc-aggressive    # Progress-first
/output-style gmcc-pragmatic     # Balanced approach
/output-style gmcc-alternative   # Challenge conventions
```

### Auto FAM Sync

ChangedFiles.md is automatically updated after Edit/Write operations. No need to manually run `/gm_fam_sync` during active development.

---

## Migration Steps

### Step 1: Update Plugin

Pull the latest GMCC plugin from the marketplace.

### Step 2: Verify Hooks

Check that your hooks.json includes all v4.0.0 hooks. The new scripts must be executable:

```bash
chmod +x plugins/gmcc/scripts/kbite_triggers_cache.sh
chmod +x plugins/gmcc/scripts/kbite_check.sh
chmod +x plugins/gmcc/scripts/auto_fam_sync.sh
```

### Step 3: Migrate Custom Agents

If you have custom agents:
1. Move from `agents/` to `prompts/`
2. Rename with `.prompt.md` extension
3. Add `model: opus` to frontmatter

### Step 4: Update Custom Commands

If you have custom commands that invoke agents, update the invocation syntax to use native Task tool format.

### Step 5: Test ECLAIR Workflow

Run a quick test with `/gm_task` to verify the workflow executes correctly with opus model.

---

## Rollback

To temporarily use v3.x behavior:

1. **Model override**: Set `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`
2. **Disable new hooks**: Remove new entries from hooks.json
3. **Use legacy agents**: Reference the `agents/` directory (not migrated away)

---

## Questions?

For issues with migration, check:
- `$GMCC_CKFS_ROOT/fam/v3/ECLAIR_BRAIN.md` for learned patterns
- Plugin logs for hook execution errors
- `/gmcc_boot` for environment diagnostics
