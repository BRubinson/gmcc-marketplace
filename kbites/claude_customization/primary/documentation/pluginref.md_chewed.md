# Chewed: pluginref.md

**Source**: primary/documentation/pluginref.md
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| pluginref.md.md | md | Complete technical reference for Claude Code plugin system - schemas, CLI commands, components, hooks, MCP, LSP, debugging |

---

## 2. Key Learnings Summary

1. **Plugin Component Architecture**: Six component types: skills, agents, hooks, MCP servers, LSP servers, and output styles.

2. **Installation Scopes**: Four scopes (user, project, local, managed) determine availability and sharing.

3. **Hook System**: 12+ events with three action types (command, prompt, agent) for automation.

4. **Plugin Caching**: Files copied to cache directory; cannot reference files outside plugin root.

5. **Path Resolution**: ${CLAUDE_PLUGIN_ROOT} variable required for all internal paths.

---

## 3. Technical Details

### Plugin Components
- **skills/**: Custom commands and shortcuts
- **agents/**: Specialized subagents
- **hooks/**: Event handlers
- **MCP servers**: External tool integration
- **LSP servers**: Code intelligence

### Directory Structure
```
my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Only manifest here
├── skills/              # At root, not inside .claude-plugin/
├── agents/
├── hooks/
└── commands/
```

### Installation Scopes
| Scope | File | Shared |
|-------|------|--------|
| user | ~/.claude/settings.json | No |
| project | .claude/settings.json | Yes (git) |
| local | .claude/settings.local.json | No |
| managed | managed-settings.json | Read-only |

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use ${CLAUDE_PLUGIN_ROOT} for all paths in hooks, MCP servers, scripts |
| 2 | BAD | Don't place component dirs inside .claude-plugin/ - only plugin.json belongs there |
| 3 | GOOD | Use symlinks to include external dependencies |
| 4 | BAD | Avoid absolute paths - all paths must be relative with ./ |
| 5 | GOOD | Install at project scope (--scope project) for team sharing |
| 6 | GOOD | Make hook scripts executable with chmod +x |
| 7 | BAD | Don't attempt path traversal (../) - files won't be copied to cache |
| 8 | GOOD | Use hook matchers to filter events |
| 9 | GOOD | Follow semantic versioning |
| 10 | BAD | Don't assume LSP plugin includes binaries - users install separately |

---

## 4. Keywords and Triggers

### Primary Keywords
plugin, manifest, hooks, MCP, LSP, skills, agents, commands, installation, scopes, caching, debugging, plugin.json, CLAUDE_PLUGIN_ROOT, settings.json

### Suggested Triggers
plugin, hook, scope, MCP server, LSP server, plugin.json, CLAUDE_PLUGIN_ROOT, subagent, marketplace, caching, PostToolUse, skills directory, --scope, symlink, semantic versioning

---

## Cross-References

- Hooks documentation
- MCP server configuration
- Skills documentation
- Settings documentation
