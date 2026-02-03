---
name: gm_new_macro
description: Create a new GM-CDE macro by following the gmcc_macro skill format. Uses explore/architect workflow pattern like gm_feature_dev.
argument-hint: [macro_name] or interactive
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, AskUserQuestion
---

# Create New Macro

You are creating a new GM-CDE macro following the gmcc_macro skill specification.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: initializing
```

**Write state:** `{"task": "new-macro", "state": "initializing"}` to `.claude/GMB_STATE.json`

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Read the macro system definition: `$GMCC_PLUGIN_ROOT/skills/gmcc_macro/SKILL.md`
2. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
3. Get current git branch

If macro system skill missing:
```
[GMB] Macro system not found.

Expected: $GMCC_PLUGIN_ROOT/skills/gmcc_macro/SKILL.md

The gmcc_macro skill defines how macros work. Check your GM-CDE installation.
```

---

## Phase 1: Gather Macro Metadata

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: planning
```

**Write state:** `{"task": "new-macro", "state": "planning"}` to `.claude/GMB_STATE.json`

### Parse Arguments

If `$ARGUMENTS` provided, parse macro name.

If no arguments, use AskUserQuestion:
```
What macro would you like to create?

Enter a name for the macro (lowercase, underscores allowed):
```

### Gather Macro Type

Use AskUserQuestion:
```
What type of macro is '{macro_name}'?

- Workflow - Multi-phase process with hooks and state management
- CLI - Shell automation pattern (not yet implemented, choose Workflow for now)
```

If CLI selected:
```
CLI macros are not yet implemented. Would you like to create a Workflow macro instead?

- Yes, make it a Workflow - Proceed with Workflow type
- No, cancel - Exit without creating
```

### Gather Macro Intention

Use AskUserQuestion:
```
Describe the intention of '{macro_name}' macro:

What does this macro do and why does it exist? (Keep it to 1 paragraph, max 5 sentences. Be direct, no corporate speak.)
```

### Create Tasks

After gathering metadata, create tasks in `$GMCC_FAM_PATH/Tasks.md`:

```markdown
## Macro: {macro_name}

- [ ] Define input context and components
- [ ] Explore existing macro patterns
- [ ] Architect macro design
- [ ] Define workflow phases
- [ ] Select phase hooks
- [ ] Generate macro skill file
- [ ] Update macro index
- [ ] Sync to instance
- [ ] Verify macro invocation works
```

Also use TaskCreate tool to track progress:

```
TaskCreate: "Define input context for {macro_name} macro"
TaskCreate: "Explore existing patterns for {macro_name} macro"
TaskCreate: "Architect {macro_name} macro design"
TaskCreate: "Define workflow phases for {macro_name} macro"
TaskCreate: "Generate {macro_name} macro skill file"
TaskCreate: "Sync {macro_name} macro to instance"
```

Mark tasks as in_progress when starting each phase, completed when done.

---

## Phase 2: Define Input Context

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: clarifying
```

**Write state:** `{"task": "new-macro", "state": "clarifying"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Define input context" task as `in_progress`

### Gather Input Format

Use AskUserQuestion:
```
What input does '{macro_name}' expect?

Describe the input format. Examples:
- "A goal string describing what to achieve"
- "Structured input with # Backstory, # Outcome, # Objectives sections"
- "A file path and operation type"

Be specific about what the macro needs to function.
```

### Gather Input Components

Use AskUserQuestion:
```
What are the components of the input?

List each distinct piece of information the macro needs:
- Component 1: {name} - {description}
- Component 2: {name} - {description}

Example for a "deploy" macro:
- target: The environment to deploy to (staging, production)
- version: The version tag to deploy
- dry_run: Whether to simulate without applying
```

**TaskUpdate:** Mark "Define input context" task as `completed`

---

## Phase 3: Explore Existing Patterns

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: exploring
```

**Write state:** `{"task": "new-macro", "state": "exploring"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Explore existing patterns" task as `in_progress`

### Launch Explorer Agents

Spawn 3 agents in parallel using Task tool with divergent exploration focuses:

**Agent 1 - Existing Macros**:
```markdown
Analyze existing GM-CDE macros to understand patterns for creating '{macro_name}'.

Read and analyze:
- $GMCC_PLUGIN_ROOT/skills/gmcc_macro/SKILL.md (macro system definition)
- $GMCC_PLUGIN_ROOT/skills/gmcc_macro_workflow_*/SKILL.md (existing workflow macros)

Focus on:
- Common phase structures
- Hook usage patterns
- State transition conventions
- Input parsing approaches

Return:
- Summary of existing macro patterns
- Reusable patterns for '{macro_name}'
- Recommended phase structure based on similar macros
```

**Agent 2 - Codebase Workflows**:
```markdown
Find workflows and patterns in the codebase that '{macro_name}' might automate or interact with.

Macro intention: {macro_intention}

Focus on:
- Related commands in $GMCC_PLUGIN_ROOT/commands/
- Similar behavioral patterns in the codebase
- Integration points with existing tools

Return:
- Relevant existing workflows
- Patterns to model from
- Integration considerations
```

**Agent 3 - GM-CDE Architecture**:
```markdown
Map the GM-CDE architecture relevant to implementing '{macro_name}'.

Read:
- $GMCC_PLUGIN_ROOT/skills/gmcc/SKILL.md (core GMB behavior)
- $GMCC_PLUGIN_ROOT/commands/gm_feature_dev.md (reference workflow)

Focus on:
- How macros integrate with GM-CDE state
- FAM interaction patterns
- Task tool integration patterns

Return:
- Architecture insights for macro design
- State management recommendations
- FAM integration points
```

### Synthesize Exploration

After agents complete, synthesize findings:

```markdown
Exploration Complete for '{macro_name}'

**Existing Macro Patterns:**
- {pattern 1}
- {pattern 2}

**Relevant Codebase Workflows:**
- {workflow 1 with file reference}
- {workflow 2}

**Architecture Insights:**
- {insight 1}
- {insight 2}

**Recommended Approach:**
{synthesis of exploration findings}
```

Save to `$GMCC_FAM_PATH/thoughts/{timestamp}_macro_exploration_{macro_name}.md`

**TaskUpdate:** Mark "Explore existing patterns" task as `completed`

---

## Phase 4: Architect Macro Design

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: architecting
```

**Write state:** `{"task": "new-macro", "state": "architecting"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Architect macro design" task as `in_progress`

### Launch Architect Agents

Using the Crack macro pattern, spawn 3 agents with divergent approaches:

**Agent 1 - Minimal Design**:
```markdown
Design '{macro_name}' macro using MINIMAL approach.

Macro Intention: {macro_intention}
Input: {input_format and components}
Exploration Findings: {summary of exploration}

Design Priorities:
- Fewest phases possible (2-3 max)
- Simple state transitions
- Minimal hooks (only essential ones)
- Reuse existing patterns directly

Return:
- Proposed phase structure
- Hook recommendations
- State transitions
- Trade-offs of this approach
```

**Agent 2 - Comprehensive Design**:
```markdown
Design '{macro_name}' macro using COMPREHENSIVE approach.

Macro Intention: {macro_intention}
Input: {input_format and components}
Exploration Findings: {summary of exploration}

Design Priorities:
- Thorough phase separation (4-6 phases)
- Full hook lifecycle
- Detailed state management
- Extensibility for future enhancements

Return:
- Proposed phase structure
- Hook recommendations
- State transitions
- Trade-offs of this approach
```

**Agent 3 - Pragmatic Design**:
```markdown
Design '{macro_name}' macro using PRAGMATIC approach.

Macro Intention: {macro_intention}
Input: {input_format and components}
Exploration Findings: {summary of exploration}

Design Priorities:
- Balance simplicity and completeness
- Phases that map to natural workflow breaks
- Hooks where they add clear value
- Good enough for now, easy to extend

Return:
- Proposed phase structure
- Hook recommendations
- State transitions
- Trade-offs of this approach
```

### Synthesize and Present

Compare all approaches and present to user:

Use AskUserQuestion:
```
I've analyzed three design approaches for '{macro_name}':

**Option 1: Minimal Design**
{2-3 sentence summary}
Phases: {count}
Hooks: {list}
Trade-offs: Fast to implement, may need extension later

**Option 2: Comprehensive Design**
{2-3 sentence summary}
Phases: {count}
Hooks: {list}
Trade-offs: More complete, takes longer to define

**Option 3: Pragmatic Design** (Recommended)
{2-3 sentence summary}
Phases: {count}
Hooks: {list}
Trade-offs: Balanced approach, reasonable complexity

Which design approach do you prefer?
- Option 1: Minimal Design
- Option 2: Comprehensive Design
- Option 3: Pragmatic Design (Recommended)
- Let me specify: I have a different preference
```

### Save Architecture Decision

Save to `$GMCC_FAM_PATH/thoughts/{timestamp}_macro_architecture_{macro_name}.md`:

```markdown
# Thought: Macro Architecture Decision - {macro_name}

**Date**: {timestamp}

## Approaches Considered

### Approach 1: Minimal Design
{summary}
- Phases: {list}
- Hooks: {list}
- Pros: {list}
- Cons: {list}

### Approach 2: Comprehensive Design
{summary}
- Phases: {list}
- Hooks: {list}
- Pros: {list}
- Cons: {list}

### Approach 3: Pragmatic Design
{summary}
- Phases: {list}
- Hooks: {list}
- Pros: {list}
- Cons: {list}

## Chosen Approach
{which and why}

## Final Design
- Phases: {final phase list}
- Hooks: {final hook list}
```

**TaskUpdate:** Mark "Architect macro design" task as `completed`

---

## Phase 5: Define Phases (Workflow Only)

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: designing
```

**Write state:** `{"task": "new-macro", "state": "designing"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Define workflow phases" task as `in_progress`

### Refine Phase Details

Based on chosen architecture, use AskUserQuestion to confirm/refine each phase:

For each phase in the chosen design:

```
Confirm Phase {n}: {phase_name}

Based on the architecture, this phase should:
- {outcome goal from architect}
- {key actions from architect}

Does this look correct?
- Yes, use this - Proceed with this phase definition
- Modify - Let me adjust the phase details
```

If user wants to modify, gather:
```
Define Phase {n}:

**Phase Name** (short, descriptive):

**Outcome Goals** (what should be achieved):

**Key Actions** (what happens in this phase):
```

### Confirm Hooks

Based on architect recommendation, confirm hooks:

```
The architecture recommends these hooks:

{list of recommended hooks with descriptions}

Accept these hook selections?
- Yes, use recommended - Proceed with these hooks
- Modify - Let me choose different hooks
```

**TaskUpdate:** Mark "Define workflow phases" task as `completed`

---

## Phase 6: Generate Macro Skill File (via Evolution Pattern)

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: implementing
```

**Write state:** `{"task": "new-macro", "state": "implementing"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Generate macro skill file" task as `in_progress`

### Evolution Integration

**IMPORTANT**: New macros are GM-CDE evolutions. Follow the `/gm_evolve` pattern:
1. Write to **template first** (source of truth)
2. Sync to instance second
3. Log the evolution in EVOLUTION_LOG.md

### Create Skill File

Generate the macro skill file following the gmcc_macro format.

**File location:** `$GMCC_REPO_PATH/gmcc_plugin_template/skills/gmcc_macro_workflow_{macro_name}/SKILL.md`

**Template:**

```markdown
---
name: gmcc_macro_workflow_{macro_name}
description: {Macro Intention - first sentence}
user-invocable: false
---

# {Macro Name} Macro - Workflow Implementation

## Macro Type: Workflow

---

## Macro Intention

{Full macro intention paragraph}

---

## Macro Input Context

### Expected Input Format

{Input format description}

### Input Parsing

{How to interpret the input}

### Input Components

{List each component}

---

## Macro Implementation

### Before All Hook

```markdown
#### Before All

{Before All hook instructions if selected, otherwise "No Before All hook defined."}
```

### Before Each Hook

```markdown
#### Before Each

{Before Each hook instructions if selected, otherwise "No Before Each hook defined."}
```

### After Each Hook

```markdown
#### After Each

{After Each hook instructions if selected, otherwise "No After Each hook defined."}
```

### After All Hook

```markdown
#### After All

{After All hook instructions if selected, otherwise "No After All hook defined."}
```

---

{For each phase:}

### Phase_{n} ~ {Phase_Name}

#### Phase Outcome Goals

{Phase outcome goals}

#### Phase States / Transitions

- Entry State: {previous phase exit state or "initializing"}
- Exit State: {descriptive state name}
- Failure State: {failure state name}

#### Phase Instructions

{Phase instructions and key actions}

---

## Error Handling

{Define error cases and recovery}

---

## Usage Example

{Show how to invoke this macro}
```

### Write to Template

Write the generated file to the template directory.

### Update Macro Index

Edit `$GMCC_REPO_PATH/gmcc_plugin_template/skills/gmcc_macro/SKILL.md` to add the new macro to the index table.

**TaskUpdate:** Mark "Generate macro skill file" task as `completed`

---

## Phase 7: Sync to Instance & Log Evolution

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: new-macro | STATE: syncing
```

**Write state:** `{"task": "new-macro", "state": "syncing"}` to `.claude/GMB_STATE.json`

**TaskUpdate:** Mark "Sync macro to instance" task as `in_progress`

### Copy to Instance

1. Create `$GMCC_PLUGIN_ROOT/skills/gmcc_macro_workflow_{macro_name}/SKILL.md` from template
2. Update `$GMCC_PLUGIN_ROOT/skills/gmcc_macro/SKILL.md` with new index entry

### Log Evolution

Append to `$GMCC_REPO_PATH/EVOLUTION_LOG.md`:

```markdown
## [Evolution {next_number}] - {TODAY}

### Description
New macro created: {macro_name}

### Changes
**Template (created):**
- `skills/gmcc_macro_workflow_{macro_name}/SKILL.md`

**Template (modified):**
- `skills/gmcc_macro/SKILL.md` (index updated)

**Instance (synced):**
- `skills/gmcc_macro_workflow_{macro_name}/SKILL.md`
- `skills/gmcc_macro/SKILL.md`

### Impact
- New {macro_type} macro available: `gmcc_macro:{macro_type}:{macro_name}()`
- {phases} phases, hooks: {hooks_list}

### Breaking Changes
None

---
```

### Update ChangedFiles.md

Add evolution entry to `ckfs/fam/{branch}/ChangedFiles.md`:

```markdown
## Evolution {next_number}: New Macro - {macro_name}
**Template (created):**
- `$GMCC_REPO_PATH/gmcc_plugin_template/skills/gmcc_macro_workflow_{macro_name}/SKILL.md`

**Template (modified):**
- `$GMCC_REPO_PATH/gmcc_plugin_template/skills/gmcc_macro/SKILL.md`

**Instance (synced):**
- `$GMCC_PLUGIN_ROOT/skills/gmcc_macro_workflow_{macro_name}/SKILL.md`
- `$GMCC_PLUGIN_ROOT/skills/gmcc_macro/SKILL.md`
```

**TaskUpdate:** Mark "Sync macro to instance" task as `completed`

### Update Tasks.md

Mark all macro tasks as complete in `$GMCC_FAM_PATH/Tasks.md`

---

## Phase 8: Report

### Update Status
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle
```

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

### Final Report

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

New Macro Created: {macro_name}

**Type:** Workflow
**Phases:** {n}
**Hooks:** {list selected hooks}
**Architecture:** {chosen approach name}

**Exploration Insights:**
- {key pattern used}
- {integration point considered}

**Files Created:**
- $GMCC_REPO_PATH/gmcc_plugin_template/skills/gmcc_macro_workflow_{macro_name}/SKILL.md
- $GMCC_PLUGIN_ROOT/skills/gmcc_macro_workflow_{macro_name}/SKILL.md

**Thoughts Generated:**
- {timestamp}_macro_exploration_{macro_name}.md
- {timestamp}_macro_architecture_{macro_name}.md

**Index Updated:**
- gmcc_macro/SKILL.md

**Next Steps:**
- Review the generated skill file
- Adjust phase instructions as needed
- Test the macro in a workflow
```

---

## Error Handling

**Macro name already exists:**
```
[GMB] Macro '{macro_name}' already exists.

Use a different name or edit the existing macro directly.
```

**User cancels mid-creation:**
```
[GMB] Macro creation cancelled.

No files were written.
```

**Exploration agent failure:**
```
[GMB] Warning: Exploration agent {n} failed.

Proceeding with available exploration data.
{summary of what was gathered}
```

**Architecture agent failure:**
```
[GMB] Warning: Architecture agent {n} failed.

Proceeding with {count} design approaches.
```
