---
name: gm_bot_team
description: Full agent team workflow. Uses true agent teams for exploration, architecture design, and code review. Maximum thoroughness for complex features requiring diverse perspectives.
argument-hint: <mem-name|index> <task/target/prompt>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot Team (Full Agent Teams)

You are executing the most thorough development workflow, leveraging true agent teams with independent Claude Code instances coordinated through shared task lists and mailboxes.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: initializing
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
/gm_bot_team 3 continue with the login endpoint
               ^index    ^prompt
```
1. Find `$GMCC_FAM_PATH/thoughts/mem_3_*/` directory
2. If not found: error "No memory set found with index 3"
3. Read `session_meta.md` to restore context
4. Determine resume phase from existing files:
   - Has `review_report.md` → resume at Phase 7 (Feedback)
   - Has `architecture_discussion_result.md` → resume at Phase 5 (Implement)
   - Has `fully_clarified_prompt.md` → resume at Phase 4 (Plan)
   - Has `relevant_implementation_report.md` → resume at Phase 3 (Clarify)
   - Otherwise → resume at Phase 2 (Implementation Overview)
5. The remaining arguments become the continuation prompt

### Case 2: First token is non-numeric (NEW mode)
```
/gm_bot_team auth-refactor implement OAuth2 flow
               ^mem_name    ^prompt
```
1. Scan `$GMCC_FAM_PATH/thoughts/` for existing `mem_*` directories
2. Find the highest numeric index (default 0 if none exist)
3. Create `$GMCC_FAM_PATH/thoughts/mem_{index+1}_{mem_name}/`
4. Write initial `session_meta.md`

### Case 3: No arguments
Use AskUserQuestion:
```
What feature would you like to build?

Provide a short name for this memory set and describe the task.
Example: auth-system implement full OAuth2 with Google and GitHub

- Enter description - Type your feature
```

---

## Memory Folder

### session_meta.md Template

Write to `$GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/session_meta.md`:

```markdown
# Memory Session: {mem_name}

**Index**: {index}
**Command**: /gm_bot_team
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

**Write state:** `{"task": "bot-team", "state": "initializing"}` to `.claude/GMB_STATE.json`

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
   - This summary will be passed to ALL agent teams

---

## Phase 2: Implementation Overview (Explore Team + Architecture Synthesizer)

**Write state:** `{"task": "bot-team", "state": "exploring"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: exploring
```

### Step 1: Launch Explore Agent Team (4 agents)

Launch 4 explore agents in parallel using the Task tool. Each agent receives the base explorer prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md` plus a unique methodology focus:

| Agent | Methodology | Exploration Focus |
|-------|-------------|-------------------|
| 1 | Conservative | Find existing patterns that can be reused. Identify code that should NOT change. Emphasize stability. |
| 2 | Aggressive | Find areas needing significant changes. Identify tech debt. Look for better abstractions. |
| 3 | Pragmatic | Focus on high-value exploration areas. Balance effort vs benefit. Consider team familiarity. |
| 4 | Alternative | Look for unconventional patterns. Challenge assumptions about current architecture. Explore edge cases. |

Each agent prompt should include:
```
{Contents of gmcc_agent_code_explorer.prompt.md}

## Task Context
**Exploration Target**: {initial prompt}
**Repository**: Explore from the current working directory
**Branch**: {ACTIVE_BRANCH}

## KBite Knowledge
{kbite context summary}

## Methodology Assignment: {Conservative|Aggressive|Pragmatic|Alternative}
{methodology-specific instructions from table above}

Commit FULLY to this methodology. Do not hedge or balance.

## Output
Return your complete exploration findings as a structured report.
Focus on: key files, patterns, integration points, dependencies, and uncertainties.
```

### Step 2: Architecture Synthesizer (1 agent)

After all 4 explore agents complete, spawn 1 architecture agent (gmcc:agent:code_architect) to synthesize:

```
Task tool:
  subagent_type: general-purpose
  prompt: |
    {Contents of gmcc_agent_code_architect.prompt.md}

    ## Synthesis Task

    You are synthesizing the findings of 4 exploration agents into a unified implementation report.

    ## Initial Prompt
    {initial prompt}

    ## Explorer 1 (Conservative) Findings:
    {output from agent 1}

    ## Explorer 2 (Aggressive) Findings:
    {output from agent 2}

    ## Explorer 3 (Pragmatic) Findings:
    {output from agent 3}

    ## Explorer 4 (Alternative) Findings:
    {output from agent 4}

    ## Output Requirements

    Write to: {mem_folder_path}/relevant_implementation_report.md

    Use this format:

    # Relevant Implementation Report

    ## Task Summary
    {what we're building, synthesized from all 4 perspectives}

    ## Key Files (Merged)
    | File | Relevance | Identified By | Notes |
    |------|-----------|---------------|-------|
    | {path} | {why} | {which agents} | {consensus or disagreement} |

    ## Patterns to Follow
    {synthesized patterns from all 4 agents}

    ## Integration Points
    {merged integration point recommendations}

    ## Architecture Preliminary Notes
    {early architecture insights from synthesis}

    ## Open Questions (Rated 1-8)
    Rate each question from 1 (minor uncertainty) to 8 (critical unknown):

    | Rating | Question | Context |
    |--------|----------|---------|
    | 8 | {most critical question} | {why it matters} |
    | 7 | {second most critical} | {context} |
    | ... | ... | ... |
    | 1 | {minor question} | {context} |

    ## Methodology Comparison
    ### Where Agents Agreed
    {consensus findings}
    ### Where Agents Diverged
    {points of disagreement and what they reveal}
    ### Recommended Direction
    {based on synthesis of all perspectives}
```

Verify `relevant_implementation_report.md` was written. Read it into context.

Update `session_meta.md` phase history.

---

## Phase 3: Clarify

**Write state:** `{"task": "bot-team", "state": "clarifying"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: clarifying
```

1. Read `relevant_implementation_report.md`
2. Extract the rated open questions (sorted by rating, highest first)
3. Present ALL uncertainties to the human using AskUserQuestion
   - Start with the highest-rated questions (8s and 7s)
   - Include lower-rated questions as well for completeness
   - Add any additional uncertainties discovered during synthesis

4. Write `fully_clarified_prompt.md` to the mem folder:

```markdown
# Fully Clarified Prompt

**Original Prompt**: {raw user prompt}
**Clarified**: {ISO timestamp}

## Clarifications (from rated questions)

### [Rating 8] Q: {question}
**A**: {answer}

### [Rating 7] Q: {question}
**A**: {answer}

{... all questions with answers ...}

## Refined Task Description
{The original prompt rewritten with all clarifications, exploration findings,
and implementation report insights integrated inline.
This is the single source of truth for what needs to be built.}

## Key Files (from implementation report)
- {file1}: {relevance}
- {file2}: {relevance}

## Patterns to Follow
- {pattern 1}
- {pattern 2}

## Constraints and Decisions
- {constraint/decision 1}
- {constraint/decision 2}
```

---

## Phase 4: Plan (Architecture Team + Coordinator)

**Write state:** `{"task": "bot-team", "state": "planning"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: planning
```

### Step 1: Launch Architecture Agent Team (4 agents)

Launch 4 architecture agents in parallel. Each receives the base architect prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md` plus methodology assignment:

| Agent | Methodology | Architecture Approach |
|-------|-------------|----------------------|
| 1 | Conservative | Smallest possible change. Maximum reuse. No new dependencies. Proven patterns only. |
| 2 | Aggressive | Consider complete rewrites. Introduce new patterns. Build for extensibility. Tech debt paydown. |
| 3 | Pragmatic | Weigh effort vs benefit. New code where it adds clear value. Optimize readability. |
| 4 | Alternative | Challenge all assumptions. Consider different technologies. What would this look like fresh? |

Each agent prompt should include:
```
{Contents of gmcc_agent_code_architect.prompt.md}

## Architecture Context
**Goal**: {refined task description from fully_clarified_prompt.md}

## Fully Clarified Prompt
{Contents of fully_clarified_prompt.md}

## Relevant Implementation Report
{Contents of relevant_implementation_report.md}

## KBite Knowledge
{kbite context summary}

## Methodology Assignment: {Conservative|Aggressive|Pragmatic|Alternative}
{methodology-specific instructions from table above}

Commit FULLY to this methodology. Do not hedge or try to balance.
The coordinator will handle synthesis.

## Output
Return your complete architecture proposal using the Code Architect Report format.
Include: components, data flow, files to modify/create, build sequence, trade-offs.
```

### Step 2: Architecture Coordinator (1 agent)

After all 4 architects complete, spawn 1 coordinator agent:

```
Task tool:
  subagent_type: general-purpose
  model: opus
  prompt: |
    You are the architecture coordinator for a GM-CDE bot team session.

    Your job is to synthesize 4 divergent architecture proposals into a unified,
    actionable implementation plan.

    ## Task
    {refined task description from fully_clarified_prompt.md}

    ## Architect 1 (Conservative) Proposal:
    {output from agent 1}

    ## Architect 2 (Aggressive) Proposal:
    {output from agent 2}

    ## Architect 3 (Pragmatic) Proposal:
    {output from agent 3}

    ## Architect 4 (Alternative) Proposal:
    {output from agent 4}

    ## Coordination Instructions

    1. Identify where all 4 architects agree (high confidence decisions)
    2. Identify where they diverge (requires trade-off analysis)
    3. For each divergence, analyze the trade-offs and make a clear recommendation
    4. If any critical question remains unresolved, flag it for user clarification
    5. Produce the final unified architecture

    ## Output Requirements

    Write to: {mem_folder_path}/architecture_discussion_result.md

    Use this format:

    # Architecture Discussion Result

    ## Consensus Points
    {where all 4 architects agreed}

    ## Divergence Analysis
    ### Divergence: {topic}
    - **Conservative**: {position}
    - **Aggressive**: {position}
    - **Pragmatic**: {position}
    - **Alternative**: {position}
    - **Resolution**: {chosen approach and why}

    ## Final Architecture

    ### Approach Summary
    {2-3 sentence summary of the unified approach}

    ### Component Specifications
    #### {Component Name}
    - **Responsibility**: {what it does}
    - **Interface**: {key methods/properties}
    - **Location**: {file path}

    ### Files to Modify
    | File | Changes | Reason |
    |------|---------|--------|

    ### Files to Create
    | File | Purpose | Key Contents |
    |------|---------|--------------|

    ### Build Sequence
    1. {step} - {rationale}
    2. {step} - {rationale}

    ### Acceptance Criteria
    - {criterion 1}
    - {criterion 2}

    ### Trade-off Summary
    | Decision | Chosen | Rejected | Rationale |
    |----------|--------|----------|-----------|

    ## Unresolved Questions (if any)
    {Questions that need user clarification before implementation can proceed}

    ## Risk Assessment
    | Risk | Likelihood | Impact | Mitigation |
    |------|------------|--------|------------|
```

Verify `architecture_discussion_result.md` was written. Read it.

### Step 3: Handle Unresolved Questions

If the coordinator flagged unresolved questions:
1. Present them to the user using AskUserQuestion
2. Update `architecture_discussion_result.md` with the answers
3. Adjust the architecture if answers change the design

### Step 4: User Approval

Present the final architecture to the user:

Use AskUserQuestion:
```
Architecture team discussion complete.

{Brief summary from architecture_discussion_result.md}

Key decisions:
- {decision 1}
- {decision 2}

How would you like to proceed?
- Approve and implement - Start building
- Modify - I have changes
- Redesign - Run architecture team again with different constraints
```

Update `session_meta.md` phase history.

---

## Phase 5: Implement

**Write state:** `{"task": "bot-team", "state": "implementing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: implementing
```

Implementation receives full context from mem artifacts:

1. Read `fully_clarified_prompt.md` - the refined task description
2. Read `relevant_implementation_report.md` - the exploration findings
3. Read `architecture_discussion_result.md` - the approved architecture

4. Follow the build sequence from the architecture document
5. Write code changes
6. Track progress in `session_meta.md` phase history

---

## Phase 6: Review (Review Team)

**Write state:** `{"task": "bot-team", "state": "reviewing"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: reviewing
```

### Launch Review Agent Team (4 agents)

Launch 4 review agents in parallel. Each receives the base reviewer prompt from `$GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md` plus methodology assignment:

| Agent | Methodology | Review Focus |
|-------|-------------|--------------|
| 1 | Conservative | Stability, risk, what could break. Flag deviations from existing patterns. |
| 2 | Aggressive | Architecture improvements, missed opportunities, better abstractions. |
| 3 | Pragmatic | Practical quality issues - bugs, conventions, readability, maintainability. |
| 4 | Alternative | Fresh perspective - question patterns, suggest novel improvements. |

Each agent prompt should include:
```
{Contents of gmcc_agent_code_quality_reviewer.prompt.md}

## Review Context

**Task**: {refined task description}

## Fully Clarified Prompt
{Contents of fully_clarified_prompt.md}

## Architecture Discussion Result
{Contents of architecture_discussion_result.md}

## Files Changed
{List of files created or modified during implementation}

## Methodology Assignment: {Conservative|Aggressive|Pragmatic|Alternative}
{methodology-specific instructions from table above}

## Output
Return your complete review using the Code Quality Review Report format.
```

### Synthesize Reviews

After all 4 review agents complete, synthesize findings in primary context:

1. Merge findings, de-duplicate issues found by multiple agents
2. Prioritize by severity (Critical > High > Medium > Low)
3. Write `review_report.md` to mem folder:

```markdown
# Review Report (Team Synthesis)

## Summary
| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Security | {n} | {n} | {n} | {n} |
| Bugs | {n} | {n} | {n} | {n} |
| Quality | {n} | {n} | {n} | {n} |

## Overall Assessment
{Pass / Pass with Issues / Needs Revision}

## Issues (by severity)
{merged and de-duplicated issues from all 4 reviewers}

## Agent Agreement
### Unanimous Findings (all 4 agree)
{highest confidence issues}

### Majority Findings (3+ agree)
{high confidence issues}

### Single Agent Findings
{lower confidence - only 1 reviewer flagged}

## Positive Observations
{good patterns observed by reviewers}
```

Present findings to user:
Use AskUserQuestion:
```
Review team complete. {summary}

How would you like to handle findings?
- Fix all issues - Address everything
- Fix critical and high - Skip medium/low
- Proceed as-is - Accept current implementation
```

Implement requested fixes.

---

## Phase 7: Feedback Integration

1. Present complete summary:
   - What was built
   - Architecture decisions (from discussion result)
   - Review findings addressed
   - Files created/modified
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

Bot Team Complete: {mem_name}

**Memory**: thoughts/mem_{index}_{mem_name}/
**Artifacts**:
- relevant_implementation_report.md (4 explorers + synthesizer)
- fully_clarified_prompt.md
- architecture_discussion_result.md (4 architects + coordinator)
- review_report.md (4 reviewers synthesized)

**Files Modified**: {count}
**Review Status**: {pass/pass with issues}
**Agent Teams Used**: 3 (explore, architecture, review)

**Next**: Run /gm_fam_sync to update FAM, or /gm_merge_branch when ready.
```

---

## Error Handling

**Agent team spawn failure:**
```
[GMB] Agent team spawn failed for {phase}

Falling back to subagent mode (single agent per phase).
```
Fall back to the /gm_bot_rpi pattern for that phase.

**Session paused:**
```
Session state preserved at: $GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/

To resume: /gm_bot_team {index} <continuation prompt>
```

**Coordinator flags critical unresolved questions:**
Present to user immediately via AskUserQuestion before proceeding.
