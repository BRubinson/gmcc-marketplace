# Chewed: progusage

**Source**: primary/documentation/progusage
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| progusage | md | Documentation on running Claude Code programmatically via CLI (-p flag), Agent SDK, and CI/CD integration |

---

## 2. Key Learnings Summary

1. **Programmatic CLI Access**: `-p` flag enables non-interactive execution for automation, scripting, and CI/CD.

2. **Agent SDK Architecture**: Same SDK powers CLI and programmatic access (Python/TypeScript) with consistent tools and context.

3. **Tool Auto-Approval**: `--allowedTools` with permission rule syntax enables fine-grained control for automated workflows.

---

## 3. Technical Details

### CLI Invocation
```bash
claude -p "prompt text" [--allowedTools "Tool1,Tool2"] [--output-format json]
```

### Output Formats
- `text`: Plain text (default)
- `json`: Structured JSON with result, session_id, metadata
- `stream-json`: Real-time newline-delimited JSON

### JSON Schema Output
```bash
claude -p "prompt" --output-format json --json-schema '{"type":"object",...}'
```

### Permission Rule Syntax
- Exact match: `"Bash(git status)"`
- Prefix match: `"Bash(git diff:*)"` - allows any command starting with "git diff"
- Multiple tools: `"Bash,Read,Edit"`

### Session Management
```bash
# Continue most recent
claude -p "prompt" --continue

# Resume specific session
session_id=$(claude -p "prompt" --output-format json | jq -r '.session_id')
claude -p "follow-up" --resume "$session_id"
```

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use `-p` flag for non-interactive programmatic execution |
| 2 | GOOD | Specify `--allowedTools` to auto-approve specific tools |
| 3 | GOOD | Use `--output-format json` with `--json-schema` for structured output |
| 4 | GOOD | Capture session IDs from JSON output for multi-conversation scenarios |
| 5 | BAD | Don't expect skills or built-in commands in -p mode - describe task directly |
| 6 | GOOD | Use `--append-system-prompt` to add custom instructions |
| 7 | GOOD | Use `:*` suffix for prefix matching |
| 8 | GOOD | Pipe jq to extract fields from JSON output |

---

## 4. Keywords and Triggers

### Primary Keywords
programmatic, CLI, -p flag, Agent SDK, headless, non-interactive, automation, CI/CD, allowedTools, output-format, json-schema, structured output, session continuation

### Suggested Triggers
programmatic, headless, automation, allowedTools, output-format, json-schema, continue conversation, CI/CD, append-system-prompt, permission rules

---

## Cross-References

- CLI reference
- Agent SDK documentation
- Settings documentation (permissions)
