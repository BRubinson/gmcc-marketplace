# Chewed: extendclaudewithskills

**Source**: primary/documentation/extendclaudewithskills
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| extendclaudewithskills.md | md | Complete documentation on Claude Code skills system - creating, managing, and sharing skills |

---

## 2. Key Learnings Summary

1. **Skills extend Claude's capabilities through SKILL.md files**: Create a SKILL.md file with YAML frontmatter and markdown instructions, invoked via `/skill-name` or loaded automatically.

2. **Skills support multiple scopes and inheritance**: Enterprise > personal (`~/.claude/skills/`) > project (`.claude/skills/`) > plugin locations.

3. **Frontmatter controls invocation, execution, and permissions**: `disable-model-invocation`, `user-invocable`, `context: fork`, `allowed-tools`.

4. **Dynamic context injection with preprocessing**: The `!`command`` syntax runs shell commands before skill content reaches Claude.

5. **Skills follow the Agent Skills open standard**: Implements agentskills.io standard with Claude Code extensions.

---

## 3. Technical Details

### Frontmatter Options
```yaml
name: skill-name
description: When to use this skill
argument-hint: optional argument placeholder text
disable-model-invocation: true  # Manual only
user-invocable: false           # Hide from menu
allowed-tools: [Read, Grep]     # Tool restrictions
model: haiku|sonnet|opus
context: fork                   # Run in subagent
agent: Explore|Plan|custom      # Which subagent
hooks:
  PreToolUse: [...]
```

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Always include a description in frontmatter for relevance matching |
| 2 | GOOD | Use `disable-model-invocation: true` for skills with side effects |
| 3 | GOOD | Keep SKILL.md under 500 lines, use supporting files |
| 4 | BAD | Don't use `context: fork` for reference-only skills |
| 5 | GOOD | Use `!`command`` for dynamic context injection |
| 6 | GOOD | Place skills in appropriate scopes for sharing |
| 7 | GOOD | Use `allowed-tools` for constrained execution |
| 8 | BAD | Don't rely on `user-invocable: false` to prevent programmatic invocation |
| 9 | GOOD | Reference supporting files with descriptions |
| 10 | GOOD | Use `$ARGUMENTS` placeholder for dynamic arguments |

---

## 4. Keywords and Triggers

### Primary Keywords
skills, SKILL.md, slash commands, frontmatter, customization, subagent, context fork, dynamic context injection, allowed-tools, disable-model-invocation, user-invocable, Agent Skills standard

### Suggested Triggers
skill, slash command, SKILL.md, frontmatter, disable-model-invocation, user-invocable, context: fork, allowed-tools, dynamic context, $ARGUMENTS, Agent Skills, skill scopes, supporting files

---

## Cross-References

- Subagent documentation (context: fork)
- Hooks reference (skill hooks)
- Plugin documentation (skill distribution)
