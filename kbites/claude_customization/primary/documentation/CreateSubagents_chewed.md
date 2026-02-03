# Chewed: CreateSubagents

**Source**: primary/documentation/CreateSubagents
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| CreateSubagents | markdown | Official Claude Code documentation on creating and configuring custom subagents |

---

## 2. Key Learnings Summary

1. **Subagents are isolated AI assistants**: Subagents run in separate context windows with custom system prompts, specific tool access, and independent permissions. They preserve the main conversation context by handling exploration and high-volume operations separately.

2. **Four scope levels with priority hierarchy**: Subagents can be defined at CLI flag (highest priority), project-level (`.claude/agents/`), user-level (`~/.claude/agents/`), or plugin-level (lowest priority).

3. **Tool restrictions and permission modes enable security**: Subagents support allowlist (`tools`) and denylist (`disallowedTools`) for tool access, plus permission modes like `plan`, `acceptEdits`, `dontAsk`, and `bypassPermissions`.

4. **Built-in subagents handle common workflows**: Claude Code includes Explore (read-only Haiku), Plan (research during plan mode), and general-purpose (full-capability) built-in subagents.

5. **Hooks enable conditional validation**: PreToolUse hooks can validate operations before execution, and SubagentStart/SubagentStop hooks manage lifecycle events.

---

## 3. Technical Details

### Frontmatter Schema
```yaml
name: agent-name
description: When to invoke (required for auto-delegation)
tools: [Read, Grep, Glob]  # Allowlist
disallowedTools: [Bash]     # Denylist
model: haiku|sonnet|opus|inherit
permissionMode: default|acceptEdits|dontAsk|bypassPermissions|plan
skills: [skill-name]        # Preload skills
hooks:
  PreToolUse: [...]
  PostToolUse: [...]
  Stop: [...]
```

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Create project-level subagents in `.claude/agents/` and check into version control |
| 2 | GOOD | Use read-only tool restrictions for code reviewers and exploratory subagents |
| 3 | GOOD | Write detailed descriptions with "use proactively" to enable automatic delegation |
| 4 | GOOD | Delegate high-volume operations to subagents to preserve main context |
| 5 | GOOD | Use PreToolUse hooks with exit code 2 for fine-grained validation |
| 6 | GOOD | Set model to 'haiku' for fast, cost-effective operations |
| 7 | GOOD | Preload domain knowledge using the skills field |
| 8 | GOOD | Resume subagents to continue work with full conversation history |
| 9 | BAD | Never use bypassPermissions mode unless absolutely necessary |
| 10 | BAD | Don't spawn subagents from within subagents - they cannot nest |
| 11 | BAD | Avoid running many parallel subagents that return detailed results |

---

## 4. Keywords and Triggers

### Primary Keywords
subagent, delegation, context isolation, tool restrictions, permission modes, hooks, lifecycle, foreground, background, resume, skills preload, scope hierarchy

### Suggested Triggers
subagent, delegate, context window, task tool, permission mode, PreToolUse, agents command, explore agent, background task, resume subagent

---

## Cross-References

- Skills documentation (skill preloading)
- Hooks reference (PreToolUse, SubagentStart/Stop)
- Permissions system
- CLI reference (--agents flag)
