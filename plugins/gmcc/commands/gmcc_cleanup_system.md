---
name: gmcc_cleanup_system
description: Audit and repair GM-CDE host wiring (retired ~/.zshrc gmcc block, PATH shim, env-vs-db roots, permission grants) via gm doctor.
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC System Cleanup

If `$GMCC_BOOTED` is not set, stop with `[GMB] ERROR: GMCC not booted`
(run /gmcc_boot for diagnostics).

Invoke the `gmcc_cleanup_system` skill and follow it: run `gm doctor
--json`, resolve each finding interactively (the retired `~/.zshrc` gmcc
env block's default remedy is DELETE), verify with a clean re-run.

The ckfs/db data audit (artifact drift, archive hygiene, kbite provenance)
is `/gmcc_cleanup`.
