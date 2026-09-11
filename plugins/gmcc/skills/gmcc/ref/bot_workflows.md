# Bot Workflow System Reference

**The single canonical lifecycle document.** Every tier command holds ONLY
its variant contract and points here. Where a tier doc and this file
disagree, this file wins. Since m0025 the LIFECYCLE ITSELF lives in the
daemon: `gm bot next` derives the current phase from db evidence and serves
that phase's instructions — this file describes the machine, not the prose.

## The machine

A bot run adds a **prompt row** to the current session, then enters the
workflow machine:

```bash
gm prompt create --name {name} --detail "<the passed prompt, verbatim>" \
  --backstory "<session backstory, verbatim>" --command /gm_bot{,_rpi,_team} --json
mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory   # verbatim from the response
gm prompt start --prompt-uuid U --variant bot|rpi|team          # draft only
gm bot next                                                     # …and follow it
```

Resume is the SAME code path — phase is derived, never stored:

```bash
gm prompt resume --prompt-uuid U [--variant V]   # pass --variant only for a pre-machine prompt
gm bot next
```

`gm bot next` returns the current phase, its instruction text (compiled into
the binary, per variant), the phase's uuid bundle, and the gate blockers for
the next phase. It REFUSES to advance past unmet gates (the briefing
hard-stop, the exploration seal, clarification finalize, architecture
approval) — mechanically, not by prose. `gm prompt set-status` remains the
ONLY door that moves a prompt; the machine names the exact command when a
status gate is met and never bypasses it.

Phase graphs (registry-governed — WorkflowSpec in the kit; new phases are
registry entries, never migrations):

| variant | phases |
|---------|--------|
| bot  | briefing → explore → clarify_open → clarify_user → architecture → plan_gate → implement → review → review_fix → done |
| rpi  | … same, plus care_package between clarify_user and architecture |
| team | … same as rpi, plus arch_options before architecture |
| task | NO workflow row (write-nothing contract) — /gm_task is not machine-driven |

## STAY TRUE (prompt content)

`backstory`/`goal`/`detail` are **pure human input**. The passed prompt goes
to `--detail` verbatim; never split, infer, or author any of the triple —
and NOTHING writes prompt content past draft: the old finalize→prompt.goal
copy is retired. The clarified intent lives on the CARE PACKAGE.

## Phases (what the machine will tell you, in brief)

1. **briefing** — `gm briefing open --prompt-uuid U --step initial`, spawn
   `gmcc:doper` (haiku), gate on `gm briefing get --step initial --wait`.
   Briefings are OPINION-FREE ref sets (dope dot-paths, kbite files,
   file changes) — no body. The dead-doper policy: on timeout, one plain
   get; still building → re-open + re-spawn once; then proceed briefing-less
   with an explicit note. The old second briefing step is RETIRED — the
   care package replaced it.
2. **explore** — per-agent summaries: `gm explore open --agent-type T` per
   expected agent (bot/rpi: general; team: the four methodologies). Agents
   hold the pen (finding/key-file rows + their OWN complete with their own
   overview). Then ONE prompt-scoped rank (`gm explore rank --prompt-uuid`;
   team delegates to `gmcc:finding-reranker`), and the primary opens +
   completes the `synthesis` summary — that completion IS the prompt-level
   seal and refuses while anything is unranked.
3. **clarify_open** — `gm prompt set-status --status clarifying` (locks
   content, creates the summary). Questions (`gm clarify question-add`, with
   ordered `--option` rows) and internal notes (`gm clarify note-add`,
   weight 0-999, 0 = critical) — team flows spawn `gmcc:ques` to pen the
   suite. `gm clarify seal` when authored.
4. **clarify_user** — the PRIMARY asks (AskUserQuestion mirroring the option
   rows), records with `gm clarify answer --question-uuid (--select
   OPTION_UUID)... [--answer text] [--skip]`. At most 2 generative
   follow-up passes.
5. **care_package** (rpi/team) — `gm clarify package-open`, curate refs
   (`package-add --kind dope|kbite|exploration` — exploration entries are
   COPIES of ranked findings, never re-explored), then `package-complete
   --intent-file` with the clarified intent (backstory+goal+detail,
   clarified). The intent lives ONLY here. Then `gm clarify finalize` (a
   pure gate) and `gm prompt set-status --status architecting`.
6. **arch_options** (team) — architects hold the OPTION pen: each writes
   its proposal via `gm arch option-add`. Once any option exists, change
   rows refuse until `gm arch decide` selects one (rejecting siblings,
   recording the rationale).
7. **architecture** — ONLY the selected option (or the solo design) expands
   into rows: persistence FIRST (`persist-add --change-kind
   add|modify|rename|delete --dope-ref <entity code>`; `field-add` with
   `--renamed-from`/`--dope-property-ref` for renames/deletes), then
   `general-add`, then `summarize`.
8. **plan_gate** — `gm arch propose`, user sign-off ALWAYS showing the full
   persistence delta table (positive AND negative changes), `gm arch
   approve` + `set-status implementing` (claims the activation) or `revise`.
9. **implement** — persistence changes first. Edit/Write is hook-recorded;
   `gm bot reconcile` at the gate sweeps Bash/workflow writes the hook never
   saw (origin=reconcile, real delete/rename kinds). Team: the primary
   hand-authors the implementation workflow, guided by `gm bot next` —
   script code never touches gm; agents inside the workflow hold the pen.
   `gm arch get` audits progress.
10. **review** — `set-status reviewing`, `gm review open`, reviewer agents
    pen finding rows, reranker calibrates, primary completes with the
    verdict.
11. **review_fix** — clarify fix intent with the user; `gm review resolve`
    per finding under 100 (works after complete by design).
12. **done** — `set-status done` (releases the activation claim, closes the
    workflow row). Completion is db rows only — no phase-history files.

## Who holds the pen

Spawned agents write their own rows via the **MCP pen tools**
(`mcp__plugin_gmcc_pen__*` — the plugin's `pen` server; primary-only verbs
are physically absent from that surface) with `gm` Bash fallbacks. The
primary keeps: the synthesis seal, rank delegation, clarify conversation +
finalize, arch decide/propose/approve, review complete/verdict, resolve.
`gmcc:code-architect` pens OPTION rows in team flows (the m0025 inversion);
its solo proposals stay chat-ephemeral.

**finding_rating (0-999)**: 0 = critical, 999 = tombstone; read threshold
100. Re-runs supersede by re-ranking, never deletion. Notes reuse the same
polarity as `weight`.

## Invariants (unchanged)

- Thread `--expected-version` on every mutation; on VERSION_CONFLICT re-get
  and retry. `SUMMARY_ABSENT` = open it; never a file fallback.
- Everything is db rows via gm/MCP — never read or write ckfs yamls; never
  mirror a report to a file.
- Zero-uuid resolution (bot verbs, briefing get, --auto-attribute) walks:
  caller's own claim → session's single claim → task row. Teammates are
  separate claude processes — their spawn prompts carry the explicit
  `--prompt-uuid` forms; every bot verb keeps that escape hatch.
- agent_id / agent_name are self-reported on every agentic write —
  ClientKey cannot distinguish sibling subagents.
- Dope is search-first (`gm dope search` + targeted `--code` gets);
  full-tree dumps are FORBIDDEN. An architecture proposing persistence is
  proposing dope changes. Kbites are inherited, never auto-detected.

## Error recovery

Daemon unreachable (exit 2): `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`,
`gm context ensure`, retry. `$GMCC_BOOTED` unset: restart Claude Code.
Anything stranded mid-phase: `gm prompt resume` + `gm bot next` — resume is
the first-run code path by construction.
