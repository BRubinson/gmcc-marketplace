# Chewed: interactivemode

**Source**: primary/documentation/interactivemode
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| interactivemode.md | md | Complete reference for keyboard shortcuts, input modes, built-in commands, vim mode, background tasks, task lists |

---

## 2. Key Learnings Summary

1. **Platform Configuration is Critical**: macOS users must configure Option as Meta key for Alt-based shortcuts, some terminals require `/terminal-setup` for Shift+Enter.

2. **Background Task Execution**: Ctrl+B backgrounds long-running commands (twice for tmux), enabling continued interaction with task ID tracking.

3. **Three Input Modes**: Standard prompts, slash commands (`/`), and bash mode (`!` prefix).

4. **Vim Mode Integration**: Full vim-style editing with NORMAL/INSERT modes via `/vim`.

5. **Session Management Commands**: `/resume`, `/rewind`, `/compact`, `/export`.

---

## 3. Technical Details

### Quick Command Prefixes
- `/` - Built-in commands or skills
- `!` - Direct bash execution
- `@` - File path autocomplete

### Background Tasks
- Ctrl+B to background (twice for tmux)
- Unique task IDs for output retrieval
- Disable via `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`

### Key Commands
| Command | Purpose |
|---------|---------|
| `/clear` | Clear conversation |
| `/compact` | Compact context |
| `/config` | Open settings |
| `/mcp` | Manage MCP servers |
| `/memory` | Edit CLAUDE.md files |
| `/model` | Change AI model |
| `/permissions` | View/update permissions |
| `/resume` | Resume session |
| `/rewind` | Rewind conversation/code |

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Configure Option as Meta key on macOS for Alt shortcuts |
| 2 | GOOD | Use Ctrl+B to background long-running commands |
| 3 | GOOD | Use `!` prefix for direct bash execution |
| 4 | GOOD | Press Esc+Esc to rewind conversation and code |
| 5 | BAD | Remember to press Ctrl+B twice with tmux |
| 6 | GOOD | Use `/terminal-setup` for Shift+Enter in VS Code, Alacritty, Zed, Warp |
| 7 | GOOD | Use Ctrl+R for reverse search |
| 8 | GOOD | Set CLAUDE_CODE_TASK_LIST_ID to share task lists across sessions |

---

## 4. Keywords and Triggers

### Primary Keywords
keyboard shortcuts, interactive mode, built-in commands, vim mode, background tasks, bash mode, command history, reverse search, multiline input, task list, session management, MCP prompts

### Suggested Triggers
keyboard shortcuts, interactive mode, background tasks, bash mode, vim mode, command history, multiline input, rewind, Option as Meta, tmux, /commands, MCP, task list, terminal setup

---

## Cross-References

- Terminal Configuration
- Skills documentation
- Checkpointing
- CLI Reference
- Settings
- Memory Management
