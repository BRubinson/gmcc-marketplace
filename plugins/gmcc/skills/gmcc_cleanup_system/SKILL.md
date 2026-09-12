---
name: gmcc_cleanup_system
description: GM-CDE host-wiring auditor. Renders gm doctor's findings (retired ~/.zshrc gmcc env block, PATH shim health, env-vs-db root agreement, settings.json permission grants, sandbox snapshot completeness, session dope drift) and interactively resolves each one. The ckfs/db data audit is /gmcc_cleanup's job.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC System Cleanup Skill

Audits the HOST wiring that makes GMCC work outside any one repo — shell
config, PATH resolution, permission grants — and interactively resolves
each finding. Detection is `gm doctor`, never prose re-derivation: this
skill renders findings, asks, and applies remedies.

The daemon makes the old env sprawl obsolete: sessions get their env from
`gm context env` at SessionStart, terminals resolve bare `gm` through the
call-time shim, and every path question is answered by `gm paths`. This
skill's job is deleting the leftovers of the old world and keeping the new
wiring healthy.

---

## When to Use

- After a plugin upgrade or `/gm_init` on an old machine
- When bare `gm` stops resolving, or resolves to the wrong (prod/sandbox) binary
- When SessionStart prints a `[GMB] WARN: ... disagreement` line
- Any time the retired `# >>> gmcc env >>>` block might still exist

---

## Step 1: Detect

```bash
gm doctor --json
```

Exit 0 with no findings → report `[GMB] System audit clean` and stop.
Daemon unreachable → `gm doctor` says so; offer the build/restart remedy
first, then re-run.

## Step 2: Resolve (one AskUserQuestion per finding; first option = default)

| Finding code | Meaning | Default remedy |
|---|---|---|
| `zshrc_gmcc_block` | The retired `#### >>> gmcc env >>>` block survives in `~/.zshrc`. Every variable in it is dead — sessions and GMVibes no longer read it | **Delete the whole marker-bounded block.** This is the ONE rm-class action in the GMCC cleanup surface: print the exact lines to be removed first, require explicit confirmation, edit only between the markers |
| `gm_not_on_path` | Bare `gm` does not resolve in a terminal | `gm setup --install-path`; if the shim dir isn't on the user's PATH, surface the printed export line — never write their shell profile |
| `gm_shim_stale` | An installed GMCC shim no longer matches the current resolver rule | Re-run `gm setup --install-path --path-dir <dir>` |
| `ckfs_root_mismatch` / `gmcc_root_mismatch` | Env claim disagrees with the db the daemon answered from | Sandbox: `gm sandbox refresh`. Prod: `gm config set --key ckfs_root --value <correct>` — show both values, let the user pick which is right |
| `sandbox_metaless` | `GMCC_ROOT` points at a snapshot with no `snapshot_meta.json` | Re-run `gm sandbox refresh` from the prod environment |
| `dope_scope_unseeded` / `dope_files_ahead` | Repo `.gmcc` tree newer than (or absent from) the session scope | `gm dope sync` |
| `dope_db_ahead` | Session dope edits never published to the repo files | `gm dope write-repo --scope-uuid <U>` (or accept — boot never overwrites db-ahead state) |
| `daemon_unreachable` | Socket dead or binary stale | `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` then `gm daemon restart` |

### Permission-grant drift (settings.json)

`gm doctor` covers wiring; the settings.json CKFS grant check stays here
(it needs jq and user-scope file edits). Expected entries in
`~/.claude/settings.json`: `$GMCC_CKFS_ROOT` in
`permissions.additionalDirectories`; `Read($GMCC_CKFS_ROOT/**)`,
`Edit($GMCC_CKFS_ROOT/**)`, `mcp__plugin_gmcc_pen__*`, and
`Bash($HOME/gmcc/bin/gmcc_hook *)` in `permissions.allow`.

`mcp__plugin_gmcc_pen__*` is the load-bearing one: the pen is the only
channel Claude records through, so a missing grant makes every write
prompt. `Bash($HOME/gmcc/bin/gmcc_hook *)` covers the shell-callable ops
client only — hooks, context env, daemon lifecycle, and the
`gmcc_hook call <MESSAGE_TYPE>` passthrough a human runs at a terminal.

RETIRED, and the merge SCRUBS them rather than leaving them: `Bash(gm *)`
and `Bash($HOME/gmcc/bin/gm *)`. The `gm` binary no longer exists, so
those grants authorize nothing — but left in place they read as a live
CLI path and invite reaching for one. Scrub them the same way the merge
already scrubs retired `Write(...)`/`Glob(...)` rules.

Missing → offer the same idempotent jq merge `/gm_init` documents (adds
what's missing, scrubs retired rules, preserves everything else). Takes
effect on the next Claude Code restart.

## Step 3: Verify + report

Re-run `gm doctor`. Report resolved/skipped per finding, plus anything
still open.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation.
- The zshrc block deletion is marker-bounded, previews the exact removed
  lines, and never touches lines outside the markers.
- **Never write shell profiles** — PATH advice is printed, not applied.
- **Never write the db directly** — all db-side remedies go through `gm`.
- `--adopt` is never offered here; dope remedies are `gm dope sync` /
  `gm dope write-repo` exactly as the doctor's remedy strings say.
