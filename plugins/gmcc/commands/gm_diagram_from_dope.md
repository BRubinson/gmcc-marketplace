---
name: gm_diagram_from_dope
description: Generate (or regenerate) the session's domain diagram from its dope model, then screenshot it.
argument-hint: [diagram-code] [--prompt] [light|dark]
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Diagram From Dope

Turn the session's dope model into a db-persisted diagram canvas — one
`dope_scope` container, one `dope_entity` card per entity, grouped in
per-domain columns (FK edges are drawn automatically by the resolver) —
then screenshot it. The layout math lives in
`$GMCC_PLUGIN_ROOT/scripts/diagram_from_dope.py`; this command only wires
context, applies the batch, and renders.

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `~/gmcc/bin/gm session get --json` for the current
   session uuid. If the user passed `--prompt`, also resolve the active
   prompt uuid (or ask which prompt) — prompt mode scopes BOTH the dope
   fetch and the diagram tier to that prompt.

3. **Fetch the dope tree.**
   ```bash
   ~/gmcc/bin/gm dope get --session-uuid <U> [--prompt-uuid <P>] --json > <scratch>/dope_get.json
   ```
   No scope ⇒ report that no dope model exists yet and suggest
   `gm dope init --session-uuid <U> --code <code> --name <name>`. A tree
   whose domains are all entity-less ⇒ report there is nothing to draw.

4. **Init the diagram (idempotent).** Default code is
   `{scope_code}_domain_model` unless the user passed one:
   ```bash
   ~/gmcc/bin/gm diagram init --session-uuid <U> --code <C> \
     --name "<Scope Name> Domain Model" \
     --description "Generated from the <scope_code> dope scope by /gm_diagram_from_dope" --json
   ```
   (`--prompt-uuid <P>` instead in prompt mode.) Note the returned
   `uuid` and `revision`.

5. **Regeneration guard.** If `revision > 0` the canvas already has
   content — fetch it so the batch can swap it atomically:
   ```bash
   ~/gmcc/bin/gm diagram get --diagram-uuid <D> --json > <scratch>/diagram_get.json
   ```
   Pass it to the script via `--existing`. NEVER hand-delete elements one
   verb at a time; the script emits the deletes into the same batch.

6. **Generate mutations.**
   ```bash
   python3 $GMCC_PLUGIN_ROOT/scripts/diagram_from_dope.py \
     <scratch>/dope_get.json <scratch>/mutations.json \
     [--existing <scratch>/diagram_get.json]
   ```

7. **Apply — one batch, one revision, one event.**
   ```bash
   ~/gmcc/bin/gm diagram batch-apply --diagram-uuid <D> \
     --expected-revision <R> --mutations-file <scratch>/mutations.json --json
   ```
   On REVISION_CONFLICT: re-run `gm diagram get`, regenerate with the
   fresh `--existing` tree and retry with the new revision.

8. **Screenshot & report.**
   ```bash
   ~/gmcc/bin/gm diagram screenshot --diagram-uuid <D> [--scheme light|dark] --json
   ```
   Print the returned path and revision, and Read the PNG to sanity-check
   the render (overlaps, ghost cards). Dangling dope bindings render as
   ghosts — legal state, but after a from-dope regenerate they usually
   mean the dope tree changed mid-run; mention them.

## Rules

- The dope tree is fetched from the DB (`gm dope get`), never from the
  on-disk `.gmcc/dope/` files — those can lag or lead the db.
- Hand-placed elements do not survive a regenerate: step 5's deletes wipe
  ALL top-level elements. Say so when regenerating a `revision > 0`
  diagram the user may have edited in GMVibes.
- Never write to `.gmcc/.screenshots/` directly, never edit the repo's
  root `.gitignore`, never restart the daemon.
