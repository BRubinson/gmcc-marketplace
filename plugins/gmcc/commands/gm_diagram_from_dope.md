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
then screenshot it. The whole generate/regenerate dance is one verb:
`gm diagram from-dope` (layout math lives in the kit beside the renderer,
so generated geometry and rendered frames share one formula).

## Steps

1. **Boot check.** If `$GMCC_BOOTED` is not set, stop with
   `[GMB] ERROR: GMCC not booted` (run /gmcc_boot for diagnostics).

2. **Resolve context.** `gm session get --json` for the current session
   uuid. If the user passed `--prompt`, also resolve the active prompt uuid
   (or ask which prompt) — prompt mode scopes BOTH the dope fetch and the
   diagram tier to that prompt.

3. **Generate — one atomic batch.**
   ```bash
   gm diagram from-dope --session-uuid <U> [--prompt-uuid <P>] \
     [--code <dope-scope-code>] [--diagram-code <C>] --json
   ```
   Default diagram code is `{scope_code}_domain_model`. The verb fetches the
   dope tree, inits the diagram (idempotent), deletes any existing top-level
   elements and adds the regenerated canvas in ONE batch under the
   diagram-revision CAS (one automatic retry on REVISION_CONFLICT).
   No scope ⇒ it reports that no dope model exists — suggest `gm dope sync`
   (seeds from the repo's `.gmcc` tree) or `gm dope init`. A tree whose
   domains are all entity-less ⇒ it reports there is nothing to draw.
   To inspect without applying: `--dry-run [--mutations-out <path>]`.

4. **Screenshot & report.**
   ```bash
   gm render --diagram-uuid <D> [--scheme light|dark] --json
   ```
   Print the returned path and revision, and Read the PNG to sanity-check
   the render (overlaps, ghost cards). Dangling dope bindings render as
   ghosts — legal state, but after a from-dope regenerate they usually
   mean the dope tree changed mid-run; mention them.

## Rules

- The dope tree is fetched from the DB, never parsed from the on-disk
  `.gmcc/` dope files — run `gm dope sync` first if the files are ahead.
- Hand-placed elements do not survive a regenerate: the batch deletes ALL
  top-level elements. Say so when regenerating a `revision > 0` diagram
  the user may have edited in GMVibes.
- Never write into the CKFS screenshots directory directly, never edit the repo's
  root `.gitignore`, never restart the daemon.
