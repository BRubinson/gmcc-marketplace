---
name: refresh_daemon_state
description: Ensure the latest GMCC daemon is installed AND running. Runs the staleness-checked build, then restarts the daemon whenever the running process predates the installed binaries (the handshake only auto-retires across a wire-version bump). Ends with gm status.
argument-hint: "[--force]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# /refresh_daemon_state

Bring the daemon system fully current: newest binaries in `~/gmcc/bin/`,
newest build actually serving the socket. Invocation protocol and self-heal
rule in `$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

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

1. **Build/install** — run:
   ```bash
   bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
   ```
   Append `--force` if the user passed it (clean rebuild). The script is
   staleness-checked: note whether it printed `installed:` (rebuilt) or
   `up to date` (no-op).

2. **Ensure the RUNNING daemon is the installed build**:
   - If step 1 rebuilt, the running daemon (if any) is definitionally
     stale — run `~/gmcc/bin/gm daemon restart`.
   - If step 1 no-oped, check what's serving the socket:
     `~/gmcc/bin/gm daemon status` (never autostarts). If no daemon is
     running, `~/gmcc/bin/gm daemon start`. If one is running, compare
     `~/gmcc/bin/gm ping --json`'s build date against the installed
     binary's mtime (`stat -f %Sm -t %Y-%m-%dT%H:%M:%SZ ~/gmcc/bin/gmcc_daemon`
     is local time — convert or compare epochs); if the running build date
     is older than the binary, run `~/gmcc/bin/gm daemon restart`.

   Do NOT rely on the protocol handshake here: it only retires a stale
   daemon across a wire-version bump, not a same-version rebuild.

3. **Verify** — run `~/gmcc/bin/gm ping` and `~/gmcc/bin/gm status`; the
   ping build sha/date must now reflect the just-installed binaries.

**Self-heal**: if any `gm` call fails because `~/gmcc/bin/gm` is missing,
run the build (step 1) and retry once.

---

## Output

Report: rebuilt vs already-current, whether a restart happened and why,
then the running build sha/date + `gm status` summary. End with:

```
[GMB] daemon current — build {sha} running, gm CLI at ~/gmcc/bin/gm
```
