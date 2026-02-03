# Chewed: memorymanagement

**Source**: primary/documentation/memorymanagement
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| memorymanagement.md | md | Complete documentation of Claude Code's memory management system - hierarchy, locations, imports, modular rules |

---

## 2. Key Learnings Summary

1. **Hierarchical Memory Architecture**: Five-tier system (Managed → Project → Rules → User → Local) where higher levels provide foundation and lower levels override/specialize.

2. **Import-Driven Composition**: Memory files compose via `@path` syntax with recursive support up to 5 hops.

3. **Conditional Rule Application**: `.claude/rules/` with YAML frontmatter `paths` field enables context-aware rule activation.

4. **Discovery Over Configuration**: Automatic discovery from cwd to root, loading subtree memories on-demand.

5. **Version Control Integration**: CLAUDE.local.md auto-gitignored while other types are version-controlled.

---

## 3. Technical Details

### Memory Hierarchy
| Type | Location | Scope |
|------|----------|-------|
| Managed policy | /Library/Application Support/ClaudeCode/CLAUDE.md | Organization |
| Project memory | ./CLAUDE.md or ./.claude/CLAUDE.md | Project team |
| Project rules | ./.claude/rules/*.md | Project team |
| User memory | ~/.claude/CLAUDE.md | All user projects |
| Project local | ./CLAUDE.local.md | Single user |

### Import Syntax
```markdown
@README                           # Relative import
@docs/git-instructions.md         # Relative path
@~/.claude/my-instructions.md     # Home directory
```

### Path-Specific Rules
```yaml
---
paths:
  - "src/api/**/*.ts"
  - "tests/**/*.test.ts"
---
# Rules only apply to matching files
```

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use hierarchical memory to separate concerns across scopes |
| 2 | GOOD | Leverage @import syntax to compose modular memory files |
| 3 | GOOD | Organize large projects using .claude/rules/ directory |
| 4 | GOOD | Apply path-specific rules using YAML frontmatter |
| 5 | GOOD | Use symlinks to share rules across projects |
| 6 | GOOD | Place frequently used commands in CLAUDE.md |
| 7 | GOOD | Use CLAUDE.local.md for private preferences |
| 8 | GOOD | Bootstrap with /init, edit with /memory |
| 9 | GOOD | Be specific in instructions |
| 10 | BAD | Don't create circular symlinks |
| 11 | BAD | Avoid vague or generic instructions |

---

## 4. Keywords and Triggers

### Primary Keywords
CLAUDE.md, memory management, hierarchical memory, project memory, user memory, managed policy, import syntax, modular rules, path-specific rules, .claude/rules, YAML frontmatter, glob patterns, /memory command, /init command, CLAUDE.local.md

### Suggested Triggers
memory, CLAUDE.md, project memory, user memory, import, .claude/rules, paths, hierarchical, managed policy, /init, /memory, glob patterns, symlink, CLAUDE.local.md

---

## Cross-References

- Settings documentation
- Project setup guides
- Team collaboration
- Enterprise deployment
