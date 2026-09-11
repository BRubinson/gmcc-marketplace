---
name: gm_bot_rpi
description: Subagent GMCC workflow (variant rpi). One general-persona subagent per phase adopts every methodology's goals at once; up to 2 implementation subagents; care package instead of the retired pre-architecture briefing.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Bot RPI (variant: rpi)

You are executing the **rpi** variant: ONE general-persona subagent per
phase (it adopts all four methodology lenses at once — summary/agent type
`general`), plus up to 2 implementation subagents. The lifecycle lives in
the daemon — `gm bot next` serves each phase's instructions and gates.
Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

Exit without proceeding.

## Arguments

Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
`--command /gm_bot_rpi` at create and `--variant rpi` at start/resume.

## Variant contract (rpi)

- Haiku doper briefing, then spawn ONE `gmcc:code-explorer` with
  `Methodology: general` — it opens its own summary via the pen tools,
  writes its rows, completes it. No 4-spawn batches, NO reranker pass:
  self-ratings stand; you rank prompt-wide from them, then open + complete
  the `synthesis` summary.
- Clarification: spawn `gmcc:ques` to pen the question/note suite (or
  author it yourself for a thin prompt), seal, run the user conversation,
  answer, then build the CARE PACKAGE (package-open → package-add refs →
  package-complete with the clarified intent), finalize, set-status
  architecting.
- Architecture: ONE `gmcc:code-architect` (general, solo mode —
  proposal-only); you persist the rows (persistence first), propose →
  sign-off (full persistence delta table) → approve → implementing.
- Implement with up to 2 implementation subagents (persistence first;
  `gm bot reconcile` at the gate). Review: ONE `gmcc:code-quality-reviewer`
  (general); you complete with the verdict and run the fix loop; done.

Spawn prompts carry ONLY: the methodology (`general`), the summary uuid
where the def asks for one, and the one-line target. Teammate-style pastes
of cheatsheets or briefings are forbidden — agents pull their own context
through the pen tools.
