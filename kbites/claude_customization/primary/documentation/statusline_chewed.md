# Chewed: statusline

**Source**: primary/documentation/statusline
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| statusline | md | Complete documentation for Claude Code's custom status line feature - configuration, JSON input structure, multi-language examples |

---

## 2. Key Learnings Summary

1. **Custom Status Line Configuration**: Configure via `.claude/settings.json` with executable scripts that receive session context as JSON via stdin and output formatted text (with ANSI colors) to stdout.

2. **Rich Contextual Data**: Scripts receive comprehensive session info: model details, workspace paths, cost metrics (USD, duration, lines changed), and context window usage.

3. **Hook-Based Update Mechanism**: Status lines update on conversation message changes with 300ms throttle.

---

## 3. Technical Details

### Configuration
```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/statusline.sh",
    "padding": 2
  }
}
```

### JSON Input Fields
- `hook_event_name`: Event type
- `session_id`: Current session identifier
- `model.display_name`: Model being used
- `workspace.root`: Working directory
- `cost.usd`, `cost.duration_ms`, `cost.lines_changed`: Cost metrics
- `context_window.total_tokens`, `context_window.used_percentage`: Token usage

### Example Bash Script
```bash
#!/bin/bash
read -r JSON
model=$(echo "$JSON" | jq -r '.model.display_name')
dir=$(basename "$(echo "$JSON" | jq -r '.workspace.root')")
echo "[$model] $dir"
```

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Configure status line in `.claude/settings.json` with `statusLine.type: "command"` |
| 2 | GOOD | Read JSON context from stdin using jq (bash), json.load() (Python), or JSON.parse() (Node.js) |
| 3 | GOOD | Use pre-calculated `used_percentage` from context_window for simple token display |
| 4 | GOOD | Output only to stdout (first line becomes status text), keep concise |
| 5 | BAD | Avoid expensive operations without caching - scripts run every 300ms |
| 6 | GOOD | Test scripts manually with mock JSON before deployment |
| 7 | GOOD | Make script executable with `chmod +x` |
| 8 | BAD | Avoid outputting to stderr - only stdout is captured |

---

## 4. Keywords and Triggers

### Primary Keywords
statusline, status line, custom prompt, PS1, settings.json, hook, stdin JSON, context window, ANSI colors, session context, executable script, jq, model display, workspace, cost metrics, token usage

### Suggested Triggers
statusline, status line, custom prompt, PS1, bottom display, session context, context window display, cost display, git branch display, ANSI colors, hook event

---

## Cross-References

- Settings documentation
- Hooks documentation
- Interactive mode documentation
