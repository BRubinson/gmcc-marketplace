---
name: gm_screenshot_session_domain_diagram_state
description: Render the current session's domain diagram headlessly and save the PNG into the repo's gitignored .gmcc/.screenshots directory.
argument-hint: [diagram-code] [--prompt] [light|dark]
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Screenshot the Session Domain Diagram State

Render the session's diagram to a PNG via `gm diagram screenshot` — a pure
client-side headless render (zero db writes) into the instance repo's
self-gitignored `{instance_root}/.gmcc/.screenshots/` directory.

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `~/gmcc/bin/gm session get --json` for the current
   session uuid. If the user passed `--prompt`, also resolve the active
   prompt uuid from the same response (or ask which prompt).

3. **Pick the diagram.** With an argument, use it as `--code`. Otherwise
   enumerate: `gm diagram list --session-uuid <U> --json` (or
   `--prompt-uuid <U>` in prompt mode — tiers never union). Zero rows ⇒
   report that no diagram exists yet and suggest
   `gm diagram init --session-uuid <U> --code <code> --name <name>`.
   Exactly one ⇒ use it. Several ⇒ AskUserQuestion-free tiebreak: pass the
   first by code order and mention the others.

4. **Render.**
   ```bash
   ~/gmcc/bin/gm diagram screenshot --session-uuid <U> [--code <C>] \
     [--scheme light|dark] --json
   ```
   (`--prompt-uuid <U>` instead when prompt-scoped. The verb fetches
   DIAGRAM_GET + one DOPE_GET per resolved dope binding, renders on the CLI
   main actor, and writes `{code}_r{revision}.png`. Dangling dope bindings
   render as ghost cards — that is a legal state, not a failure.)

5. **Report.** Print the returned path and revision. Optionally register the
   artifact: re-run with `--artifact --artifact-prompt-uuid <P>` when the
   screenshot documents a prompt's work.

Never write to `.gmcc/.screenshots/` directly, never edit the repo's root
`.gitignore` (the directory self-ignores), and never restart the daemon.
