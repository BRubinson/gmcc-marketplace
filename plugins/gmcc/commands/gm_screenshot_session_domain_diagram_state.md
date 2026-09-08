---
name: gm_screenshot_session_domain_diagram_state
description: Render the current session's domain diagram headlessly to CKFS storage and return the image path for an agent to read.
argument-hint: [diagram-code] [--prompt] [light|dark]
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Render the Session Domain Diagram State

Render the session's diagram to a PNG via `gm render` — a pure client-side
headless render (zero db writes) into the owner's CKFS storage at
`{ckfs_root}/{owner ckfs path}/{gmcc_diagram_path or 'diagrams'}/screenshots/{code}.png`.

Two things to know before using it:

- **The file is CKFS-rooted, not repo-rooted.** It lives outside the git
  checkout entirely, so there is no `.gitignore` to manage and a
  PROJECT-tier diagram renders as happily as a session-tier one. (`gm
  diagram screenshot`, which wrote into `{instance_root}/.gmcc/.screenshots/`,
  was retired in prompt 9 — it could not serve project-tier diagrams at all.)
- **One mutable file per diagram code**, not one per revision. `gm render`
  decides freshness by comparing a fingerprint sidecar written beside the
  PNG, so re-running it when nothing changed costs nothing and re-renders
  nothing. The fingerprint covers the diagram's revision AND every bound
  dope scope's revision — a dope edit changes the picture without touching
  the diagram row, and a timestamp check would miss exactly that.

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `gm session get --json` for the current
   session uuid. If the user passed `--prompt`, also resolve the active
   prompt uuid from the same response (or ask which prompt).

3. **Pick the diagram.** With an argument, use it as `--code`. Otherwise
   enumerate: `gm diagram list --session-uuid <U> --json` (or
   `--prompt-uuid <U>` in prompt mode — tiers never union). Zero rows ⇒
   report that no diagram exists yet and suggest
   `gm diagram init --session-uuid <U> --code <code> --name <name>`.
   Exactly one ⇒ use it. Several ⇒ pass the first by code order and mention
   the others.

4. **Render.**
   ```bash
   gm render --session-uuid <U> [--code <C>] [--scheme light|dark] --json
   ```
   (`--prompt-uuid <U>` instead when prompt-scoped. The verb fetches
   DIAGRAM_GET + one DOPE_GET per resolved dope binding, renders on the CLI
   main actor, and writes one file per code. Dangling dope bindings render
   as ghost cards — a legal state, not a failure. Pass `--force` only to
   defeat the freshness check deliberately.)

5. **Read it.** The printed path is the deliverable: `Read` it so the image
   enters context. `rendered: false` in the JSON means the existing file was
   already current — that is a success, not a no-op to retry.

6. **Report.** Print the path and revision. Optionally register the
   artifact: re-run with `--artifact --artifact-prompt-uuid <P>` when the
   render documents a prompt's work.

Never write into the CKFS screenshots directory directly, and never restart
the daemon.
