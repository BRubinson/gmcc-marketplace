# Chewed: settings

**Source**: primary/documentation/settings
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| settings | md | Comprehensive documentation of Claude Code configuration system - files, scopes, permissions, environment variables, plugins, subagents, MCP, hooks, sandboxing |

---

## 2. Key Learnings Summary

1. **Configuration Scopes**: Four-tier hierarchy (Managed > Command-line > Local > Project > User) determines where settings apply.

2. **Permission System**: Allow/Ask/Deny rules with pattern matching for fine-grained tool access control.

3. **Security Features**: Sandboxing for bash commands, managed restrictions for enterprise control, hook execution limits.

---

## 3. Technical Details

### Configuration Scopes
| Scope | Location | Shared | Precedence |
|-------|----------|--------|------------|
| Managed | System-level managed-settings.json | IT deployed | Highest |
| User | ~/.claude/ | No | Lowest |
| Project | .claude/settings.json | Yes (git) | Medium |
| Local | .claude/settings.local.json | No (gitignored) | High |

### Permission Rule Syntax
- Deny rules evaluated first (highest priority)
- Allow rules evaluated last (lowest priority)
- `:*` suffix: Prefix matching with word boundary
- `*` anywhere: Glob matching without word boundary

### Tool-specific Specifiers
- Bash: Command patterns (`Bash(git commit:*)`)
- Read/Edit/Write: File paths with globs (`Read(./.env)`)
- WebFetch: Domain patterns (`WebFetch(domain:example.com)`)
- MCP: Server and tool names (`MCP(server:github, tool:create_pull_request)`)
- Task: Subagent names (`Task(agent:code-reviewer)`)

### Sandbox Configuration
```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "excludedCommands": ["docker", "git"],
    "network": {
      "allowLocalBinding": true
    }
  }
}
```

### Environment Variable Persistence
Environment variables do NOT persist between Bash commands.
Solutions:
1. Pre-activate environment before starting Claude
2. Set `CLAUDE_ENV_FILE` to shell script path
3. Use SessionStart hook to write to `$CLAUDE_ENV_FILE`

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use Managed scope for organization-wide security policies |
| 2 | GOOD | Use Project scope for team-shared configurations |
| 3 | GOOD | Use Local scope for personal overrides and testing |
| 4 | GOOD | Place deny rules before allow rules in permission arrays |
| 5 | BAD | Don't rely on Bash permission patterns as security boundaries - they're fragile |
| 6 | GOOD | Use permissions.deny to exclude sensitive files |
| 7 | GOOD | Store team subagents in .claude/agents/ |
| 8 | GOOD | Set strictKnownMarketplaces for enterprise plugin control |
| 9 | BAD | Don't use URL marketplaces for plugins with relative paths |
| 10 | GOOD | Use CLAUDE_ENV_FILE or SessionStart hooks for environment persistence |
| 11 | GOOD | Enable sandboxing with autoAllowBashIfSandboxed |
| 12 | GOOD | Use :* suffix for prefix matching with word boundary |

---

## 4. Keywords and Triggers

### Primary Keywords
settings.json, configuration scopes, permissions, managed settings, sandbox, MCP servers, plugins, subagents, hooks, environment variables, allow deny ask, marketplace restrictions, tool permissions

### Suggested Triggers
configure, permission, settings, scope, managed, sandbox, plugin, hook, environment, marketplace, subagent, MCP, attribution, deny, allow, CLAUDE_ENV_FILE, strictKnownMarketplaces, allowManagedHooksOnly

---

## Cross-References

- Hooks documentation
- Plugin reference
- MCP configuration
- Subagent documentation
- Memory management
