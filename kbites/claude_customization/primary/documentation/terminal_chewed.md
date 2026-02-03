# Chewed: terminal

**Source**: primary/documentation/terminal
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| terminal | markdown | Complete guide for optimizing terminal setup - themes, line breaks, notifications, input handling, Vim mode |

---

## 2. Key Learnings Summary

1. **Terminal Configuration Independence**: Claude Code cannot control terminal themes - use `/config` for theme matching, terminal app for appearance.

2. **Line Break Entry Methods**: Quick escape (`\` + Enter), native Shift+Enter (iTerm2, WezTerm, Ghostty, Kitty), or `/terminal-setup` for others.

3. **File-Based Input Over Pasting**: Large content should be written to files - VS Code terminal particularly prone to truncating.

4. **Notification Customization**: Configure via terminal settings (iTerm2) or custom notification hooks.

5. **Vim Mode Subset**: Enable via `/vim` or `/config` for navigation, editing, yank/paste, text objects.

---

## 3. Technical Details

### Line Break Configuration
- **Universal**: `\` + Enter (quick escape)
- **Native support**: iTerm2, WezTerm, Ghostty, Kitty
- **Automated setup**: VS Code, Alacritty, Zed, Warp (via `/terminal-setup`)
- **Manual Option+Enter**: Enable "Use Option as Meta Key"

### iTerm2 Notification Setup
1. Preferences → Profiles → Terminal
2. Enable "Silence bell"
3. Enable "Send escape sequence-generated alerts"

### Vim Mode Operations
- **Modes**: NORMAL (Esc), INSERT (i, I, a, A, o, O)
- **Navigation**: h/j/k/l, w/e/b, 0/$^, gg/G, f/F/t/T
- **Editing**: x, dw/de/db/dd/D, cw/ce/cb/cc/C
- **Yank/Paste**: yy/Y, yw/ye/yb, p/P
- **Text Objects**: iw/aw, i"/a", i'/a', i(/a(, i[/a[, i{/a{

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use `/config` to match Claude Code's theme to your terminal |
| 2 | GOOD | Configure custom status line for contextual info |
| 3 | GOOD | Use `/terminal-setup` for VS Code, Alacritty, Zed, Warp |
| 4 | BAD | Avoid pasting very long content directly - especially in VS Code |
| 5 | GOOD | Write large content to files and ask Claude to read it |
| 6 | GOOD | Enable iTerm2 notifications for task completion alerts |
| 7 | GOOD | Use quick escape (`\` + Enter) as universal line break method |
| 8 | GOOD | Enable Vim mode via `/vim` for Vim keybindings |
| 9 | BAD | Don't expect `/terminal-setup` in terminals with native Shift+Enter |

---

## 4. Keywords and Triggers

### Primary Keywords
terminal, configuration, setup, notifications, vim, line breaks, themes, statusline, hooks, pasting, keyboard shortcuts, iTerm2, VS Code, Shift+Enter, /config, /terminal-setup, /vim

### Suggested Triggers
terminal setup, line break, Shift+Enter, pasting large, vim mode, notifications, terminal theme, status line, VS Code terminal, iTerm2, Option+Enter, /terminal-setup, truncating

---

## Cross-References

- Status line documentation
- Hooks documentation
- Interactive mode documentation
- Settings documentation
