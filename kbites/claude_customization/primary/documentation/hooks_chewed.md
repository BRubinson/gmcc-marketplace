# Chewed: hooks

**Source**: primary/documentation/hooks
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| hooks.md | md | Complete guide to Claude Code hooks - shell commands that execute at lifecycle points |

---

## 2. Key Learnings Summary

1. **Hooks provide deterministic control**: Unlike prompting, hooks execute shell commands automatically at specific lifecycle events.

2. **Event-driven architecture**: 11 hook events (PreToolUse, PostToolUse, PermissionRequest, UserPromptSubmit, Notification, Stop, SubagentStop, PreCompact, Setup, SessionStart, SessionEnd).

3. **Security is paramount**: Hooks run with current environment credentials - review all implementations before registration.

4. **Configuration via JSON**: Registered in settings.json with matcher pattern, command type, and shell command.

5. **Practical use cases**: Automatic formatting, compliance logging, notifications, feedback loops, blocking sensitive modifications.

---

## 3. Technical Details

### Hook Configuration
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "type": "command",
      "command": "prettier --write \"$(echo $CLAUDE_TOOL_INPUT | jq -r '.file_path')\""
    }]
  }
}
```

### Exit Codes
- **0**: Success, continue
- **2**: Block tool call, show stderr to Claude
- **Other**: Non-blocking error

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use hooks for actions that must happen deterministically |
| 2 | BAD | Never register hooks without reviewing implementation |
| 3 | GOOD | Use PreToolUse with exit code 2 to block tool calls |
| 4 | GOOD | Use PostToolUse for automatic formatting after edits |
| 5 | GOOD | Store hooks in user settings for global, project for project-specific |
| 6 | GOOD | Use matcher patterns like "Edit\|Write" for multiple tools |
| 7 | GOOD | Process hook input via stdin using jq |
| 8 | GOOD | Make hook scripts executable |
| 9 | BAD | Don't use hooks for LLM-driven decisions |
| 10 | GOOD | Use Notification hooks for desktop alerts |

---

## 4. Keywords and Triggers

### Primary Keywords
hooks, shell commands, lifecycle events, PreToolUse, PostToolUse, PermissionRequest, automatic formatting, security, matcher patterns, settings.json, exit codes, stdin JSON

### Suggested Triggers
hooks, PreToolUse, PostToolUse, automatic formatting, block tool, customize Claude, shell command lifecycle, settings.json, matcher, exit code, stdin JSON, file protection, desktop notification

---

## Cross-References

- Hooks reference (detailed event schemas)
- Settings documentation
- Security best practices
