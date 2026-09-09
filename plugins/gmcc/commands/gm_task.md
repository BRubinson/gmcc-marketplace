---
name: gm_task
description: Load GMCC session context (via gm reads), then just do the task. Writes no prompt rows or report summaries — GMCC persistence happens only via the automatic file-change hook, an optional doper briefing for meaty tasks, or an explicitly requested retroactive write-back.
argument-hint: <task / request>
disable-model-invocation: true
allowed-tools: Bash(gm:*)
---

# GM-CDE Task (Context-loaded, no ceremony)

You are executing a task with full GMCC context loaded, but **without** the
prompt-authoring ceremony of `/gm_bot`. You load context, you do the work,
and you leave the prompt/report surface of the daemon db untouched — unless
the user explicitly asks you to write something back.

The contract that distinguishes this command from `/gm_bot`:

> **Default behavior authors NOTHING in the daemon db or the ckfs.**
> No prompt row, no clarify/arch/explore/review summaries, no artifact
> registrations. Editing the user's *repository* files is the task and is
> expected — and those Edit/Write changes are auto-recorded by the plugin's
> PostToolUse hook (`gm file-change add --auto-attribute`; unattributed when
> no prompt is active). That hook bookkeeping is harness plumbing, not you
> reaching for gm mutations. The two sanctioned exceptions: the optional
> doper briefing below, and an explicitly requested retroactive write-back
> (final section).

SessionStart injects the compact `gm cheatsheet` core; run
`gm cheatsheet --full` for exact signatures — never `gm ... --help`
roundtrips, never guess flags.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMT] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

Current session state (inlined at invocation):

!`gm session get --json`
!`gm prompt list --with-reports --json`
!`gm dope list --json`

If these errored with exit 2 (daemon unreachable), self-heal:
`bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gm context ensure`,
then re-run them.

---

## Phase 1: Deeper Context (read-only, on demand)

The inlined state above covers the default scope: session row (backstory,
status), every prompt's clarification/architecture/exploration/review stubs,
change summary, and dope scopes. Pull detail only where the task needs it:

- `gm clarify get` / `gm arch get` / `gm explore get` / `gm review get` for
  full detail on the prompts that matter; `gm search "<topic>" --json` finds
  prior work across prompts — do not grep the ckfs for it.
  `gm artifact list --prompt-uuid U` shows files registered against a prompt.
- **Dope on demand.** `gm dope search session "<query>"` (FTS5, dot-path
  hits) then targeted `gm dope get --code <scope>` — never full-tree dumps.
- **KBites on demand.** If a task clearly benefits from a kbite:
  `gm kbite search "<topic>" --json` for ranked stubs, read the briefs, then
  `gm kbite file-get --file-uuid U --json` for the content that matters
  (`gm kbite get --code {name} --json` for the overview; purpose file at
  `{kbite_root}/{name}/KBITE_PURPOSE.md`, kbite_root from
  `gm paths --json`). Prefer kbites already active for the session. Do not
  block on an AskUserQuestion for kbite selection — only load what the task
  needs.

### Optional: session-owned briefing for meaty tasks

For a substantial task that would benefit from real context assembly,
delegate it to the doper instead of hand-searching (this is a sanctioned
db write — `agent_briefing` rows are context plumbing, not work records).
There is no prompt row, so the briefing is SESSION-owned:

```bash
gm briefing open --session-uuid U --step initial --json     # → briefing uuid
```

```
Task tool:
  subagent_type: gmcc:doper
  prompt: |
    Owner session uuid: {U}
    Step: initial
    Topic: {one line — what this task is about}
```

After the doper's receipt, pull it BY UUID — `gm briefing get
--briefing-uuid {B} --json`, where {B} was printed by your own `gm briefing
open` — and work from the briefing body plus the deeper-pull commands it
names. The zero-uuid form is for SPAWNED agents; here in the primary it can
be shadowed by this instance's lingering prompt claim (a prompt-owned
briefing would resolve ahead of your just-built task row), and you hold the
uuid anyway.

---

## Phase 2: Do the Task

Execute the user's request directly in the primary context using
Read / Edit / Write / Grep / Glob / Bash (and Task for subagents if a search
genuinely warrants it).

- Edit the user's repository files freely — that is the work. The
  PostToolUse hook records those changes automatically; do not add manual
  `gm file-change add` bookkeeping on top of it.
- **Do not** author gm entities (no prompt rows, no report summaries, no
  artifact registrations, nothing under `$GMCC_CKFS_ROOT`).
- If the task balloons in scope and would benefit from the full clarify → plan →
  review pipeline, suggest the user re-run it under `/gm_bot` (or `/gm_bot_rpi`
  / `/gm_bot_team`) rather than reaching for GMCC bookkeeping here.

When finished, give a concise summary: what you did, files touched, anything
deferred. Do **not** persist that summary anywhere — it stays in the chat.

---

## Retroactive Write-Back (only on explicit request)

Skip this section entirely unless the user, at some point in the conversation,
explicitly asks you to record the work (e.g. "save that to the session",
"record the files you changed", "write this up as a prompt"). Honor exactly
what they ask for; do not volunteer writes.

Two write targets are supported.

### A. Record / attribute changed files

Edit/Write-driven changes were already recorded automatically (unattributed).
Manual `gm file-change add` is needed only for:

- files changed through Bash (scripts, generators, `git mv`):
  ```bash
  gm file-change add --path <repo-relative path> \
    --kind edit|create|delete|rename [--range start:end]... \
    [--content "<short note>"] [--prompt-uuid U]
  ```
- attributing the work to a prompt row (e.g. one created via write-back B):
  pass `--prompt-uuid` on the rows you add.

Run from inside the repo — git context is auto-detected. `--content`
requires exactly one `--range`.

### B. Record a prompt

Capture the task after the fact as a prompt row (no clarify pipeline is run,
so it lands as `draft`):

```bash
gm prompt create --name {name} \
  --goal "<what the task aimed to achieve>" \
  --detail "<how it was done — the specifics>" \
  --command /gm_task --json
```

(Retroactive capture is the one case where the bot authors `goal`/`detail` —
it is recording work already done at the user's request, not splitting a
human prompt. For a long write-up use `--detail-file`.) If you have
artifacts to drop there, mkdir the memory dir at the RETURNED
`ckfs_relative_storage_path` (relative to `gm paths` → ckfs_root) — never
re-derive `{seq}_{name}` yourself; the daemon slugs the name — registering
each with `gm artifact add --note "..."`.

After any write-back, state plainly what was persisted and where.
