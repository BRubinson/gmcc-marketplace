---
name: gm_bot
description: Lightweight GMCC workflow (variant bot). Authors a prompt into the current session, enters the daemon's workflow machine, and runs every phase in primary context — the only spawn is the haiku doper briefing.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Bot (variant: bot)

You are executing the **bot** variant: every phase in primary context, no
subagents except the `gmcc:doper` briefing pass. The lifecycle lives in the
daemon — `gm bot next` tells you the current phase, its instructions, and
what blocks the next one. Follow it; this file carries only the variant
contract. Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

Exit without proceeding.

## Arguments

- **Numeric seq** → resume: find the prompt via `gm prompt list --json`,
  then `gm prompt resume --prompt-uuid U [--variant bot]` and `gm bot next`.
- **Slug name + content** → create (STAY TRUE: the whole passed prompt goes
  to `--detail` verbatim; goal/backstory are never authored):

```bash
gm prompt create --name {name} --detail-file <content> \
  --backstory "<session backstory verbatim>" --command /gm_bot --json
mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory   # path verbatim from the response
gm prompt start --prompt-uuid U --variant bot
gm bot next
```

- **No args** → AskUserQuestion for the prompt content.

## Variant contract (bot)

- Haiku doper briefing, then YOU run exploration in context: open your
  `general` summary (`mcp__plugin_gmcc_pen__bot_summary --agent-type
  general`), pen the finding rows yourself, complete it. The pen is loaded
  for you too — `.mcp.json` sets `alwaysLoad`, so running the phase in the
  primary's own context is no reason to reach for the CLI.
- Clarification: you run the merged clarifier pass in context — rank
  prompt-wide from your own self-ratings, open + complete the `synthesis`
  summary, author the questions/notes, seal, run the user conversation
  (AskUserQuestion mirroring the option rows), answer rows, finalize. NO
  care package — the clarified picture stays in your context.
- Architecture: design in context; persistence rows first (change kinds +
  dope refs); propose → user sign-off with the full persistence delta
  table → approve → set-status implementing.
- Implement in context (persistence first; run `gm bot reconcile` at the
  gate), review in context against your general review summary, complete
  with a verdict, run the fix loop, set-status done.

Every step's exact commands come from `gm bot next` — trust the machine,
never skip its gate blockers.
