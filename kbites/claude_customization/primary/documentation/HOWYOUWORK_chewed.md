# Chewed: HOWYOUWORK

**Source**: primary/documentation/HOWYOUWORK
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| HOWYOUWORK | markdown | Official Claude Code documentation explaining the agentic loop, tools, sessions, permissions, and best practices |

---

## 2. Key Learnings Summary

1. **The Agentic Loop Architecture**: Claude Code operates through a three-phase loop (gather context, take action, verify results) powered by models for reasoning and tools for action.

2. **Session Management and Context Windows**: Sessions are ephemeral with no persistent memory between runs. Context management through compaction, skills, and subagents. CLAUDE.md provides cross-session persistence.

3. **Safety Through Checkpoints and Permissions**: Every file edit creates a reversible checkpoint (Esc twice to rewind). Three permission modes: Default, Auto-accept edits, and Plan mode.

---

## 3. Technical Details

### Model Selection
- Sonnet for general tasks
- Opus for complex architectural decisions
- Accessible via /model command or --model flag

### Tool Categories
- File operations
- Search
- Execution
- Web
- Code intelligence

### Extension Mechanisms
- Skills
- MCP servers
- Hooks
- Subagents

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Put persistent rules in CLAUDE.md rather than relying on conversation history |
| 2 | GOOD | Use --fork-session for parallel work from same starting point |
| 3 | GOOD | Set disable-model-invocation: true on manually-invoked skills |
| 4 | GOOD | Separate research from implementation using plan mode |
| 5 | BAD | Don't resume the same session in multiple terminals simultaneously |
| 6 | GOOD | Provide verification targets (tests, screenshots, expected output) |
| 7 | GOOD | Use subagents for long-running tasks to isolate context consumption |
| 8 | GOOD | Whitelist trusted commands in .claude/settings.json |
| 9 | BAD | Don't rely on session-scoped permissions when resuming |
| 10 | GOOD | Interrupt Claude mid-execution by typing corrections |

---

## 4. Keywords and Triggers

### Primary Keywords
agentic loop, context window, checkpoints, permissions, sessions, tools, models, CLAUDE.md, subagents, skills, MCP, hooks, plan mode, fork session, compaction

### Suggested Triggers
how claude works, context management, session, permissions, checkpoint, agentic, CLAUDE.md, best practices

---

## Cross-References

- /en/common-workflows
- /en/features-overview
- /en/model-config
- /en/memory
- /en/iam
- /en/skills, /en/mcp, /en/hooks, /en/sub-agents
