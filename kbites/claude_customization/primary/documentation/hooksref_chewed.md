# Chewed: hooksref

**Source**: primary/documentation/hooksref
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| hooksref.md | md | Complete reference for Claude Code hooks - lifecycle, configuration, events, schemas |

---

## 2. Key Learnings Summary

1. **Hook Lifecycle and Events**: 12 hook events (SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop, Stop, PreCompact, SessionEnd, Notification).

2. **Configuration Hierarchy**: User settings, project settings, local settings, managed policies, plugins, skills, subagents.

3. **Two Hook Types**: Command hooks (bash scripts) and prompt-based hooks (LLM evaluation for context-aware decisions).

---

## 3. Technical Details

### Decision Control (PreToolUse)
```json
{
  "permissionDecision": "allow|deny|ask",
  "updatedInput": { "modified": "params" },
  "additionalContext": "Info for Claude"
}
```

### Environment Persistence
Write to `$CLAUDE_ENV_FILE` in SessionStart hooks to persist variables.

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use PreToolUse with permissionDecision: "allow" to auto-approve trusted operations |
| 2 | GOOD | Persist environment variables via $CLAUDE_ENV_FILE |
| 3 | GOOD | Use matcher patterns with regex efficiently |
| 4 | BAD | Don't use SessionStart for one-time operations - use Setup hooks |
| 5 | GOOD | Use $CLAUDE_PROJECT_DIR for project-relative scripts |
| 6 | GOOD | Use prompt-based hooks for context-aware decisions |
| 7 | BAD | Never trust hook input blindly - validate and sanitize |
| 8 | GOOD | Return exit code 2 to block with feedback |
| 9 | GOOD | Use updatedInput to modify tool parameters |
| 10 | BAD | Don't use exit code 2 if returning structured JSON |
| 11 | GOOD | Define hooks in skill/subagent frontmatter for scoped behavior |
| 12 | GOOD | Use additionalContext to inject info without verbose output |

---

## 4. Keywords and Triggers

### Primary Keywords
hooks, lifecycle, events, PreToolUse, PostToolUse, PermissionRequest, SessionStart, matchers, command hooks, prompt-based hooks, exit codes, JSON output, decision control, CLAUDE_ENV_FILE, MCP tools

### Suggested Triggers
hook, PreToolUse, PostToolUse, PermissionRequest, SessionStart, matcher, permissionDecision, CLAUDE_ENV_FILE, exit code 2, additionalContext, plugin hook, updatedInput, prompt-based hook, MCP tool hook

---

## Cross-References

- Hooks guide (practical examples)
- Settings documentation
- Plugin documentation
- Skills documentation
