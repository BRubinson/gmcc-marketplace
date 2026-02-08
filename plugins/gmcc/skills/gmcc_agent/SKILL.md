---
name: gmcc_agent
description: GM-CDE Agent System - Defines how GMCC agents are structured, invoked, and behave. Agents are specialized personas with defined capabilities, behaviors, and output formats that operate within the GM-CDE framework.
user-invocable: false
---

# GMCC Agent System

This skill defines the GM-CDE agent system - a framework for creating specialized agent personas that can be invoked to perform specific types of work within the GM-CDE ecosystem.

## What is a GMCC Agent?

A GMCC Agent is a specialized persona with:
- **Defined personality and behaviors** - How the agent approaches problems
- **Specific capabilities** - What actions the agent is suited to perform
- **Structured output format** - Predictable response syntax for parent orchestration

Unlike commands (which are user-invoked), agents are **specialized workers** that can be spawned by bot workflow commands or directly.

Agents follow the naming convention: `gmcc_agent_{agent_name}`

---

## Agent Index

| Agent | Purpose | Primary Use |
|-------|---------|-------------|
| `gmcc_agent_code_explorer` | Deep codebase analysis and pattern discovery | Understanding existing code before changes |
| `gmcc_agent_code_architect` | Architecture design and implementation planning | Designing features and changes |
| `gmcc_agent_code_quality_reviewer` | Code review for bugs, security, and quality | Reviewing proposed or existing code |

---

## Invocation Syntax

GMCC Agents use a unified invocation syntax:

```
gmcc:agent:{agent_name}(input)
```

### Invocation Examples

**Basic invocation:**
```
gmcc:agent:code_explorer(target: "src/auth/")
```

**With methodology seed (for bot workflows):**
```
gmcc:agent:code_architect(
  goal: "design caching layer",
  methodology: "conservative"
)
```

**Contextual invocation:**
```
gmcc:agent:code_quality_reviewer()
# Pulls context from conversation and FAM
```

### Via Task Tool

When spawning agents programmatically, use the Task tool:

```
Task tool:
  subagent_type: general-purpose
  prompt: [Agent prompt from agent file with parameters filled in]
```

---

## Agent File Structure

Every GMCC Agent file must contain these sections:

### 1. Frontmatter

```yaml
---
name: gmcc_agent_{name}
description: {Brief description of agent purpose}
model: sonnet
tools: [List of tools agent can use]
---
```

### 2. Agent Identity

```markdown
# GMCC Agent: {Name}

You are a GMCC Agent operating within the GM-CDE framework.

## GM-CDE Integration

On startup, you MUST:
1. Acknowledge you are operating as a GMB sub-agent
2. Reference the GMCC skill for GM-CDE rules
3. Respect ACTIVE_BRANCH context
4. Follow OUTPUT_MODE guidelines
```

### 3. Personality Matrix and Behaviors

Defines how the agent generally behaves and approaches problems:

```markdown
## Personality Matrix

### Core Traits
- {trait 1}: {description}
- {trait 2}: {description}

### Problem-Solving Approach
{How does this agent tackle problems?}

### Priorities
1. {First priority}
2. {Second priority}
3. {Third priority}
```

### 4. Capabilities

What actions this agent is suited to perform:

```markdown
## Capabilities

### Primary Functions
- {capability 1}
- {capability 2}

### Tools Used
- {tool}: {how it's used}

### Limitations
- {what this agent should NOT do}
```

### 5. Output Syntax

Predefined markdown structure the agent returns:

```markdown
## Output Syntax

The agent MUST return output in this exact format:

\`\`\`markdown
## {Agent Name} Report

### Section 1
{content}

### Section 2
{content}
\`\`\`
```

### 6. Methodology Support (Optional)

For agents that support bot workflow methodology seeding:

```markdown
## Methodology Modes

When invoked with a methodology parameter, adapt behavior:

### Conservative Mode
{how to behave conservatively}

### Aggressive Mode
{how to behave aggressively}

### Pragmatic Mode
{how to balance}

### Alternative Mode
{how to think differently}
```

---

## Integration with Bot Workflows

Bot workflow commands spawn GMCC agents for specialized work phases. Agents receive kbite context, task prompts, and methodology assignments.

### Agent Usage by Command

| Command | Phase | Agent Used |
|---------|-------|------------|
| `/gm_bot_rpi` | Implementation Overview | 1x `gmcc_agent_code_explorer` |
| `/gm_bot_rpi` | Plan | 1x `gmcc_agent_code_architect` |
| `/gm_bot_rpi` | Review | 1x `gmcc_agent_code_quality_reviewer` |
| `/gm_bot_team` | Implementation Overview | 4x `gmcc_agent_code_explorer` + 1x `gmcc_agent_code_architect` (synthesizer) |
| `/gm_bot_team` | Plan | 4x `gmcc_agent_code_architect` + 1x coordinator |
| `/gm_bot_team` | Review | 4x `gmcc_agent_code_quality_reviewer` |

### Methodology Seeding

In `/gm_bot_team`, each agent in a team receives one of four methodology assignments:
- **Conservative**: Stability, proven patterns, minimal risk
- **Aggressive**: Innovation, rewrites, new approaches
- **Pragmatic**: Balance effort/value, team familiarity
- **Alternative**: Unconventional approaches, challenge assumptions

In `/gm_bot_rpi`, the single agent applies all 4 methodologies sequentially.

---

## Creating New Agents

To create a new GMCC agent:

1. Create file: `.claude/agents/gmcc_agent_{name}.md`
2. Follow the agent file structure above
3. Update this agent index
4. Test with direct invocation before using in bot workflows

### Naming Conventions

- Agent files: `agents/gmcc_agent_{name}.md`
- Names: lowercase with underscores
- Keep names descriptive but concise

---

## Best Practices

1. **Single Focus**: Each agent should excel at one type of task
2. **Clear Output**: Output format must be parseable by parent workflows
3. **GM-CDE Aware**: Always reference GMCC skill and respect GM-CDE properties
4. **Methodology Flexible**: Support methodology seeding for bot workflow compatibility
5. **Tool Appropriate**: Only list tools the agent actually needs
6. **Fail Gracefully**: Include guidance for handling edge cases

---

## Syntax Reference

### GMCC Syntax

All GMCC constructs use the `gmcc:` prefix:

| Type | Syntax | Example |
|------|--------|---------|
| Agent | `gmcc:agent:{name}(params)` | `gmcc:agent:code_explorer(target: "src/")` |

This syntax makes GMCC agent invocations easily identifiable and parseable.
