# Chewed: OutputStyles

**Source**: primary/documentation/OutputStyles
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| OutputStyles.md | md | Documentation of Claude Code's output style system including built-in styles, custom style creation, and configuration |

---

## 2. Key Learnings Summary

1. **System Prompt Modification**: Output styles directly edit Claude Code's system prompt rather than appending to it.

2. **Built-in Styles**: Three pre-configured styles - Default (software engineering), Explanatory (educational insights), Learning (collaborative coding with TODO markers).

3. **Custom Style Creation**: Markdown files with frontmatter in `~/.claude/output-styles` or `.claude/output-styles`.

---

## 3. Technical Details

### Built-in Output Styles
- **Default**: Standard software engineering system prompt
- **Explanatory**: Adds educational "Insights" sections during coding
- **Learning**: Collaborative mode with TODO(human) markers for user contribution

### Custom Style File Format
```markdown
---
name: My Custom Style
description: Brief description for UI
keep-coding-instructions: false
---

# Custom Style Instructions
[Your custom instructions here...]
```

### Configuration
- `/output-style` - Interactive menu selection
- `/output-style [style]` - Direct switch
- Stored in `.claude/settings.local.json`

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use output styles to repurpose Claude Code for non-engineering tasks |
| 2 | GOOD | Set `keep-coding-instructions: true` when custom styles need software engineering capabilities |
| 3 | GOOD | Store user-level custom styles in `~/.claude/output-styles` |
| 4 | GOOD | Use Explanatory style when onboarding to a codebase |
| 5 | GOOD | Use Learning style with TODO(human) markers to practice coding |
| 6 | BAD | Don't confuse output styles with CLAUDE.md - CLAUDE.md doesn't modify system prompt |
| 7 | BAD | Don't use output styles for task-specific workflows - use Skills instead |

---

## 4. Keywords and Triggers

### Primary Keywords
output-style, system-prompt, customization, explanatory, learning, frontmatter, keep-coding-instructions, CLAUDE.md, sub-agents, skills

### Suggested Triggers
output-style, system prompt customization, explanatory mode, learning mode, repurpose claude code, custom agent behavior, CLAUDE.md vs output-style, keep-coding-instructions, TODO(human), style frontmatter

---

## Cross-References

- CLAUDE.md documentation
- Skills documentation
- Sub-agents documentation
