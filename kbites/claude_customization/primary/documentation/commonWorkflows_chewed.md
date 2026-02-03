# Chewed: commonWorkflows

**Source**: primary/documentation/commonWorkflows
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| commonWorkflows | md | Comprehensive documentation of practical Claude Code workflows for everyday development tasks |

---

## 2. Key Learnings Summary

1. **Interactive Workflow Patterns**: Claude Code supports multiple interaction modes (Normal, Auto-Accept, Plan Mode) that can be toggled during sessions using keyboard shortcuts (Shift+Tab).

2. **Subagent Architecture**: Claude Code uses specialized AI subagents for task delegation, supporting both automatic delegation and explicit invocation, with capability to create custom project-specific subagents in `.claude/agents/`.

3. **Session Management and Context**: Sessions are automatically saved per project directory, can be named for easy retrieval, support forking and resumption.

4. **Extended Thinking Mode**: Configurable reasoning system allocating up to 31,999 tokens for internal reasoning, valuable for complex architectural decisions.

5. **Unix-Style Integration**: Claude Code functions as a command-line utility with pipes, structured output formats, and build script integration.

6. **File and Resource References**: The @ syntax enables direct file and directory inclusion, MCP resource fetching, and image analysis.

---

## 3. Detailed Analysis

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use Plan Mode (Shift+Tab or --permission-mode plan) for safe codebase exploration |
| 2 | GOOD | Name sessions with /rename early for easy retrieval later |
| 3 | GOOD | Create project-specific agents in .claude/agents/ with descriptive descriptions |
| 4 | GOOD | Use @ references to include files, directories, and MCP resources directly |
| 5 | BAD | Don't use cmd+v to paste images, use ctrl+v instead |
| 6 | GOOD | Install code intelligence plugins for precise navigation capabilities |
| 7 | GOOD | Do refactoring in small, testable increments |
| 8 | GOOD | Use --output-format json or stream-json for scripting integration |
| 9 | GOOD | Toggle verbose mode with Ctrl+O to view extended thinking process |
| 10 | GOOD | Use Git worktrees to run parallel Claude Code sessions |
| 11 | GOOD | Provide reproduction steps and commands when reporting bugs |
| 12 | BAD | Don't rely on phrases like "think hard" to enable extended thinking |
| 13 | GOOD | Use --continue for most recent conversation, --resume with name for known sessions |
| 14 | GOOD | Limit subagent tool access to only what each agent needs |
| 15 | GOOD | Start with broad questions when exploring, then narrow down progressively |

---

## 4. Keywords and Triggers

### Primary Keywords
workflows, subagents, plan mode, session management, extended thinking, file references, git worktrees, output format, permissions, refactoring, debugging, testing, documentation, pull requests, MCP resources, image analysis

### Suggested Triggers
workflow, subagent, plan mode, session, thinking, @ reference, worktree, output-format, refactor, debug, test, pull request, image, documentation

---

## Cross-References

- Subagent documentation
- Plan Mode configuration
- Extended thinking settings
- Session management commands
- Git worktree workflows
