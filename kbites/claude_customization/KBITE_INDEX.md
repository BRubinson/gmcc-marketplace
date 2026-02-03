# KBite Index: claude_customization

**Purpose**: See [KBITE_PURPOSE.md](./KBITE_PURPOSE.md)
**Last Updated**: 2026-02-02T22:30:00Z
**Total Resources**: 18

## Resource Index

| Resource | Axis | Path | Keywords | Relevance | Confidence | Unique Keywords |
|----------|------|------|----------|-----------|------------|-----------------|
| pluginref.md | primary/documentation | primary/documentation/pluginref.md | plugin, manifest, hooks, MCP, LSP, skills, agents | 100 | 95 | plugin, CLAUDE_PLUGIN_ROOT, marketplace |
| extendclaudewithskills | primary/documentation | primary/documentation/extendclaudewithskills | skills, SKILL.md, slash commands, frontmatter, context fork | 98 | 95 | SKILL.md, disable-model-invocation, context: fork |
| hooks | primary/documentation | primary/documentation/hooks | hooks, shell commands, lifecycle events, PreToolUse, PostToolUse | 97 | 95 | PreToolUse, PostToolUse, exit code 2 |
| hooksref | primary/documentation | primary/documentation/hooksref | hooks, lifecycle, events, permissionDecision, CLAUDE_ENV_FILE | 96 | 95 | permissionDecision, CLAUDE_ENV_FILE, additionalContext |
| CreateSubagents | primary/documentation | primary/documentation/CreateSubagents | subagent, delegation, context isolation, tool restrictions, permission modes | 95 | 95 | subagent, delegation, context isolation |
| settings | primary/documentation | primary/documentation/settings | settings.json, scopes, permissions, sandbox, MCP, plugins, hooks | 94 | 95 | configuration scopes, sandbox, strictKnownMarketplaces |
| interactivemode | primary/documentation | primary/documentation/interactivemode | keyboard shortcuts, built-in commands, vim mode, background tasks, bash mode | 93 | 95 | background tasks, Ctrl+B, vim mode |
| memorymanagement | primary/documentation | primary/documentation/memorymanagement | CLAUDE.md, memory hierarchy, import syntax, modular rules, path-specific rules | 92 | 95 | .claude/rules, path-specific rules, @import |
| modelconfig | primary/documentation | primary/documentation/modelconfig | model aliases, opusplan, sonnet, opus, haiku, prompt caching | 91 | 95 | opusplan, model aliases, ANTHROPIC_DEFAULT |
| cliref | primary/documentation | primary/documentation/cliref | CLI, flags, REPL, system prompt, subagents, permissions, output formats | 90 | 95 | --append-system-prompt, --output-format, --allowedTools |
| OutputStyles | primary/documentation | primary/documentation/OutputStyles | output-style, system-prompt, explanatory, learning, frontmatter | 89 | 95 | output-style, keep-coding-instructions, TODO(human) |
| commonWorkflows | primary/documentation | primary/documentation/commonWorkflows | workflows, subagents, plan mode, session management, extended thinking, git worktrees | 88 | 95 | extended thinking, git worktrees, @ reference |
| bestpractices | primary/documentation | primary/documentation/bestpractices | context window, verification, CLAUDE.md, skills, hooks, subagents, Plan Mode | 87 | 95 | verification, course-correct, context management |
| progusage | primary/documentation | primary/documentation/progusage | programmatic, CLI, -p flag, Agent SDK, automation, CI/CD, json-schema | 86 | 95 | -p flag, headless, json-schema |
| statusline | primary/documentation | primary/documentation/statusline | statusline, custom prompt, stdin JSON, context window, ANSI colors | 85 | 95 | statusline, stdin JSON, context_window |
| checkpointing | primary/documentation | primary/documentation/checkpointing | checkpointing, rewind, undo, session recovery, Esc+Esc | 84 | 95 | checkpoint, rewind, Esc+Esc |
| terminal | primary/documentation | primary/documentation/terminal | terminal, notifications, vim mode, line breaks, Shift+Enter | 83 | 95 | /terminal-setup, vim mode, line breaks |
| HOWYOUWORK | primary/documentation | primary/documentation/HOWYOUWORK | agentic loop, context window, checkpoints, permissions, sessions, tools | 82 | 95 | agentic loop, fork session |

## Keyword Cross-Reference

| Keyword | Resources | Best Resource |
|---------|-----------|---------------|
| skills | extendclaudewithskills, pluginref.md, bestpractices, commonWorkflows | extendclaudewithskills (98) |
| hooks | hooks, hooksref, pluginref.md, settings, bestpractices | hooks (97) |
| plugin | pluginref.md, settings | pluginref.md (100) |
| subagent | CreateSubagents, commonWorkflows, bestpractices, cliref | CreateSubagents (95) |
| CLAUDE.md | memorymanagement, bestpractices, commonWorkflows | memorymanagement (92) |
| settings | settings, cliref, bestpractices | settings (94) |
| MCP | pluginref.md, settings | pluginref.md (100) |
| permissions | settings, cliref, hooksref, HOWYOUWORK | settings (94) |
| checkpointing | checkpointing, HOWYOUWORK, bestpractices | checkpointing (84) |
| plan mode | commonWorkflows, bestpractices, HOWYOUWORK | commonWorkflows (88) |
| lifecycle | hooks, hooksref | hooks (97) |
| model | modelconfig, cliref | modelconfig (91) |
| CLI | cliref, progusage | cliref (90) |
| output | OutputStyles, cliref, statusline | OutputStyles (89) |
| vim | interactivemode, terminal | interactivemode (93) |
| keyboard | interactivemode | interactivemode (93) |
| automation | progusage, hooks | progusage (86) |
| context window | bestpractices, HOWYOUWORK, memorymanagement, statusline | bestpractices (87) |

## Quick Reference Mappings

| Task | Best Resource | Alternative |
|------|---------------|-------------|
| Add a slash command | extendclaudewithskills | pluginref.md |
| Create a plugin | pluginref.md | settings |
| Configure keyboard shortcuts | interactivemode | settings |
| Add lifecycle hooks | hooks | hooksref |
| Configure MCP servers | pluginref.md | settings |
| Create subagents | CreateSubagents | commonWorkflows |
| Change model settings | modelconfig | settings |
| Customize output format | OutputStyles | cliref |
| Use CLI programmatically | progusage | cliref |
| Manage memory/context | memorymanagement | bestpractices |
