# Chewed: modelconfig

**Source**: primary/documentation/modelconfig
**Chewed By**: gmcc:agent:kbite_crunch_chew
**Date**: 2026-02-02T00:00:00Z
**Confidence**: 95

---

## 1. Contents Overview

| File | Type | Description |
|------|------|-------------|
| modelconfig | md | Complete documentation on model configuration, aliases, environment variables, and prompt caching |

---

## 2. Key Learnings Summary

1. **Model Aliases Simplify Configuration**: Aliases (default, sonnet, opus, haiku, opusplan) abstract away version numbers and auto-select latest versions.

2. **Four-Level Configuration Hierarchy**: Session commands > startup flags > environment variables > settings file.

3. **OpusPlan Hybrid Mode**: Uses Opus for plan mode, Sonnet for execution - optimizing quality and cost.

4. **Environment Variables Control Mapping**: ANTHROPIC_DEFAULT_{OPUS|SONNET|HAIKU}_MODEL customize alias resolution.

5. **Granular Prompt Caching Control**: Disable globally or per model tier.

---

## 3. Technical Details

### Model Aliases
| Alias | Behavior |
|-------|----------|
| default | Account-type dependent with auto-fallback |
| sonnet | Latest Sonnet for daily coding |
| opus | Latest Opus for complex reasoning |
| haiku | Fast, efficient for simple tasks |
| opusplan | Opus in plan mode, Sonnet in execution |
| sonnet[1m] | Sonnet with 1M token context |

### Configuration Priority
1. `/model <alias>` (session)
2. `--model <alias>` (startup)
3. `ANTHROPIC_MODEL=<alias>` (env)
4. settings file

### Environment Variables
- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `CLAUDE_CODE_SUBAGENT_MODEL`
- `DISABLE_PROMPT_CACHING=1`
- `DISABLE_PROMPT_CACHING_{HAIKU|SONNET|OPUS}=1`

### Takeaways

| # | Type | Takeaway |
|---|------|----------|
| 1 | GOOD | Use model aliases instead of hardcoding versions |
| 2 | GOOD | Use opusplan for workflows needing both reasoning and execution |
| 3 | GOOD | Configure at appropriate scope: session for temporary, settings for permanent |
| 4 | GOOD | Use environment variables to control alias mappings |
| 5 | GOOD | Disable prompt caching selectively when debugging |
| 6 | BAD | Avoid ANTHROPIC_SMALL_FAST_MODEL (deprecated) |
| 7 | GOOD | Add [1m] suffix for extended context window |
| 8 | GOOD | Check configuration via /status |

---

## 4. Keywords and Triggers

### Primary Keywords
model configuration, model aliases, opusplan, sonnet, opus, haiku, anthropic_model, prompt caching, extended context, environment variables, configuration hierarchy, subagent model

### Suggested Triggers
model, opusplan, alias, configuration priority, prompt caching, environment variable, ANTHROPIC_DEFAULT, extended context, subagent model, model switching

---

## Cross-References

- Settings file documentation
- Status line documentation
- Sub-agents documentation
- Pricing documentation
