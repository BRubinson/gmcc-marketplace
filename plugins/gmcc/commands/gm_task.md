---
name: gm_task
description: Load GMCC session context (via gm reads), then just do the task. Read-only by default — makes NO db or ckfs writes unless you explicitly ask for a retroactive write-back later in the conversation.
argument-hint: <task / request>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, AskUserQuestion
---

# GM-CDE Task (Context-loaded, read-only)

You are executing a task with full GMCC context loaded, but **without** the
prompt-authoring ceremony of `/gm_bot`. You load context, you do the work, and
you leave the daemon db and ckfs untouched — unless the user explicitly asks
you to write something back.

The contract that distinguishes this command from `/gm_bot`:

> **Default behavior writes NOTHING to the daemon db or the ckfs.**
> No prompt row, no artifact registrations, no `gm file-change add`
> bookkeeping. Editing the user's *repository* files is the task and is
> expected — "no writes" refers to GMCC persistence only. Writes happen
> **only** when the user explicitly asks for a retroactive write-back during
> the conversation (see the final section).

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMT] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

---

## Phase 1: Load Context (read-only)

Load **session context** — this is the default scope. These are all reads.

1. `~/gmcc/bin/gm session get --json` — session row (backstory, status),
   prompt stubs, change summary. (`gm context get --json` for the uuid
   triple + active kbite codes if needed.)
2. `gm prompt list --with-reports --json` for every prompt's clarification,
   architecture, exploration, and review state in one call; `gm clarify get`
   / `gm arch get` / `gm explore get` / `gm review get` for full detail on
   the ones that matter. `gm search "<topic>" --json` finds prior work
   across prompts (incl. exploration/review text) — do not grep the ckfs for
   it. `gm artifact list --prompt-uuid U` shows any other files registered
   against a prompt.

**KBites on demand.** If a task clearly benefits from a kbite, load it from
the db: read `$GMCC_KBITE/{name}/KBITE_PURPOSE.md`, then
`gm kbite search "<topic>" --json` for ranked file stubs and
`gm kbite file-get --file-uuid U --json` for the content that matters
(`gm kbite get --code {name} --json` for the full overview). Prefer kbites
already active for the session (`kbite_codes` from `gm session get` /
`gm context get`). Do not block on an AskUserQuestion for kbite selection —
only load what the task needs.

---

## Phase 2: Do the Task

Execute the user's request directly in the primary context using
Read / Edit / Write / Grep / Glob / Bash (and Task for subagents if a search
genuinely warrants it).

- Edit the user's repository files freely — that is the work.
- **Do not** write to the daemon db (`gm` mutations) or create anything under
  `$GMCC_CKFS_ROOT` (no prompt rows, no `memory/` artifacts).
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

### A. Record changed files

For each file you modified (run from inside the repo — git context is
auto-detected):

```bash
~/gmcc/bin/gm file-change add --path <repo-relative path> \
  --kind edit|create|delete|rename [--range start:end]... \
  [--content "<short note>"] [--prompt-uuid U]
```

Pass `--prompt-uuid` only if the work is being attributed to a prompt row
(e.g. one created via write-back B).

### B. Record a prompt

Capture the task after the fact as a prompt row (no clarify pipeline is run,
so it lands as `draft`):

```bash
~/gmcc/bin/gm prompt create --name {name} \
  --goal "<what the task aimed to achieve>" \
  --detail "<how it was done — the specifics>" \
  --command /gm_task --json
```

(Retroactive capture is the one case where the bot authors `goal`/`detail` —
it is recording work already done at the user's request, not splitting a
human prompt.) If you have artifacts to drop there, mkdir the memory dir at
the RETURNED `ckfs_relative_storage_path` (relative to `gm paths` →
ckfs_root) — never re-derive `{seq}_{name}` yourself; the daemon slugs the
name — registering each with `gm artifact add --note "..."`.

After any write-back, state plainly what was persisted and where.
