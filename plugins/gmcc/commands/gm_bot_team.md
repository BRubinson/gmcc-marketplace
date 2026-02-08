---
name: gm_bot_team
description: Full agent team workflow. Uses Claude Code Agent Teams (experimental) for exploration, architecture design, and code review. Maximum thoroughness for complex features requiring diverse perspectives.
argument-hint: <mem-name|index> <task/target/prompt>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot Team (Agent Teams)

<!-- [FIX #15] Rewritten to use actual Claude Code Agent Teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS).
     Previous version used Task tool subagents (4 per phase). New version spawns real teammates -
     independent Claude Code instances with their own context windows, coordinated via shared
     task list and mailbox messaging. This enables true parallel work and cross-agent discussion.

     Key differences from /gm_bot_rpi (subagent workflow):
     - Teammates are full Claude Code sessions, not subagents
     - Teammates can message each other directly (not just report back to lead)
     - Shared task list enables self-coordination
     - Lead can enter delegate mode (Shift+Tab) to focus on coordination
     - Higher token cost but deeper analysis from independent perspectives -->

You are the **team lead** executing the most thorough development workflow, leveraging Claude Code Agent Teams with independent teammate instances coordinated through shared task lists and mailbox messaging.

## Status Bar
```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: initializing
```

---

## Prerequisites: Agent Teams Must Be Enabled

<!-- [FIX #15] Include instructions to enable agent teams as the user requested -->

**Agent Teams is an experimental feature.** Before running this workflow, the user must enable it.

Check if agent teams are available. If teammate spawning fails, output:

```
[GMB] ERROR: Agent Teams not enabled

Agent Teams is required for /gm_bot_team. Enable it by ONE of:

1. Environment variable (session):
   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

2. Claude Code settings (~/.claude/settings.json):
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     }
   }

3. Project settings (.claude/settings.json in repo root):
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     }
   }

After enabling, restart Claude Code and run /gm_bot_team again.

Alternative: Use /gm_bot_rpi for subagent-based workflow (no experimental features required).
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
   - Has `review_report.md` -> resume at Phase 7 (Feedback)
   - Has `architecture_discussion_result.md` -> resume at Phase 5 (Implement)
   - Has `fully_clarified_prompt.md` -> resume at Phase 4 (Plan)
   - Has `relevant_implementation_report.md` -> resume at Phase 3 (Clarify)
   - Otherwise -> resume at Phase 2 (Implementation Overview)
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
   - This summary will be passed to ALL teammate spawn prompts

---

## Phase 2: Implementation Overview (Explore Team)

**Write state:** `{"task": "bot-team", "state": "exploring"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: exploring
```

<!-- [FIX #15] Uses actual agent teams instead of Task tool subagents.
     [FIX #7] Teammates read their own prompt files (each has its own context window).
     [FIX #6] Slim spawn prompts - teammates load full identity from prompt file. -->

### Step 1: Create the Explore Team

Create an agent team named `gmb-explore-{mem_name}` with 4 teammates. Each teammate is an independent Claude Code session that will explore the codebase from a different methodology perspective.

Spawn **4 explore teammates** with these prompts:

#### Teammate: explore-conservative
```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

## Task Context
**Exploration Target**: {initial prompt}
**Repository**: Explore from the current working directory
**Branch**: {ACTIVE_BRANCH}

## KBite Knowledge
{kbite context summary from session_meta.md}

## Methodology Assignment: Conservative
Find existing patterns that can be reused directly. Identify code that should NOT change.
Emphasize stability. Look for minimal integration points.
Commit FULLY to this methodology. Do not hedge or balance.

## Output
Write your exploration report to: {mem_folder_path}/explore_conservative.md
Use the Code Explorer Report format from your prompt file.
```

#### Teammate: explore-aggressive
```
(Same structure, methodology: Aggressive)
Find areas needing significant changes. Identify tech debt. Look for better abstractions.
Consider broader architectural changes.
Write to: {mem_folder_path}/explore_aggressive.md
```

#### Teammate: explore-pragmatic
```
(Same structure, methodology: Pragmatic)
Focus on high-value exploration areas. Balance effort vs benefit.
Consider team familiarity and maintenance cost.
Write to: {mem_folder_path}/explore_pragmatic.md
```

#### Teammate: explore-alternative
```
(Same structure, methodology: Alternative)
Look for unconventional patterns. Challenge assumptions about current architecture.
Explore edge cases and unusual code paths.
Write to: {mem_folder_path}/explore_alternative.md
```

**Important**: Each teammate writes to a **different file** to avoid conflicts. Teammates work fully in parallel.

### Step 2: Wait for Explore Team

Wait for all 4 explore teammates to complete their work. Monitor via the shared task list.

### Step 3: Clean Up Explore Team

Once all 4 reports are written, clean up the explore team.

### Step 4: Synthesize Exploration (Primary Context)

<!-- [FIX #15] Synthesis runs in primary context instead of spawning a 5th agent.
     The lead has all 4 reports available and can synthesize directly.
     This saves a teammate spawn and keeps synthesis in the coordinating context. -->

Read all 4 exploration reports and synthesize into a unified implementation report:

1. Read `explore_conservative.md`, `explore_aggressive.md`, `explore_pragmatic.md`, `explore_alternative.md`
2. Merge key files, patterns, integration points, and dependencies
3. Identify where agents agreed (high confidence) vs diverged (needs discussion)
4. Write `relevant_implementation_report.md` to the mem folder:

```markdown
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

## Methodology Comparison
### Where Agents Agreed
{consensus findings}
### Where Agents Diverged
{points of disagreement and what they reveal}
### Recommended Direction
{based on synthesis of all perspectives}
```

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

## Phase 4: Plan (Architecture Team)

**Write state:** `{"task": "bot-team", "state": "planning"}` to `.claude/GMB_STATE.json`

```
[GMB] MODE: GM-CDE | BRANCH: {ACTIVE_BRANCH} | TASK: bot-team | STATE: planning
```

<!-- [FIX #15] Architecture team uses real agent teams.
     [FIX #16] Architect teammates use opus model for complex reasoning (opusplan pattern).
     [FIX #7] Teammates read their own prompt files. -->

### Step 1: Create the Architecture Team

Create an agent team named `gmb-arch-{mem_name}` with 4 teammates. Each should use the **opus** model for deep architectural reasoning.

Spawn **4 architect teammates** with these prompts:

#### Teammate: arch-conservative
```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

## Architecture Context
**Goal**: {refined task description from fully_clarified_prompt.md}

## Fully Clarified Prompt
{Contents of fully_clarified_prompt.md}

## Relevant Implementation Report
{Contents of relevant_implementation_report.md}

## KBite Knowledge
{kbite context summary}

## Methodology Assignment: Conservative
Smallest possible change to achieve goal. Maximum reuse of existing code and patterns.
No new dependencies. Proven patterns only. Optimize for stability and predictability.
Commit FULLY to this methodology. The coordinator will handle synthesis.

## Output
Write your architecture proposal to: {mem_folder_path}/arch_conservative.md
Use the Code Architect Report format from your prompt file.
Include: components, data flow, files to modify/create, build sequence, trade-offs.
```

#### Teammate: arch-aggressive
```
(Same structure, methodology: Aggressive)
Consider complete rewrites if they improve architecture. Introduce new patterns.
Build for extensibility. Tech debt paydown is a feature.
Write to: {mem_folder_path}/arch_aggressive.md
```

#### Teammate: arch-pragmatic
```
(Same structure, methodology: Pragmatic)
Weigh effort vs benefit explicitly. New code where it adds clear value.
Optimize for readability and maintainability.
Write to: {mem_folder_path}/arch_pragmatic.md
```

#### Teammate: arch-alternative
```
(Same structure, methodology: Alternative)
Challenge all assumptions. Consider different technologies/frameworks.
What would this look like if we started fresh? Innovation over convention.
Write to: {mem_folder_path}/arch_alternative.md
```

**Important**: Each teammate writes to a **different file** to avoid conflicts.

### Step 2: Wait for Architecture Team

Wait for all 4 architect teammates to complete. Monitor via shared task list.

### Step 3: Clean Up Architecture Team

Once all 4 proposals are written, clean up the architecture team.

### Step 4: Coordinate Architecture (Primary Context)

<!-- [FIX #15] Coordination runs in primary context for the same reason as exploration synthesis.
     The lead reads all 4 proposals and synthesizes the final architecture. -->

Read all 4 architecture proposals and synthesize:

1. Read `arch_conservative.md`, `arch_aggressive.md`, `arch_pragmatic.md`, `arch_alternative.md`
2. Identify consensus points (all 4 agree) vs divergences
3. For each divergence, analyze trade-offs and make a clear recommendation
4. Write `architecture_discussion_result.md` to the mem folder:

```markdown
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

### Step 5: Handle Unresolved Questions

If the coordination flagged unresolved questions:
1. Present them to the user using AskUserQuestion
2. Update `architecture_discussion_result.md` with the answers
3. Adjust the architecture if answers change the design

### Step 6: User Approval

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

Implementation runs in primary context with full mem artifacts:

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

<!-- [FIX #15] Review team uses real agent teams.
     [FIX #16] Review teammates use sonnet (cost-effective for code analysis).
     [FIX #7] Teammates read their own prompt files. -->

### Step 1: Create the Review Team

Create an agent team named `gmb-review-{mem_name}` with 4 teammates. Each should use the **sonnet** model for cost-effective review.

Spawn **4 review teammates** with these prompts:

#### Teammate: review-conservative
```
Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

## Review Context
**Task**: {refined task description}

## Fully Clarified Prompt
{Contents of fully_clarified_prompt.md}

## Architecture Discussion Result
{Contents of architecture_discussion_result.md}

## Files Changed
{List of files created or modified during implementation}

## Methodology Assignment: Conservative
Strict review. Flag deviations from existing patterns. Prioritize stability.
Recommend against risky changes. Focus on what could break.

## Output
Write your review to: {mem_folder_path}/review_conservative.md
Use the Code Quality Review Report format from your prompt file.
```

#### Teammate: review-aggressive
```
(Same structure, methodology: Aggressive)
Improvement-focused. Identify opportunities to make code better.
Recommend refactoring where beneficial. Focus on what could be improved.
Write to: {mem_folder_path}/review_aggressive.md
```

#### Teammate: review-pragmatic
```
(Same structure, methodology: Pragmatic)
Balanced review. Flag real issues, suggest improvements.
Weigh risk vs benefit. Focus on what matters most.
Write to: {mem_folder_path}/review_pragmatic.md
```

#### Teammate: review-alternative
```
(Same structure, methodology: Alternative)
Fresh perspective. Question established patterns.
Consider if there are better approaches. Focus on what could be different.
Write to: {mem_folder_path}/review_alternative.md
```

### Step 2: Wait for Review Team

Wait for all 4 review teammates to complete. Monitor via shared task list.

### Step 3: Clean Up Review Team

Once all 4 reviews are written, clean up the review team.

### Step 4: Synthesize Reviews (Primary Context)

Read all 4 review reports and synthesize:

1. Read `review_conservative.md`, `review_aggressive.md`, `review_pragmatic.md`, `review_alternative.md`
2. Merge findings, de-duplicate issues found by multiple reviewers
3. Prioritize by severity (Critical > High > Medium > Low)
4. Write `review_report.md` to mem folder:

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
- explore_{conservative,aggressive,pragmatic,alternative}.md (4 teammate reports)
- relevant_implementation_report.md (synthesized exploration)
- fully_clarified_prompt.md
- arch_{conservative,aggressive,pragmatic,alternative}.md (4 teammate proposals)
- architecture_discussion_result.md (synthesized architecture)
- review_{conservative,aggressive,pragmatic,alternative}.md (4 teammate reviews)
- review_report.md (synthesized review)

**Files Modified**: {count}
**Review Status**: {pass/pass with issues}
**Agent Teams Used**: 3 (explore, architecture, review) x 4 teammates each

**Next**: Run /gm_fam_sync to update FAM, or /gm_merge_branch when ready.
```

---

## Error Handling

**Agent teams not available (feature not enabled):**
```
[GMB] Agent Teams not available. See Prerequisites section above.

Falling back to /gm_bot_rpi subagent workflow.
```
Execute the equivalent phase using the /gm_bot_rpi pattern (single subagent per phase).

**Teammate spawn failure:**
```
[GMB] Teammate spawn failed for {teammate_name} in {phase}

Continuing with remaining teammates. Will note gap in synthesis.
```
Continue with available teammates. Note the missing perspective in synthesis.

**All teammates fail for a phase:**
```
[GMB] All teammate spawns failed for {phase}

Falling back to subagent mode (single agent per phase).
```
Fall back to the /gm_bot_rpi pattern for that phase.

**Session paused:**
```
Session state preserved at: $GMCC_FAM_PATH/thoughts/mem_{index}_{mem_name}/

To resume: /gm_bot_team {index} <continuation prompt>

Note: Agent teams do not persist across session restarts.
Teammate reports written to the mem folder will be available for synthesis on resume.
```

**Coordinator flags critical unresolved questions:**
Present to user immediately via AskUserQuestion before proceeding.

**File conflict between teammates:**
Each teammate writes to uniquely named files ({phase}_{methodology}.md). If a conflict is detected, prefer the most recent write and note the conflict in synthesis.

---

## Agent Teams Quick Reference

<!-- [FIX #15] Quick reference for lead agent on team management patterns -->

### Spawning Teammates
Instruct teammates with specific, self-contained prompts. Each teammate:
- Is a full independent Claude Code session
- Has its own context window (does NOT inherit lead conversation)
- Loads project context automatically (CLAUDE.md, skills, MCP servers)
- Must receive all necessary context in its spawn prompt

### File Conflict Avoidance
**Critical**: Never assign two teammates to write the same file. Use the naming convention:
- `{phase}_{methodology}.md` (e.g., `explore_conservative.md`, `arch_pragmatic.md`)

### Model Selection
- Explore teammates: sonnet (fast, cost-effective for code reading)
- Architecture teammates: opus (deep reasoning for design decisions)
- Review teammates: sonnet (good balance for code analysis)

### Token Budget Awareness
Agent teams use significantly more tokens than subagent workflows. Each teammate has its own full context window. Plan for ~4x token usage compared to /gm_bot_rpi per phase.
