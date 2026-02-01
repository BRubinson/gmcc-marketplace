---
name: gmcc_macro_workflow_eclair
description: ECLAIR Macro - Explore, Clarify, Learn, Architect, Implement, Review. The GM-CDE native method for high-accuracy code implementation with cross-session learning accumulation.
user-invocable: false
---

# ECLAIR Macro - Workflow Implementation

## Macro Type: Workflow

---

## Macro Intention

ECLAIR is the GM-CDE native method to leverage Claude/GMB and GMCC to implement code and other LLM tasks with mind-blowing accuracy and quality. It provides a 6-phase Research-Plan-Implement workflow that accumulates learnings across sessions through the ECLAIR_BRAIN. Each phase has clear inputs, outputs, and state transitions enabling full resumability. The macro integrates tightly with GM-CDE protocols, spawning methodology-seeded agents for exploration and architecture, using AskUserQuestion for clarification, and leveraging plan mode for context management.

---

## Macro Input Context

### Expected Input Format

ECLAIR receives an initial prompt describing the task/feature to implement, plus a session name identifier:

```markdown
# ECLAIR Session

**Session Name**: {eclair_name} (e.g., "feat_oauth_support", "evolve_gmcc_macros")
**Initial Prompt**: {The raw user request to be processed through all 6 phases}
```

### Input Parsing

1. **Session Name**: Used for ECLAIR_STATE_{session_name}.md filename
2. **Initial Prompt**: The raw task/feature request that gets refined through phases

### Input Components

| Component | Required | Description |
|-----------|----------|-------------|
| `session_name` | Yes | Unique identifier for this ECLAIR session (snake_case recommended) |
| `initial_prompt` | Yes | The raw task/feature request to process |
| `mode` | Optional | `"full"` (default) or `"lite"` - controls agent spawning behavior |
| `context` | Optional | Additional context about the codebase or task |

### Mode Parameter

ECLAIR supports two execution modes:

| Mode | Agent Behavior | Use Case |
|------|----------------|----------|
| `full` | Spawns 4 divergent methodology-seeded agents (Conservative, Aggressive, Pragmatic, Alternative) in Phases 1, 4, 6 | Complex features, architecture decisions, thorough exploration |
| `lite` | Spawns 1 hybrid agent (Pragmatic+Alternative) in Phases 1, 4, 6 | Quick tasks, bug fixes, well-scoped work |

**LITE Mode Hybrid Methodology**: Combines Pragmatic (balance effort/value, team familiarity, optimize for readability) with Alternative (explore unconventional approaches, challenge assumptions) for a single balanced perspective that maintains quality while reducing overhead.

---

## GMCC Native Integration

**CRITICAL**: ECLAIR must execute within the GM-CDE context. It:
- Updates GMB_STATE.json at phase transitions
- Writes to FAM files (ECLAIR_STATE, ECLAIR_BRAIN, Tasks.md)
- Creates thoughts at key decision points
- Respects ACTIVE_BRANCH context

---

## Macro Implementation

### Before All Hook

```markdown
#### Before All

1. **Parse and validate mode parameter**:
   ```
   mode = input.mode || "full"
   if mode not in ["full", "lite"]:
     error "Invalid mode. Must be 'full' or 'lite'"
   ```

2. **Read ECLAIR_BRAIN.md** from `$GMCC_FAM_PATH/ECLAIR_BRAIN.md`
   - If file doesn't exist, create it with empty structure
   - Extract relevant brain bites for the current task (relevance >50)

3. **Create ECLAIR_STATE_{session_name}.md** at `$GMCC_FAM_PATH/ECLAIR_STATE_{session_name}.md`
   - Initialize with session metadata, goal, status="initializing"
   - **Include mode in state**: `**Mode**: {mode}`
   - Set up phase output sections (all pending)

4. **Define Phase Tasks in Tasks.md** under section `## ECLAIR - {session_name}`
   - Create parent task for each phase:
     - [ ] Phase 1: Explore
     - [ ] Phase 2: Clarify
     - [ ] Phase 3: Learn
     - [ ] Phase 4: Architect
     - [ ] Phase 5: Implement
     - [ ] Phase 6: Review

5. **Update GMB_STATE.json**:
   ```json
   {
     "task": "macro-eclair",
     "state": "initializing",
     "macro": "eclair",
     "session_name": "{session_name}",
     "mode": "{mode}",
     "phase": 0
   }
   ```

6. **Create invocation thought**: `thoughts/{timestamp}_eclair_{session_name}_start.md`
```

### Before Each Hook

```markdown
#### Before Each

1. Read phase input from previous phase output (or initial_prompt for Phase 1)
2. Verify phase dependencies met (e.g., Clarify complete before Learn)
3. Update ECLAIR_STATE with current phase status = "in_progress"
```

### After Each Hook

```markdown
#### After Each

1. **Define phase OUTPUT** - structured JSON saved to ECLAIR_STATE:
   ```json
   {
     "phase": "{phase_name}",
     "status": "complete",
     "timestamp": "{ISO timestamp}",
     "output": { /* phase-specific output */ }
   }
   ```

2. **Update GMB_STATE.json** with completed phase

3. **Check off phase task** in Tasks.md

4. **Create phase thought** if significant decisions were made
```

### After All Hook

```markdown
#### After All

1. **Write session summary** to user covering all 6 phases

2. **Verify all tasks checked off** in Tasks.md ECLAIR section

3. **Finalize ECLAIR_STATE** with status="complete"

4. **Create completion thought**: `thoughts/{timestamp}_eclair_{session_name}_complete.md`

5. **Reset GMB_STATE.json** to idle
```

---

## ECLAIR Principles / Phases

The 6 ECLAIR phases form the workflow structure:

1. **Explore** - Initial understanding through multi-agent codebase exploration
2. **Clarify** - Resolve ambiguities through user interaction
3. **Learn** - Document learnings to brain, create annotated prompt, trigger plan mode
4. **Architect** - Design implementation through divergent agent approaches
5. **Implement** - Execute design with task tracking
6. **Review** - Quality gates and multi-agent code review

---

### Phase_1 ~ Explore

#### Phase Outcome Goals

- A clarification of confusing reasoning/grammar/logic/organization of the initial prompt, saved to ECLAIR_STATE
- An exploration of relevant source files to understand which ones might be part of the requested features
- An exploration of relevant resource files in ckfs and a general collection of which may be relevant

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `clarifying_initial_prompt` | Entry state - analyze and clarify the initial prompt |
| `exploring_relevant_files` | Source and resource file exploration via agents |
| `building_final_report` | Compile exploration findings |
| `done` | Phase complete, ready for Clarify |

- Entry State: `clarifying_initial_prompt`
- Exit State: `done`
- Failure State: `exploration_failed`

#### Phase Instructions

**State: clarifying_initial_prompt**

1. Start 1 gmcc:agent:code_explorer with instructions:
   > "Do a brief overview of the initial prompt, resources, and source. Return a list of clarifying grammar issues and uncertainties. This is a very high level task."

2. Ask clarifying questions about prompt clarity using AskUserQuestion

3. Save Q&A to phase state, transition to `exploring_relevant_files`

**State: exploring_relevant_files**

4. **Spawn agents based on mode**:

   **If mode == "full"** - Start 4 gmcc:agent:code_explorer agents in parallel:

   | Agent | Methodology | Focus |
   |-------|-------------|-------|
   | 1 | Conservative | Find existing patterns that can be reused directly |
   | 2 | Aggressive | Identify areas that might need significant changes |
   | 3 | Pragmatic | Balance effort/value in exploration scope |
   | 4 | Alternative | Look for unconventional integration points |

   **If mode == "lite"** - Start 1 gmcc:agent:code_explorer with hybrid methodology:

   | Agent | Methodology | Focus |
   |-------|-------------|-------|
   | 1 | Pragmatic+Alternative | Balance practical implementation with creative alternatives. Consider both standard patterns and unconventional approaches. Optimize for readability while challenging assumptions where beneficial. |

5. Collect outputs from all agents, transition to `building_final_report`

**State: building_final_report**

6. Compile explorations into final report including:
   - Key files identified (source + ckfs resources)
   - Patterns discovered
   - Integration points
   - Uncertainties requiring clarification

7. Save to phase state as `phases.explore.output`

8. Transition to `done`, begin Phase 2

#### Phase Output Format

```json
{
  "phase": "explore",
  "status": "complete",
  "output": {
    "initial_prompt_clarified": "...",
    "key_source_files": ["file:line", ...],
    "key_resource_files": ["ckfs/...", ...],
    "patterns_discovered": [...],
    "integration_points": [...],
    "uncertainties": [...],
    "agent_reports": {
      "conservative": {...},
      "aggressive": {...},
      "pragmatic": {...},
      "alternative": {...}
    }
  }
}
```

---

### Phase_2 ~ Clarify

#### Phase Outcome Goals

- A clear understanding of the target feature behavior
- Architecture/implementation direction resolved
- All ambiguities addressed

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `clarifying` | Iterative question-answer with user |
| `done` | All uncertainties resolved |

- Entry State: `clarifying`
- Exit State: `done`
- Failure State: `clarification_abandoned`

#### Phase Instructions

**State: clarifying**

1. Review codebase findings from Phase 1 and original feature request

2. Identify underspecified aspects:
   - Edge cases
   - Error handling
   - Integration points
   - Scope boundaries
   - Design preferences
   - Backward compatibility
   - Performance needs

3. **Present all questions to user** using AskUserQuestion in organized list

4. **Review answers and repeat** until uncertainty threshold is acceptable
   - If user says "whatever you think is best", provide recommendation and get explicit confirmation

5. Save all Q&A to phase state

**State: done**

6. Write a **FULLY QUALIFIED initial prompt** as phase output:
   - Original initial prompt
   - Annotated directly with code exploration output
   - All Q&A answers inline in the most relevant areas

7. Transition to Phase 3

#### Phase Output Format

```json
{
  "phase": "clarify",
  "status": "complete",
  "output": {
    "questions_asked": [...],
    "answers_received": [...],
    "clarifications": {...},
    "fully_qualified_initial_prompt": "..."
  }
}
```

---

### Phase_3 ~ Learn

#### Phase Outcome Goals

- Documented learnings in ECLAIR_BRAIN
- A clear mind to execute architecture (via context clear)
- Annotated initial prompt ready for architect phase

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `thinking` | Review everything from previous phases |
| `learning` | Save relevant concepts to brain |
| `planning` | Create annotated_initial_prompt output |
| `done` | Plan mode triggered, context cleared |

- Entry State: `thinking`
- Exit State: `done`
- Failure State: `learning_failed`

#### Phase Instructions

**State: thinking**

1. Review everything done in Phases 1-2

2. Identify concepts with relevance rating >85% that should be saved to brain
   - Also check for ORIGINALITY >85% (otherwise update existing brain bites)

3. Ask user using AskUserQuestion which learnings to save (similar list style to Clarify)

**State: learning**

4. Save approved learnings to `$GMCC_FAM_PATH/ECLAIR_BRAIN.md`:

   ```markdown
   ## Brain Bite: {Topic}

   **Date**: {timestamp}
   **Session**: {session_name}
   **Cross-Cutting Score**: {0-100}
   **Relevance Score**: {0-100}

   ### Finding
   {What was learned}

   ### Application
   {How it applies to future work}

   ### Evidence
   {File references, patterns}
   ```

**State: planning**

5. Create `annotated_initial_prompt` as phase output:
   - Grammatically correct version of initial prompt
   - Annotated inline with relevant:
     - Q&A responses
     - ECLAIR_BRAIN knowledge (including new learnings)
   - Ready to enter architecture phase

6. Save output to ECLAIR_STATE

**State: done**

7. **CRITICAL**: Trigger Claude's plan mode with ExitPlanMode
   - Plan content should summarize current ECLAIR state
   - This triggers context clearing
   - Include resume instructions pointing to ECLAIR_STATE file
   - Macro resumes from Phase 4 after context clear

#### Phase Output Format

```json
{
  "phase": "learn",
  "status": "complete",
  "output": {
    "brain_bites_added": [...],
    "brain_bites_updated": [...],
    "annotated_initial_prompt": "...",
    "context_cleared": true,
    "resume_from": "phase_4_architect"
  }
}
```

#### Context Clearing Mechanism

At end of Learn phase:

1. Write all state to ECLAIR_STATE_{session_name}.md
2. Enter plan mode via EnterPlanMode tool
3. Plan summarizes ECLAIR progress and next steps
4. ExitPlanMode triggers auto-clear + resume
5. On resume, read ECLAIR_STATE to restore context
6. Continue with Phase 4

---

### Phase_4 ~ Architect

#### Phase Outcome Goals

- A clear architecture plan for implementation
- Detailed list of desired behaviors / acceptance criteria
- Expected tests if any
- Files to create/modify with build sequence

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `exploring_architecture_options` | 4 divergent architect agents |
| `comparing_architecture` | Analyze differences, explore tradeoffs |
| `getting_signoff` | User approval of chosen approach |
| `done` | Architecture approved, ready to implement |

- Entry State: `exploring_architecture_options`
- Exit State: `done`
- Failure State: `architecture_rejected`

#### Phase Instructions

**State: exploring_architecture_options**

1. **Spawn architect agents based on mode**:

   **If mode == "full"** - Start 4 gmcc:agent:code_architect agents:

   | Agent | Methodology |
   |-------|-------------|
   | 1 | Conservative - Minimal changes, proven patterns |
   | 2 | Aggressive - Consider rewrites, new patterns |
   | 3 | Pragmatic - Balance effort and value |
   | 4 | Alternative - Unconventional approaches |

   **If mode == "lite"** - Start 1 gmcc:agent:code_architect with hybrid methodology:

   | Agent | Methodology |
   |-------|-------------|
   | 1 | Pragmatic+Alternative - Design balanced architecture that weighs effort vs benefit while exploring unconventional approaches. Consider team familiarity and proven patterns, but challenge assumptions where it adds value. |

2. Collect all architecture outputs, transition to `comparing_architecture`

**State: comparing_architecture**

3. **Compare architectures based on mode**:

   **If mode == "full"**:
   - Analyze architecture options, collect differences
   - Spin up 2 custom gmcc:agent:code_explorer agents to:
     - Explore how each architecture might affect the app differently
     - Build intuition on trade-offs
   - Spin up 1 custom Opus gmcc:agent:code_architect to:
     - Analyze all architectures + exploration results
     - Create final report with trade-offs matrix, recommendations, unexplored alternatives

   **If mode == "lite"**:
   - Review the single hybrid architecture
   - Self-analyze for gaps and trade-offs
   - No additional agents spawned (already balanced approach)

4. Transition to `getting_signoff`

**State: getting_signoff**

7. Enter mini-Clarify sub-phase:
   - Present architecture options to user
   - Use AskUserQuestion for preferences
   - Iterate until explicit user approval

8. **ALWAYS need explicit user approval** before proceeding

**State: done**

9. Save approved architecture to phase state
10. Transition to Phase 5

#### Phase Output Format

```json
{
  "phase": "architect",
  "status": "complete",
  "output": {
    "approaches_considered": {
      "conservative": {...},
      "aggressive": {...},
      "pragmatic": {...},
      "alternative": {...}
    },
    "synthesis_report": {...},
    "chosen_approach": "...",
    "user_approval": true,
    "files_to_create": [...],
    "files_to_modify": [...],
    "build_sequence": [...],
    "acceptance_criteria": [...],
    "expected_tests": [...]
  }
}
```

---

### Phase_5 ~ Implement

#### Phase Outcome Goals

- All implementation tasks complete
- Tests implemented (if required)
- Code validated through user feedback

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `initial_implementation` | Execute implementation plan |
| `test_augmentation` | Add/modify tests as needed |
| `validation` | User testing and bug fixes |
| `done` | Implementation complete |

- Entry State: `initial_implementation`
- Exit State: `done`
- Failure State: `implementation_blocked`

#### Phase Instructions

**State: initial_implementation**

1. Break out implementation plan into Tasks.md entries under ECLAIR section:
   ```markdown
   ### Implementation Tasks
   - [ ] Task 1 from build sequence
   - [ ] Task 2 from build sequence
   ...
   ```

2. Execute implementation tasks, checking off as complete

3. Transition to `test_augmentation`

**State: test_augmentation**

4. Spin up 1 custom haiku gmcc:agent:code_explorer to:
   - Detect if any relevant tests changed
   - Review if initial request included new test requirements

5. Implement test changes if any

6. Transition to `validation`

**State: validation**

7. Through back-and-forth with user:
   - Run automatic test execution
   - Gather user manual testing feedback
   - Bug fix as needed

8. Iterate until validation passes

**State: done**

9. Create summary output:
   - List of all changes made with file references
   - Summary of implementation journey

10. Transition to Phase 6

#### Phase Output Format

```json
{
  "phase": "implement",
  "status": "complete",
  "output": {
    "tasks_completed": [...],
    "files_created": [...],
    "files_modified": [...],
    "tests_added": [...],
    "tests_modified": [...],
    "validation_iterations": 2,
    "summary": "..."
  }
}
```

---

### Phase_6 ~ Review

#### Phase Outcome Goals

- Code we can be proud of
- Simple, DRY, elegant, easy to read, functionally correct
- Developer ergonomics prioritized
- Final learning capture if relevant

#### Phase States / Transitions

| State | Description |
|-------|-------------|
| `reviewing_implementation` | 4 methodology-seeded reviewers |
| `finishing_touches` | Address issues per user decision |
| `final_learnings` | Mini Learn phase if relevant |
| `done` | Review complete, ECLAIR session finished |

- Entry State: `reviewing_implementation`
- Exit State: `done`
- Failure State: `review_blocked`

#### Phase Instructions

**State: reviewing_implementation**

1. **Spawn review agents based on mode**:

   **If mode == "full"** - Start 4 gmcc:agent:code_quality_reviewer agents:

   | Agent | Methodology | Focus |
   |-------|-------------|-------|
   | 1 | Conservative | Stability, minimal risk |
   | 2 | Aggressive | Architecture improvements |
   | 3 | Pragmatic | Practical quality issues |
   | 4 | Alternative | Novel quality perspectives |

   **If mode == "lite"** - Start 1 gmcc:agent:code_quality_reviewer with hybrid methodology:

   | Agent | Methodology | Focus |
   |-------|-------------|-------|
   | 1 | Pragmatic+Alternative | Balanced review focusing on practical quality issues (bugs, conventions, readability) while considering novel perspectives and architectural improvements where high-value. |

2. Collect review findings

3. Transition to `finishing_touches`

**State: finishing_touches**

4. **Present findings to user** using AskUserQuestion:
   - "What would you like to do with these findings?"
   - Options: Fix now, Fix later, Proceed as-is

5. Implement desired changes based on user decision

6. Transition to `final_learnings`

**State: final_learnings**

7. Do mini Learn phase if relevant:
   - Any new patterns discovered during implementation?
   - Update ECLAIR_BRAIN if cross-cutting insights found

**State: done**

8. Finalize ECLAIR session

#### Phase Output Format

```json
{
  "phase": "review",
  "status": "complete",
  "output": {
    "review_findings": {
      "conservative": {...},
      "aggressive": {...},
      "pragmatic": {...},
      "alternative": {...}
    },
    "issues_fixed": [...],
    "issues_deferred": [...],
    "final_learnings_added": [...],
    "quality_assessment": "..."
  }
}
```

---

## State Files

### ECLAIR_STATE_{session_name}.md Template

```markdown
# ECLAIR State: {session_name}

**Created**: {timestamp}
**Branch**: {branch_name}
**Status**: initializing | phase_N | complete | failed
**Goal**: {initial prompt summary}

## Session Context

**Initial Prompt**:
{raw initial prompt}

**Relevant Brain Bites**:
{brain bites loaded at start}

## Phase Outputs

### phases.explore
```json
{output or null}
```

### phases.clarify
```json
{output or null}
```

### phases.learn
```json
{output or null}
```

### phases.architect
```json
{output or null}
```

### phases.implement
```json
{output or null}
```

### phases.review
```json
{output or null}
```

## Current Phase
- Phase: {N}
- State: {current_state}
- Started: {timestamp}

---
*Last Updated: {timestamp}*
```

### ECLAIR_BRAIN.md Template

```markdown
# ECLAIR Brain: {branch_name}

Cross-session learnings accumulated through ECLAIR macro executions.

**Note**: Brain bites remain in branch FAM until branch merge to main.

## Brain Bites

{brain bites sorted by relevance score descending}

---

## Sessions Contributing

| Session | Date | Bites Added |
|---------|------|-------------|
| {session_name} | {date} | {count} |

---
*Last Updated: {timestamp}*
```

---

## Error Handling

### Agent Spawn Failure

```markdown
If agent spawn fails:
1. Log failure to phase state
2. Retry with reduced agent count
3. If all spawns fail, transition to failure state
4. Present error to user with options:
   - Retry phase
   - Skip to next phase (if non-critical)
   - Abort ECLAIR session
```

### User Abandonment

```markdown
If user stops responding during Clarify:
1. Save current state to ECLAIR_STATE
2. Set status to "paused"
3. Create thought documenting pause point
4. Session can be resumed later via session_name
```

### Phase Failure

```markdown
If phase cannot complete:
1. Set phase status to "failed" with reason
2. Save partial outputs if any
3. Ask user: Retry, Skip, or Abort
4. Log decision to phase state
```

### Context Clear Recovery

```markdown
If context clear disrupts state:
1. ECLAIR_STATE file is source of truth
2. On resume, fully reload from state file
3. Verify phase outputs exist before proceeding
```

---

## Invocation Syntax

### Basic Invocation (FULL mode - default)

```
gmcc:macro:workflow:eclair(
  session_name: "feat_oauth_support",
  initial_prompt: "Add OAuth login support to the authentication system"
)
```

### LITE Mode Invocation

```
gmcc:macro:workflow:eclair(
  session_name: "task_fix_login_bug",
  initial_prompt: "Fix the login validation error on empty password",
  mode: "lite"
)
```

### Contextual Invocation

```markdown
Starting ECLAIR session for:

gmcc:macro:workflow:eclair()

# ECLAIR Session: feat_new_dashboard

## Initial Prompt
I need to build a new analytics dashboard that shows user engagement metrics.
The dashboard should integrate with our existing data pipeline and support
real-time updates.
```

### Resume Invocation

```
gmcc:macro:workflow:eclair(
  session_name: "feat_oauth_support",
  resume: true
)
```

The macro will read ECLAIR_STATE_{session_name}.md and continue from last checkpoint.

---

## Best Practices

1. **Session Naming**: Use descriptive snake_case names like `feat_oauth`, `fix_login_bug`, `refactor_auth_module`

2. **Brain Bite Quality**: Only save learnings with cross-cutting score >70 and relevance >85

3. **Clarify Thoroughly**: Don't rush through Phase 2. Better clarification = better architecture.

4. **Plan Mode Discipline**: The Learn phase context clear is intentional. Trust the annotated_initial_prompt.

5. **User Approval Gates**: Always get explicit approval in Architect phase. No assumptions.

6. **Task Granularity**: Break implementation into small, checkable tasks for visibility.

7. **Review Seriously**: Don't skip Phase 6. Developer ergonomics matter.
