# Chewed: cliref

**Source**: primary/documentation/cliref
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| cliref | md | Comprehensive CLI reference documentation covering all commands, flags, and usage patterns for Claude Code |

---

## 2. Key Learnings Summary

1. **Command Modes**: Interactive REPL (`claude`), SDK print mode (`-p`), and session resumption (`-c`, `-r`)

2. **Customization Layers**: System prompts (replace or append), agents, tools, permissions, and settings

3. **Integration Points**: MCP server configuration, Chrome browser integration, IDE connectivity, structured output formats

---

## 3. Technical Details

### System Prompt Customization (4 flags)
1. `--system-prompt`: **Replaces** entire default prompt
2. `--system-prompt-file`: **Replaces** with file contents
3. `--append-system-prompt`: **Appends** to default prompt - RECOMMENDED
4. `--append-system-prompt-file`: **Appends** file contents

### Subagent Definition Format
```json
{
  "agent-name": {
    "description": "When to invoke (required)",
    "prompt": "System prompt for agent (required)",
    "tools": ["Read", "Edit", "Bash"],
    "model": "sonnet|opus|haiku|inherit"
  }
}
```

### Permission Management
- `--permission-mode plan` - begins in specified mode
- `--allowedTools` - tools that execute without prompting
- `--disallowedTools` - removes tools from context
- `--tools "Bash,Edit,Read"` - restricts available tools
- `--dangerously-skip-permissions` - skips all prompts

### Output Formats
- Text: Default human-readable
- JSON: `--output-format json`
- Stream-JSON: `--output-format stream-json`

### Budget Controls
- `--max-turns 3` - limits agentic turns
- `--max-budget-usd 5.00` - caps API spending
- `--fallback-model sonnet` - auto-switches on overload

---

## 4. Keywords and Triggers

### Primary Keywords
CLI, command-line, flags, REPL, print mode, SDK, system prompt, subagents, agents, permissions, tools, MCP, session management, settings, output formats, JSON, budget controls, Chrome integration, IDE, plugins, debug

### Suggested Triggers
CLI reference, command flags, system prompt, --append-system-prompt, --permission-mode, --output-format, subagent definition, --allowedTools, --max-turns, --max-budget-usd, session resumption, MCP configuration

---

## Cross-References

- /en/settings - Configuration options
- /en/sub-agents - Detailed subagent documentation
- /en/hooks#setup - Setup and maintenance hooks
- /en/mcp - Model Context Protocol configuration
- /en/common-workflows - Advanced workflow patterns
