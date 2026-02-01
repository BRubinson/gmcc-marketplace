---
name: gmcc_macro
description: GM-CDE Macro System - Defines how macros are formatted, executed, defined, and created. Macros are reusable behavioral templates that can be invoked to execute predefined workflows or CLI patterns.
user-invocable: false
---

# GMCC Macro System

This skill defines the GM-CDE macro system - a framework for creating reusable, templated behavioral patterns that the GMB can execute.

## What is a Macro?

A macro is a predefined set of behaviors that are filled in like a template and executed. Unlike commands (which are user-invoked) or skills (which define agent behavior), macros are **composable behavioral patterns** that can be invoked within other workflows or directly.

Macros follow the naming convention: `gmcc_macro_{macro_type}_{macro_name}`

---

## Macro Index

| Macro | Type | Purpose |
|-------|------|---------|
| `gmcc_macro_workflow_eclair` | Workflow | **Primary workflow macro.** 6-phase Research-Plan-Implement workflow with cross-session learning (Explore, Clarify, Learn, Architect, Implement, Review). Supports `mode: "full"` (4 divergent agents) or `mode: "lite"` (1 hybrid agent). |

### ECLAIR Modes

| Mode | Agents per Phase | Use Case |
|------|------------------|----------|
| `full` (default) | 4 divergent (Conservative, Aggressive, Pragmatic, Alternative) | Complex features, thorough exploration |
| `lite` | 1 hybrid (Pragmatic+Alternative) | Quick tasks, bug fixes |

### LITE Mode: Pragmatic+Alternative Hybrid Methodology

The LITE mode uses a hybrid of two methodologies executed by a single agent:

**Pragmatic Mindset:**
- Focus on effort-to-value ratio
- Maximize team code familiarity
- Optimize for readability and maintainability
- Avoid over-engineering for the problem at hand
- Balance quality with shipping velocity

**Alternative Mindset:**
- Challenge established assumptions
- Identify unconventional but valuable approaches
- Explore design space beyond proven patterns
- Question "that's how we always do it"
- Find elegant edge-case solutions

**Hybrid Execution:**
The agent applies both lenses sequentially:
1. **Pragmatic pass**: What's the straightforward, familiar solution that balances effort and quality?
2. **Alternative pass**: What interesting approach might we be missing? Where could we challenge assumptions for genuine improvement?
3. **Synthesis**: Integrate pragmatic foundation with alternative improvements that actually add value.

Result: Single perspective that avoids both "business as usual" and "perfect is enemy of good."

---

## Macro Types

### 1. Workflow Macros

Workflow macros define a controlled, multi-phase execution process. They are the primary macro type and include phase hooks for orchestration.

**Use workflow macros when:**
- The task requires multiple sequential phases
- State needs to be tracked across phases
- Multiple agents or steps need coordination
- The process should be resumable/interruptible

**Structure:** See "Workflow Macro Format" below.

### 2. CLI Macros (Future)

CLI macros will provide shell-level automation patterns. They are planned but not yet implemented.

**Status:** TO BE IMPLEMENTED LATER

---

## Macro File Format

Every macro skill file must contain these sections:

### 1. Macro Type Declaration

```markdown
## Macro Type: Workflow
```

Declares whether this is a Workflow or CLI macro.

### 2. Macro Intention

A concise elevator pitch (max 5 sentences, 1 paragraph) explaining what the macro does and why it exists. No corporate buzzwords - straight talk about purpose.

```markdown
## Macro Intention

The Crack macro spawns multiple agents with deliberately different approaches to solve the same problem. Each agent commits fully to their assigned methodology (conservative, aggressive, balanced, alternative) without trying to compromise. A synthesis phase then combines the best insights from all approaches. This produces solutions that benefit from diverse perspectives while avoiding groupthink.
```

### 3. Macro Input Context

Defines expected inputs and how to parse/interpret them.

```markdown
## Macro Input Context

### Expected Input Format
{Description of what input the macro expects}

### Input Parsing
{How to interpret and structure the input}

### Input Components
- **Component 1**: {description}
- **Component 2**: {description}
```

### 4. Macro Implementation (Type-Specific)

The actual macro behavior, structured according to macro type.

---

## Workflow Macro Format

Workflow macros are defined by **phases** and **phase hooks**.

### Phase Hooks

Phase hooks execute at specific points in the workflow lifecycle:

| Hook | Triggers | Purpose |
|------|----------|---------|
| `Before All` | Once before first phase starts | Setup, validation, initialization |
| `Before Each` | Before each phase begins | Phase preparation, state checks |
| `After Each` | After each phase completes | Cleanup, logging, state updates |
| `After All` | Once after last phase completes | Final cleanup, summary, reporting |

### Phase Structure

Each phase follows this format:

```markdown
### Phase_{N} ~ {Phase_Name}

#### Phase Outcome Goals
{What should be achieved by the end of this phase}

#### Phase States / Transitions
- Entry State: {expected state when entering}
- Exit State: {state after successful completion}
- Failure State: {state if phase fails}

#### Phase Instructions
{Detailed instructions for executing this phase}
```

### Workflow State Management

Workflow macros should update GMB_STATE.json at phase transitions:

```json
{
  "task": "macro-{macro_name}",
  "state": "phase_{n}_{phase_name}",
  "macro": "{macro_name}",
  "phase": {n}
}
```

---

## Creating New Macros

To create a new macro, use the `/gm_new_macro` command which will:

1. Gather macro metadata (name, type, intention)
2. Define input context
3. For workflow macros: define phases and hooks
4. Create the skill file following this format
5. Update this macro index

### Naming Conventions

- Macro skill files: `skills/gmcc_macro_{type}_{name}/SKILL.md`
- Macro names: lowercase with underscores
- Types: `workflow`, `cli` (future)

### Example Macro Names

- `gmcc_macro_workflow_eclair` - Primary workflow macro with FULL/LITE modes
- `gmcc_macro_workflow_validate` - Multi-agent validation workflow (future)
- `gmcc_macro_cli_deploy` - Deployment automation (future)

### Integration with GMCC Agents

Macros can spawn GMCC agents for specialized work. See `gmcc_agent` skill for agent definitions.

Available agents:
- `gmcc_agent_code_explorer` - Deep codebase analysis
- `gmcc_agent_code_architect` - Architecture design
- `gmcc_agent_code_quality_reviewer` - Code review

---

## Invoking Macros

Macros use the unified GMCC syntax:

```
gmcc:macro:{macro_type}:{macro_name}()
```

### Invocation Syntax

**Basic invocation (FULL mode, contextual input):**
```
gmcc:macro:workflow:eclair(
  session_name: "feat_auth_system",
  initial_prompt: "implement user authentication"
)
```
The macro pulls additional context from FAM files and conversation history.

**LITE mode invocation:**
```
gmcc:macro:workflow:eclair(
  session_name: "task_fix_login",
  initial_prompt: "fix login validation bug",
  mode: "lite"
)
```

**Via command wrappers (recommended):**
- `/gm_feature_dev` → Invokes ECLAIR FULL mode
- `/gm_task` → Invokes ECLAIR LITE mode

### Input Resolution

When a macro is invoked:

1. **Named params take priority** - Explicitly passed values are used directly
2. **Contextual fill-in** - Missing params are inferred from:
   - Current conversation context
   - FAM Purpose.md and Tasks.md
   - Recent thoughts
   - Surrounding prompt content

### Examples

**From /gm_feature_dev (FULL mode):**
```markdown
# User runs: /gm_feature_dev add caching layer

# Command internally invokes:
gmcc:macro:workflow:eclair(
  mode: "full",
  session_name: "feat_caching_layer",
  initial_prompt: "add caching layer"
)
```

**From /gm_task (LITE mode):**
```markdown
# User runs: /gm_task fix login bug

# Command internally invokes:
gmcc:macro:workflow:eclair(
  mode: "lite",
  session_name: "task_fix_login_bug",
  initial_prompt: "fix login bug"
)
```

**Direct invocation (advanced):**
```markdown
gmcc:macro:workflow:eclair(
  session_name: "feat_oauth_support",
  initial_prompt: "Add OAuth support to authentication system",
  mode: "full"
)
```

### Execution Flow

When GMB encounters a macro invocation:

1. Parse the skill path: `gmcc_macro:{type}:{name}`
2. Read the macro skill file: `skills/gmcc_macro_{type}_{name}/SKILL.md`
3. Resolve input (named params merged with contextual)
4. Execute Before All hook
5. Execute each phase with Before Each / After Each hooks
6. Execute After All hook
7. Return macro output to caller

### Legacy Syntax (Deprecated)

The old `|~<MacroName, params/>` syntax from MACROS.md is deprecated. Use hybrid skill/function syntax instead.

---

## Integration with GM-CDE

Macros operate within the GM-CDE framework:
- They inherit GMB behavioral rules
- They can read/write ckfs files
- They respect ACTIVE_BRANCH context
- They update GMB_STATE.json during execution
- Their outputs can create thoughts in the FAM

---

## Best Practices

1. **Single Responsibility**: Each macro should do one thing well
2. **Clear Phases**: Workflow phases should have distinct, verifiable outcomes
3. **Fail Gracefully**: Include failure states and recovery paths
4. **Document Inputs**: Be explicit about what input format the macro expects
5. **State Visibility**: Keep GMB_STATE.json updated so users can track progress
