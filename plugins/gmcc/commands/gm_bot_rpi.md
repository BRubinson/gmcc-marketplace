---
name: gm_bot_rpi
description: Subagent-based Research/Plan/Implement workflow. Spawns specialized GMCC agents for exploration, architecture, and code review while keeping clarification and implementation in primary context.
argument-hint: <mem-name|index> <task/target/prompt>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement)

You are executing an enhanced development workflow that leverages GMCC subagents for Research, Planning, and Review phases.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: initializing
```

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify GM-CDE is initialized (`$GMCC_REPO_PATH` exists)
2. Get current git branch -> `{ACTIVE_BRANCH}`
3. Load current FAM context from `$GMCC_FAM_PATH/`:
   - Read Purpose.md
   - Read Tasks.md

If ckfs missing:
```
[GMB] GM-CDE not initialized. Run /gm_init first.
```

---

## Argument Parsing

Parse `$ARGUMENTS`:

### Case 1: First token is numeric (RESUME mode)
```
/gm_bot_rpi 3 continue with the login endpoint
              ^index    ^prompt
```
1. Find `$GMCC_FAM_PATH/thoughts/mem_3_*/` directory
2. If not found: error "No memory set found with index 3"
3. Read `session_meta.md` to restore context
4. Determine resume phase from existing files:
   - Has `review_report.md` → resume at Phase 7 (Feedback)
   - Has `architecture_document.md` → resume at Phase 5 (Implement)
   - Has `fully_clarified_prompt.md` → resume at Phase 4 (Plan)
   - Has `exploration_report.md` → resume at Phase 3 (Clarify)
   - Otherwise → resume at Phase 2 (Implementation Overview)
5. The remaining arguments become the continuation prompt

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot_rpi auth-refactor implement OAuth2 flow
              ^mem_name    ^prompt
```
1. Scan `$GMCC_FAM_PATH/thoughts/` for existing `mem_*` directories
2. Find the highest numeric index (default 0 if none exist)
3. Create `$GMCC_FAM_PATH/thoughts/mem_{index+1}_{mem_name}/`
4. Write initial `session_meta.md`

### Case 3: No arguments
Use AskUserQuestion:
```
What would you like to work on?

Provide a short name for this memory set and describe the task.
Example: auth-refactor implement OAuth2 flow

- Enter description - Type your task
```

---

## Memory Folder

### session_meta.md Template

Write to `$GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/session_meta.md`:

```markdown
# Memory Session: {mem_name}

**Index**: {index}
**Command**: /gm_bot_rpi
**Created**: {ISO timestamp}
**Branch**: {ACTIVE_BRANCH}
**Status**: active

## Initial Prompt
{raw user prompt}

## KBites Loaded
{list of kbite names, or "none"}

## KBite Content Summary
{Brief summary of loaded kbite content for agent context passing}

## Phase History
- {timestamp}: Session created
```

---

## Phase 1: KBite Index Loading (New Memory Only)

**Skip this phase if resuming an existing memory set.**

**Write state:** `{"task": "bot-rpi", "state": "initializing"}` to `.claude/GMB_STATE.json`

1. List available kbites from `$GMCC_CKFS_ROOT/kbites/`:
   - For each kbite directory, read `KBITE_PURPOSE.md` for a one-line summary

2. Use AskUserQuestion (multiSelect: true):
```
Which kbites are relevant to this task?

Available kbites:
- {kbite_1}: {purpose summary}
- {kbite_2}: {purpose summary}
- None - proceed without kbite context
```

3. For each selected kbite:
   - Read `KBITE_INDEX.md` for the resource list
   - Read `KBITE_TRIGGER_MAP.md` for relevant resource mapping
   - Load the top 3-5 highest-relevance chewed files
   - Compile a **kbite context summary** (key learnings, takeaways, patterns)

4. Store kbite summary in `session_meta.md` under "KBite Content Summary"
   - This summary will be passed into ALL subsequent agent prompts

---

## Phase 2: Implementation Overview (Explore Agent)

**Write state:** `{"task": "bot-rpi", "state": "exploring"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: exploring
```

Spawn 1 explore subagent using the Task tool:

### Agent: gmcc:agent:code_explorer

Read the agent prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md` and construct the full Task prompt:

```
Task tool:
  subagent_type: general-purpose
  prompt: |
    {Contents of gmcc_agent_code_explorer.prompt.md}

    ## Task Context

    **Exploration Target**: {initial prompt}
    **Repository**: {GMCC_REPO_PATH}
    **Branch**: {ACTIVE_BRANCH}

    ## KBite Knowledge
    {kbite context summary from session_meta.md}

    ## Exploration Approach

    Apply all 4 methodologies sequentially:

    1. **Conservative**: Find existing patterns that can be reused directly
    2. **Aggressive**: Identify areas that might need significant changes
    3. **Pragmatic**: Balance effort/value in exploration scope
    4. **Alternative**: Look for unconventional integration points

    ## Output Requirements

    Write your complete exploration report to: {mem_folder_path}/exploration_report.md

    Use this format:

    # Exploration Report

    ## Target
    {what was explored}

    ## Key Files
    | File | Relevance | Must Read |
    |------|-----------|-----------|
    | {path} | {why} | {yes/no} |

    ## Patterns Discovered
    {patterns found across all 4 methodology passes}

    ## Integration Points
    {where new code should connect}

    ## Dependencies
    {what depends on what}

    ## Uncertainties
    {questions that couldn't be answered from code alone}

    ## Methodology Insights
    ### Conservative Findings
    {patterns to preserve}
    ### Aggressive Findings
    {areas ripe for improvement}
    ### Pragmatic Findings
    {high-value focus areas}
    ### Alternative Findings
    {unconventional approaches worth considering}
```

After the agent completes, verify `exploration_report.md` was written. Read it into context.

Update `session_meta.md` phase history.

---

## Phase 3: Clarify

**Write state:** `{"task": "bot-rpi", "state": "clarifying"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: clarifying
```

1. Review the exploration report for uncertainties and ambiguities

2. Use AskUserQuestion to resolve all identified issues:
   - Uncertainties from the exploration report
   - Edge cases and error handling
   - Integration preferences
   - Scope boundaries

3. Write `fully_clarified_prompt.md` to the mem folder:

```markdown
# Fully Clarified Prompt

**Original Prompt**: {raw user prompt}
**Clarified**: {ISO timestamp}

## Clarifications

### Q: {question 1}
**A**: {answer 1}

### Q: {question 2}
**A**: {answer 2}

## Refined Task Description
{The original prompt rewritten with all clarifications and exploration findings
integrated inline. This is the single source of truth for what needs to be built.}

## Key Files (from exploration)
- {file1}: {relevance}
- {file2}: {relevance}

## Patterns to Follow
- {pattern 1 from exploration}
- {pattern 2}

## Constraints
- {constraint 1}
- {constraint 2}
```

---

## Phase 4: Plan (Architecture Agent)

**Write state:** `{"task": "bot-rpi", "state": "planning"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: planning
```

Spawn 1 architecture subagent using the Task tool:

### Agent: gmcc:agent:code_architect

Read the agent prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md` and construct the full Task prompt:

```
Task tool:
  subagent_type: general-purpose
  prompt: |
    {Contents of gmcc_agent_code_architect.prompt.md}

    ## Architecture Context

    **Goal**: {refined task description from fully_clarified_prompt.md}

    ## Fully Clarified Prompt
    {Contents of fully_clarified_prompt.md}

    ## Exploration Report
    {Contents of exploration_report.md}

    ## KBite Knowledge
    {kbite context summary}

    ## Architecture Approach

    Apply all 4 methodologies and synthesize:
    1. **Conservative**: Minimal changes, proven patterns
    2. **Aggressive**: Consider rewrites and new patterns
    3. **Pragmatic**: Balance effort and value
    4. **Alternative**: Unconventional but valuable approaches

    Then synthesize the best elements from each into a unified architecture.

    ## Output Requirements

    Write your architecture document to: {mem_folder_path}/architecture_document.md

    Use this format:

    # Architecture Document

    ## Goal
    {what is being designed}

    ## Approach Summary
    {2-3 sentence summary}

    ## Component Specifications
    ### {Component Name}
    - **Responsibility**: {what it does}
    - **Interface**: {key methods/properties}
    - **Location**: {file path}

    ## Files to Modify
    | File | Changes | Reason |
    |------|---------|--------|
    | {path} | {what changes} | {why} |

    ## Files to Create
    | File | Purpose | Key Contents |
    |------|---------|--------------|
    | {path} | {responsibility} | {main exports} |

    ## Build Sequence
    1. {step 1} - {why first}
    2. {step 2} - {dependencies}

    ## Acceptance Criteria
    - {criterion 1}
    - {criterion 2}

    ## Trade-offs
    **Pros**: {advantages}
    **Cons**: {limitations}

    ## Methodology Analysis
    ### Conservative Approach
    {what it would look like}
    ### Aggressive Approach
    {what it would look like}
    ### Pragmatic Approach
    {what it would look like}
    ### Alternative Approach
    {what it would look like}
    ### Synthesis Rationale
    {why the final design was chosen}
```

After the agent completes, verify `architecture_document.md` was written.

Present the architecture to the user for approval before proceeding:

Use AskUserQuestion:
```
Architecture design complete. Review the plan:

{Brief summary of the architecture from architecture_document.md}

How would you like to proceed?
- Approve and implement - Start building
- Modify - I have changes to the architecture
- Reject and redesign - Start architecture over
```

Update `session_meta.md` phase history.

---

## Phase 5: Implement

**Write state:** `{"task": "bot-rpi", "state": "implementing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: implementing
```

1. Read `architecture_document.md` for the implementation plan
2. Follow the build sequence
3. Write code changes
4. Track progress in `session_meta.md` phase history

---

## Phase 6: Review (Code Review Agent)

**Write state:** `{"task": "bot-rpi", "state": "reviewing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-rpi | STATE: reviewing
```

Spawn 1 review subagent using the Task tool:

### Agent: gmcc:agent:code_quality_reviewer

Read the agent prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md` and construct the full Task prompt:

```
Task tool:
  subagent_type: general-purpose
  prompt: |
    {Contents of gmcc_agent_code_quality_reviewer.prompt.md}

    ## Review Context

    **Task**: {refined task description}

    ## Fully Clarified Prompt
    {Contents of fully_clarified_prompt.md}

    ## Architecture Document
    {Contents of architecture_document.md}

    ## Files Changed
    {List of files that were created or modified during implementation}

    ## Review Instructions

    1. Read each changed file
    2. Validate against the architecture document and acceptance criteria
    3. Check for bugs, security issues, and quality problems
    4. Verify conventions are followed

    ## Output Requirements

    Write your review report to: {mem_folder_path}/review_report.md

    Use the standard Code Quality Review Report format from your prompt.
```

After the agent completes, read `review_report.md`.

Present findings to the user:
Use AskUserQuestion:
```
Code review complete. {summary of findings}

How would you like to handle the review findings?
- Fix all issues - Address everything the reviewer found
- Fix critical only - Only fix critical and high-priority issues
- Proceed as-is - Accept the current implementation
```

Implement requested fixes.

---

## Phase 7: Feedback Integration

**Write state:** `{"task": "bot-rpi", "state": "reviewing"}` to `.claude/GMB_STATE.json`

1. Present a complete summary:
   - What was built (from architecture_document.md)
   - Files created/modified
   - Review findings addressed
   - Any known limitations

2. Wait for user feedback

3. Iterate on feedback until satisfied

4. On completion:

**Write state:** `{"task": "none", "state": "idle"}` to `.claude/GMB_STATE.json`

Update `session_meta.md`:
- Set Status to `completed`
- Add final phase history entry

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: none | STATE: idle

Bot RPI Complete: {mem_name}

**Memory**: thoughts/mem_{index}_{mem_name}/
**Artifacts**:
- exploration_report.md
- fully_clarified_prompt.md
- architecture_document.md
- review_report.md

**Files Modified**: {count}
**Review Status**: {pass/pass with issues}

**Next**: Run /gm_fam_sync to update FAM, or continue with more tasks.
```

---

## Error Handling

**Agent spawn failure:**
```
[GMB] Agent spawn failed for {phase}

Falling back to primary context for this phase.
```
Continue the phase in primary context as a fallback.

**Session paused:**
```
Session state preserved at: $GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/

To resume: /gm_bot_rpi {index} <continuation prompt>
```

**Task grows in scope:**
Use AskUserQuestion:
```
This task may benefit from full agent team treatment.

Would you like to upgrade?
- Continue as /gm_bot_rpi - Keep subagent workflow
- Switch to /gm_bot_team - Full agent team treatment
```
