---
name: gm_art
description: "Interactive co-diagramming: Claude and GMVibes edit the SAME canvas live"
argument-hint: "[diagram_code | new <code> <name>] [instruction]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# /gm_art [diagram_code] [instruction]

Starts an interactive diagramming session on ONE shared canvas: you edit it
db-natively through the `gm` CLI, GMVibes reflects every write live off the
daemon event stream, and the human draws in GMVibes while you read their
strokes back. Pure choreography — every primitive already exists; this
command is the loop discipline.

## The substrate (nothing here is new machinery)

- WRITE: `gm diagram batch-apply --diagram-uuid U --mutations-file P
  --expected-revision N` — one transaction, one revision bump, one durable
  DIAGRAM_CHANGE event. `--expected-revision` is the whole-diagram CAS:
  on VERSION_CONFLICT, re-`get`, rebase your mutations, retry ONCE.
- WATCH: `gm events --since-id N --json` filtered to kind DIAGRAM_CHANGE
  with your diagram_uuid. Durable and replayable — no subscription needed;
  poll between your own turns.
- READ BACK: `gm diagram get --diagram-uuid U --json` for the tree, and
  `gm render --diagram-uuid U --json` for the picture (fingerprint-cheap:
  unchanged content re-renders nothing; add `--force` only after your own
  kit-side look changes, which do not happen in this loop).
- UNDERSTANDING: optionally `gm prompt-diagram qualify` to record what the
  picture MEANS once the session settles.

## Echo suppression (the one stated rule)

Every `batch-apply` response returns the post-write `revision`. Keep a
per-diagram watermark of YOUR latest returned revision. When polling
events, IGNORE any DIAGRAM_CHANGE for this diagram whose `revision` is
<= your watermark — that is your own write echoing back. A HIGHER
revision is the human's edit: `gm diagram get` + `gm render` BEFORE your
next write, then rebase onto the new revision. Never diff by author —
there is no actor column, by design.

## Flow

1. **Pick the canvas.** No argument → `gm diagram search --json` (browse
   mode) and AskUserQuestion over the recent diagrams (+ "create new").
   `new <code> <name>` → `gm diagram init --session-uuid <current session>
   --code <code> --name "<name>" --json` (resolve the session with
   `gm session get --json`). A bare code → `gm diagram get --session-uuid
   <current> --code <code> --json`; on SUMMARY_ABSENT offer to init.
2. **Baseline.** `gm diagram get` for the tree + revision; `gm render` and
   READ the PNG (the Read tool renders images); note the current event
   cursor (`gm events --limit 1 --json` → id). Set watermark = revision.
3. **Announce the loop** to the user: they draw in GMVibes (the canvas
   updates live for them on your every write); they talk to you here.
4. **Each of your turns:**
   a. Poll `gm events --since-id <cursor>` → advance cursor; apply the
      echo rule. If the human drew, re-`get` + re-`render` + LOOK before
      planning.
   b. Make your edit as ONE batch (mutations file in the scratchpad;
      `--expected-revision` = latest known). Update the watermark from the
      response.
   c. Re-render and LOOK at the result — never describe an edit you have
      not seen. Iterate geometry until it reads well (the Phase E
      discipline: adjust centers/sizes via element-update, re-render).
5. **On "done":** final render, show the ckfs path, and offer
   `gm prompt-diagram qualify` to persist the reading.

## Element vocabulary (payload `--content` JSON, kind tags)

`uml_node` (node_kind: db_cylinder|rounded_rect|triangle|rhombus|diamond|
circle; width/height; markdown body), `connector` (routing_kind:
orthogonal_step|straight|curved; head_kind/tail_kind: none|arrow|dot|
open_arrow|diamond|circle|cross; line_style solid|dashed; label),
`drawing_stroke` (freehand; vertices carry pressure), `drawing_text`
(block markdown box), `drawing_layer`, `dope_scope_persistence_layer` +
`dope_entity` (code bindings; ghosts legal). Connectors are children of
the element they LEAVE and target a peer of their parent — in one batch
use `parent_client_ref`/`target_client_ref`.

## Pre-flight

If `$GMCC_BOOTED` is unset:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

If the daemon is unreachable (gm exit 2): `bash
$GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, `gm context ensure`, retry.

ARGUMENTS: $ARGUMENTS
