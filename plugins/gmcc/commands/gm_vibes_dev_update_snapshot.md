---
name: gm_vibes_dev_update_snapshot
description: Create or refresh the local-dev sandbox at gmcc_ckfs/development/local_sandbox — a snapshot of the gmcc-marketplace repo, the gmcc sqlite (via gm backup), and a sub-ckfs, fully isolated behind GMCC_ROOT so a dev daemon/gm/GMVibes stack runs without touching prod.
argument-hint: [status]
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# GM Vibes Dev Snapshot

Thin wrapper over `gm sandbox refresh` — the whole pipeline lives in the gm
binary (see `gm cheatsheet`, SANDBOX section). Run it, verify, report.

## Preconditions (the verb enforces these — do not work around a refusal)

- Run from the **gmcc-marketplace repo root**, in a **prod** session
  (`GMCC_ROOT` unset). A refusal names the fix — e.g. `gm daemon restart`
  when the running prod daemon predates the installed binary.
- The prod db is touched ONLY by the sanctioned `gm backup` read. The live
  ckfs is never written. Kbites (~27GB) are never copied — the sandbox gets
  empty kbite roots by design.

## Steps

1. If the argument is `status`, run `gm sandbox status --json`,
   report, and stop.
2. Run the refresh (allow a generous timeout — it clones the repo and copies
   the project subtree):
   ```sh
   gm sandbox refresh --json
   ```
3. Verify isolation before declaring success:
   ```sh
   SANDBOX=~/gmcc_ckfs/development/local_sandbox
   "$SANDBOX/launch_gm.sh" status --json      # autostarts the SANDBOX daemon
   "$SANDBOX/launch_gm.sh" paths --json       # every path must be under $SANDBOX
   "$SANDBOX/launch_gm.sh" session list --json # non-empty = identity rewrite worked
   ```
   If any `paths` value points outside the sandbox, STOP and report — do not
   keep using that sandbox.
4. Report: generation, instance code, the two launchers
   (`launch_gm.sh <args>`, `launch_gmvibes.sh [app-path]` — Finder cannot
   pass env, so the app must be launched through the script), and that
   re-running this command is always the safe recovery for a partial
   snapshot (`snapshot_meta.json` is written last).

## Refusals

- NEVER run `gm setup --launchd` in the sandbox (the verb refuses too — the
  launchd plist/label is a prod singleton).
- NEVER copy the live `~/gmcc/gmcc.db` directly; the pipeline's `gm backup`
  is the only sanctioned read.
- NEVER point sandbox kbite roots at the live kbite trees.
