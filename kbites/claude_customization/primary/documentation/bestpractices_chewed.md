# Chewed: bestpractices

**Source**: primary/documentation/bestpractices
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| bestpractices | text/html | Official Claude Code best practices documentation covering verification, planning, prompting, environment configuration, communication, session management, automation, and common failure patterns |

---

## 2. Key Learnings Summary

1. **Context Window Management**: Claude's context window is the most critical resource to manage. Performance degrades as context fills with conversation history, file reads, and command outputs. Use /clear between unrelated tasks, delegate to subagents for research, and leverage auto-compaction features.

2. **Verification-Driven Development**: Provide Claude with concrete ways to verify its own work (tests, screenshots, expected outputs). This is described as "the single highest-leverage thing you can do" and dramatically improves output quality.

3. **Environment Configuration Hierarchy**: CLAUDE.md provides persistent project context, skills offer on-demand domain knowledge, hooks enforce deterministic actions, subagents handle isolated research, and MCP servers connect external tools. Each serves a distinct purpose in the customization ecosystem.

---

## 3. Detailed Analysis

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Always provide concrete verification criteria (tests, screenshots, expected outputs) so Claude can validate its own work |
| 2 | GOOD | Keep CLAUDE.md concise - only include things Claude can't infer from code |
| 3 | BAD | Avoid letting Claude explore without scope - unscoped investigations read hundreds of files and fill context |
| 4 | GOOD | Use subagents for research tasks to keep investigation in separate context |
| 5 | BAD | Don't correct Claude more than twice on the same issue - run /clear and start fresh |
| 6 | GOOD | Use hooks for actions that must happen every time with zero exceptions |
| 7 | GOOD | Separate exploration from implementation using Plan Mode |
| 8 | BAD | Avoid over-specified CLAUDE.md files - bloated files cause Claude to ignore actual instructions |
| 9 | GOOD | Use /clear between unrelated tasks to reset context and maintain performance |
| 10 | GOOD | Create skills in .claude/skills/ for domain knowledge and reusable workflows |
| 11 | GOOD | Use @ syntax to reference files, paste images directly |
| 12 | BAD | Don't use --dangerously-skip-permissions without sandboxing |
| 13 | GOOD | Provide specific context in prompts: reference files, mention constraints |
| 14 | GOOD | Use Writer/Reviewer pattern with multiple sessions for better code review |
| 15 | GOOD | Install relevant CLI tools (gh, aws, gcloud) for context-efficient external service interaction |

---

## 4. Keywords and Triggers

### Primary Keywords
context window, verification, CLAUDE.md, skills, hooks, subagents, Plan Mode, permissions, checkpoints, rewind, MCP servers, headless mode, auto-compaction, fan-out, sandbox

### Suggested Triggers
best practices, context management, CLAUDE.md, verification, skills, hooks, subagents, Plan Mode, performance degradation, course-correct, /clear, /rewind, auto-compaction, headless, multiple sessions, failure patterns, verification criteria, permission allowlists, MCP, plugins

---

## Cross-References

- CLAUDE.md reference documentation
- Skills creation guide
- Hooks configuration
- Subagent definition
- MCP server setup
- Plugin marketplace
