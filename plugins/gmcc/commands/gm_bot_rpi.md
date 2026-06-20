---
name: gm_bot_rpi
description: Subagent-based Research/Plan/Implement workflow. Spawns specialized GMCC subagents for exploration, architecture, and code review while keeping clarification and implementation in primary context. Authors prompts into the current session.
argument-hint: <prompt-name|id> <task/prompt content>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Bot RPI (Subagent Research/Plan/Implement, v6.0.0)

You are executing an enhanced development workflow that leverages GMCC subagents for Research, Planning, and Review phases. Same prompt-into-session model as `/gm_bot`, with subagents added to Phases 2, 4, and 6.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

The SessionStart hook auto-creates `$GMCC_SESSION_PATH/{session_data.yaml, prompts/}`. If `$GMCC_SESSION_PATH/session_data.yaml` is missing, instruct the user to restart Claude Code.

1. Read `$GMCC_SESSION_PATH/session_data.yaml` for current session state.
2. Skim recent clarified prompts under `$GMCC_SESSION_PATH/prompts/*_clarified.yaml` for context.

---

## Argument Parsing

Identical to `/gm_bot`. See `${CLAUDE_PLUGIN_ROOT}/commands/gm_bot.md` for full detail. Quick summary:

- **Resume** (`/gm_bot_rpi 3 ...`): find prompt with `id: 3` in session_data; resume at Phase 4 if clarified, Phase 3 if draft.
- **New** (`/gm_bot_rpi auth-refactor ...`): assign next id, write draft yaml, append session_data entry, proceed.
- **No args**: AskUserQuestion for name + content.

---

## Draft Prompt File Template

Write to `$GMCC_SESSION_PATH/prompts/{id}_{name}.yaml`:

```yaml
version: 1
id: {id}
name: {name}
status: draft
command: /gm_bot_rpi
created_at: {ISO 8601}
content: |
  {raw user prompt}
kbites_loaded: []
kbite_context_summary: ""    # filled in Phase 1 for subagent passing
```

---

## Phase 1: KBite Loading (New Prompt Only)

1. List available kbites: `ls $GMCC_KBITE_DIGESTED/`. For each, read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md`.
2. AskUserQuestion (multiSelect) to pick relevant kbites.
3. For each selected kbite: read `KBITE_INDEX.md` + `KBITE_TRIGGER_MAP.md`, load top 3-5 chewed files, compile a **kbite context summary** (key learnings, takeaways, patterns).
4. Update the draft prompt yaml's `kbites_loaded:` list and `kbite_context_summary:` field — this summary is passed to every subagent spawn.

---

## Phase 2: Implementation Overview (Explore Subagent)

Spawn 1 explore subagent via Task tool. The subagent does its work in its own context window; it returns a structured report as its final message. The primary context receives the report content but does NOT persist it to disk (v6.0.0 deliberately drops intermediate-artifact persistence — see `skills/gmcc/ref/bot_workflows.md`).

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_explorer.prompt.md

    ## Task Context
    **Exploration Target**: {raw prompt content}
    **Repository**: Explore from the current working directory
    **Branch**: $(basename $GMCC_SESSION_PATH)

    ## KBite Knowledge
    {kbite_context_summary from prompt yaml}

    ## Exploration Approach
    Apply all 4 methodologies sequentially:
    1. Conservative: existing patterns to reuse
    2. Aggressive: areas that might need significant changes
    3. Pragmatic: balance effort/value
    4. Alternative: unconventional integration points

    ## Output
    Return your complete exploration report as your final message.
    Use the Code Explorer Report format from your prompt file.
    Include: Target, Key Files, Patterns, Integration Points, Dependencies, Uncertainties, Methodology Insights.
```

Read the returned report into the primary context. Use it to inform Clarify.

---

## Phase 3: Clarify

1. Review the exploration report for uncertainties and ambiguities.
2. AskUserQuestion to resolve all identified issues (uncertainties, edge cases, integration preferences, scope boundaries).
3. Write `$GMCC_SESSION_PATH/prompts/{id}_{name}_clarified.yaml`:

```yaml
version: 1
id: {id}
name: {name}
status: clarified
command: /gm_bot_rpi
clarified_at: {ISO 8601}
original_content: |
  {raw user prompt}
clarifications:
  - q: {question 1}
    a: {answer 1}
refined_content: |
  {Refined task description integrating clarifications + exploration findings.
   Single source of truth from here on.}
key_files:
  - path: {file}
    relevance: {why}
patterns_to_follow:
  - {pattern from exploration}
constraints:
  - {constraint}
kbites_loaded:
  - {kbite name}
```

4. Update `session_data.yaml`: flip prompt entry to `status: clarified`, set `clarified_file: prompts/{id}_{name}_clarified.yaml`.

---

## Phase 4: Plan (Architect Subagent)

Spawn 1 architect subagent. Same in-conversation pattern — no disk persistence of the architecture doc.

```
Task tool:
  subagent_type: general-purpose
  model: opus
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_architect.prompt.md

    ## Architecture Context
    **Goal**: {refined_content from clarified prompt yaml}

    ## Clarified Prompt
    {full clarified yaml contents}

    ## Exploration Findings
    {exploration report from Phase 2, in primary context}

    ## KBite Knowledge
    {kbite_context_summary}

    ## Architecture Approach
    Apply all 4 methodologies and synthesize the best elements.

    ## Output
    Return your architecture document as your final message.
    Format: Goal, Approach Summary, Components, Files to Modify/Create, Build Sequence, Acceptance Criteria, Trade-offs.
```

Present the architecture to the user via AskUserQuestion:
```
Architecture design complete. Review the plan:

{brief summary}

How would you like to proceed?
- Approve and implement - Start building
- Modify - I have changes to the architecture
- Reject and redesign - Start architecture over
```

---

## Phase 5: Implement

1. Follow the approved architecture's build sequence.
2. Make edits with Read/Edit/Write.
3. After each file write, append to `session_data.yaml`'s `changed_files:` list:
   ```yaml
   - file: {path relative to instance}
     timestamp: {ISO 8601}
     lines: [[start, end], ...]
     commit: {short sha or "uncommitted"}
   ```

---

## Phase 6: Review (Code Review Subagent)

Spawn 1 review subagent.

```
Task tool:
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    Read and follow your agent identity from: $GMCC_PLUGIN_ROOT/prompts/gmcc_agent_code_quality_reviewer.prompt.md

    ## Review Context
    **Task**: {refined_content from clarified prompt}

    ## Clarified Prompt
    {clarified yaml contents}

    ## Architecture
    {architecture doc from Phase 4}

    ## Files Changed
    {list from session_data.yaml changed_files}

    ## Output
    Return your review report as your final message.
    Format per the Code Quality Review Report in your prompt file.
```

Present findings via AskUserQuestion:
```
Code review complete. {summary}

How would you like to handle the findings?
- Fix all issues
- Fix critical only
- Proceed as-is
```

Implement requested fixes (back to Phase 5 for the fix subset).

---

## Phase 7: Feedback Integration

1. Present a complete summary: what was built, files modified, review findings addressed, known limitations.
2. Wait for user feedback. Iterate until satisfied.
3. On completion, append to `session_data.yaml`:
   ```yaml
   phase_history:
     - prompt_id: {id}
       command: /gm_bot_rpi
       completed_at: {ISO 8601}
       review_status: {pass | pass_with_issues}
   ```

```
Bot RPI Complete: prompt {id} ({name})

**Session**: {GMCC_SESSION_PATH relative to GMCC_PROJECTS}
**Files Modified**: {count}
**Review Status**: {pass / pass_with_issues}

**Next**: continue with more prompts in this session, or start a new prompt with `/gm_bot_rpi {next_id} ...`.
```

---

## Error Handling

**Subagent spawn failure:**
```
[GMB] Subagent spawn failed for {phase}

Falling back to primary context for this phase.
```
Continue the phase in primary context as a fallback.

**Session paused:**
```
State preserved at: $GMCC_SESSION_PATH/prompts/{id}_{name}{_clarified}.yaml

To resume: /gm_bot_rpi {id} <continuation prompt>
```

**Task grows in scope:**
```
This task may benefit from full agent team treatment.

- Continue as /gm_bot_rpi
- Switch to /gm_bot_team
```
