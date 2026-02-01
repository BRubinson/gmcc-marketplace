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

Unlike macros (which define workflows) or commands (which are user-invoked), agents are **specialized workers** that can be spawned by macros, commands, or directly.

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

**With methodology seed (for Crack macro):**
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

For agents that support Crack macro methodology seeding:

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

## Integration with Crack Macro

The Crack macro spawns multiple instances of GMCC agents with different methodology seeds. The workflow:

1. Crack macro receives goal and context
2. Spawns N agents (typically code_architect) with different methodologies
3. Each agent produces output in their defined format
4. Crack synthesizes outputs into unified recommendation

### Agent Selection for Crack

| Phase | Agent Used |
|-------|------------|
| Exploration | `gmcc_agent_code_explorer` |
| Architecture | `gmcc_agent_code_architect` |
| Review | `gmcc_agent_code_quality_reviewer` |

---

## Creating New Agents

To create a new GMCC agent:

1. Create file: `.claude/agents/gmcc_agent_{name}.md`
2. Follow the agent file structure above
3. Update this agent index
4. Test with direct invocation before using in macros

### Naming Conventions

- Agent files: `agents/gmcc_agent_{name}.md`
- Names: lowercase with underscores
- Keep names descriptive but concise

---

## Best Practices

1. **Single Focus**: Each agent should excel at one type of task
2. **Clear Output**: Output format must be parseable by parent workflows
3. **GM-CDE Aware**: Always reference GMCC skill and respect GM-CDE properties
4. **Methodology Flexible**: Support methodology seeding for Crack compatibility
5. **Tool Appropriate**: Only list tools the agent actually needs
6. **Fail Gracefully**: Include guidance for handling edge cases

---

## Syntax Reference

### Unified GMCC Syntax

All GMCC constructs use the `gmcc:` prefix:

| Type | Syntax | Example |
|------|--------|---------|
| Agent | `gmcc:agent:{name}(params)` | `gmcc:agent:code_explorer(target: "src/")` |
| Macro | `gmcc:macro:{type}:{name}(params)` | `gmcc:macro:workflow:crack(n: 3)` |

This unified syntax makes GMCC constructs easily identifiable and parseable.
