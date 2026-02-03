# KBite Triggers: claude_customization

When any of these concepts appear in a prompt or project context, GMB should check this kbite.

## Trigger Words

| Trigger | Confidence | Context |
|---------|------------|---------|
| skills | 95 | Creating or using custom skills, SKILL.md files |
| hooks | 95 | Lifecycle event customization, PreToolUse, PostToolUse |
| plugin | 95 | Plugin development, manifest files, installation |
| MCP | 95 | Model Context Protocol servers and integration |
| subagent | 92 | Creating or delegating to subagents, context isolation |
| SKILL.md | 92 | Skill definition file creation or editing |
| settings.json | 92 | Configuration file modification |
| CLAUDE.md | 90 | Project memory configuration, persistent instructions |
| slash command | 90 | Creating custom commands invoked with / |
| customize | 88 | General customization of Claude behavior |
| lifecycle event | 88 | Hook event handling, PreToolUse, PostToolUse |
| CLI | 88 | Command-line interface flags and options |
| plan mode | 88 | Planning workflow activation |
| checkpointing | 88 | Session state management, rewind capability |
| permissions | 88 | Security settings, sandbox configuration |
| model alias | 85 | Model configuration (opusplan, sonnet, opus, haiku) |
| frontmatter | 85 | YAML frontmatter in skills and commands |
| keyboard shortcuts | 85 | Interactive mode keybindings |
| output-style | 85 | Response format customization |
| vim mode | 85 | Vim keybindings in interactive mode |
| statusline | 82 | Custom prompt/statusbar configuration |
| automation | 80 | Programmatic usage, CI/CD integration |

## Anti-Triggers

Words that might seem related but should NOT activate this kbite:

| Word | Reason |
|------|--------|
| Claude Desktop | Desktop app, not CLI customization |
| API | General API usage, not CLI customization |
| code | Too generic - matches all programming tasks |
| file | Too generic - matches file operations generally |
| prompt | Too broad - general prompting, not customization |
| conversation | General usage pattern, not customization |
| browser | Web interface, not CLI |
| mobile | Mobile app, not CLI |
