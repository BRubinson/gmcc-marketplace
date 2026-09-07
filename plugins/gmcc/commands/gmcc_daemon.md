---
name: gmcc_daemon
description: Build, install, and control the GMCC daemon (gmcc_daemon + gm CLI). Runs scripts/build_daemon.sh and drives the gm CLI for status/restart. The daemon owns the SQLite db at ~/gmcc/gmcc.db; everything else is a socket client.
argument-hint: "[build | status | restart | setup]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /gmcc_daemon

Manage the GMCC daemon system. Full invocation protocol (gm subcommand list,
self-heal rule, single-writer model) in
`$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

---

## Execution

Read the `gmcc_daemon` skill (`$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`)
for the complete protocol, then dispatch on the argument:

- **`build`** (default when binaries are missing/stale): run
  `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` and report the output.
  Append `--force` if the user asked for a clean rebuild.
- **`status`**: run `gm status` and report daemon pid, schema
  version, and table counts.
- **`restart`**: run `gm daemon restart`.
- **`setup`**: run `gm setup` (first-time init of `~/gmcc/` and the
  db). Offer `--launchd` if the user wants the daemon started at login.
- **No argument**: run the build (staleness-checked — it no-ops when binaries
  are current), then `gm status`.

**Self-heal**: if any `gm` invocation fails because the gm binary is
missing, run the build first, then retry once.

---

## Output

Relay the script/CLI output. On success end with:

```
[GMB] daemon ready — gm CLI at ~/gmcc/bin/gm
```
