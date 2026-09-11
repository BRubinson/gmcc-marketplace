#!/bin/bash
# subagentStatusLine: one decoration line per visible agent row in the agent
# panel, answering "which phase, what is blocking" without spawning anything.
#
# THIS SCRIPT NEVER CALLS gm. Not per row, not per tick. The harness re-runs
# this command on EVERY status refresh (~5s while agents are live), and the
# per-task JSON it hands us carries only a harness task id — no agent_id, no
# prompt link — so a per-row `gm bot next` is structurally wrong twice over:
# it would spawn N daemon round trips per tick, and it would have nothing to
# key them on. Instead the phase is refreshed by the turn boundary that
# actually changes it: gmcc_turn_sweep.sh writes the payload of the
# `gm bot sweep --json` call it was already making into a per-session cache,
# and this script only reads that file.
#
# NO CACHE IS THE NORMAL CASE, not an error. The sweep is not wired to any
# hook event right now — it is held back pending validation that PostToolUse
# genuinely misses agent Edit/Write calls on the officially installed plugin —
# so unless something ran it by hand there is no cache and every row is
# undecorated. That is the correct rendering, and every path below that cannot
# produce a dated phase collapses onto it.
#
# CACHE CONTRACT (gmcc_turn_sweep.sh is the sole writer):
#   ${GMCC_ROOT:-$HOME/gmcc}/run/turn_sweep/<session_id>.json
#   {recorded, prompt_uuid, variant, phase, blockers[], refused?,
#    baseline_conflict?}
# The payload has NO per-agent array, deliberately — see that script's header.
# Every row in the panel therefore shows the same SESSION-LEVEL phase and
# blockers, prefixed by its own name. That is the honest delivered surface:
# the intent asked for per-agent prompt attribution and the harness gives us
# no id to join on.
#
# REFUSALS BEAT STALE PHASES, and the payload alone cannot deliver that. The
# refusal the writer records in `refused` covers exactly one case — ambiguous
# workflow ownership — and is rendered below. Every OTHER way capture stops is
# an early `exit 0` in the writer that never reaches the publish step at all:
# GMCC not booted, `gm` not on PATH, the sweep lock held by another turn, or
# the hook simply not being wired. None of those touch the cache, so the last
# good payload would otherwise render as a confident `implement · clear`
# forever — after the prompt closes, after the operator moves to another
# prompt, after `gm` disappears mid-session. "Phase X" while capture is off is
# a lie that reads like a feature, and a healthy run and a dead one must not
# look identical.
#
# FRESHNESS IS THE CACHE FILE'S OWN mtime. The payload carries no timestamp,
# and it does not need one: because every early exit above leaves the file
# untouched, its mtime IS the moment of the last SUCCESSFUL sweep — the same
# fact a `swept_at` field inside the payload would carry, obtained without the
# writer having to cooperate. Older than GMCC_STATUSLINE_MAX_AGE_MIN minutes
# (default 10) and the cache is treated as ABSENT: no phase, no blockers, no
# row text. So is a cache this script cannot date at all. Unknown beats stale;
# stale looks healthy.
#
# HOW THIS IS LAUNCHED, and why the launcher in ../settings.json is not the
# bare path it looks like it should be. A plugin's settings.json accepts
# exactly two keys — "agent" and "subagentStatusLine" — so this ships from
# the plugin without touching user settings. But unlike hooks.json, the value
# gets NO ${CLAUDE_PLUGIN_ROOT} expansion: the harness merges plugin settings
# into a flat object that no longer carries the plugin's directory, so there
# is nothing left to expand from, and the status line is spawned with a plain
# shell and no CLAUDE_PLUGIN_ROOT in its environment. A bare
# "${CLAUDE_PLUGIN_ROOT}/scripts/..." would run as "/scripts/..." and exit
# 127 on every refresh tick. The launcher therefore takes CLAUDE_PLUGIN_ROOT
# if some future harness does expand it, falls back to GMCC_PLUGIN_ROOT from
# the session env, and exits 0 in silence if neither resolves — a wrong path
# must cost nothing, not an error line every five seconds. JSON carries no
# comments, which is why that reasoning lives here.
#
# Contract: stdout is JSONL, one {"id","content"} per row, nothing else ever.
# Any other byte on stdout is logged by the harness as a schema error at tick
# frequency. Every failure path prints nothing and exits 0 — a nonzero exit
# is logged every ~5s for the life of the session.

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)" || exit 0
[ -z "$input" ] && exit 0

session_id="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"

# Filename hygiene, byte-identical to the writer's — the session id lands in
# a path on both sides and the two must agree exactly or the cache is missed.
session_id="$(printf '%s' "${session_id:-default}" | tr -c 'A-Za-z0-9_.-' '_')"

cache="${GMCC_ROOT:-$HOME/gmcc}/run/turn_sweep/$session_id.json"

# No cache means no sweep has published one for this session — the ordinary
# state while the sweep is unwired, and also what a not-booted repo looks like.
# Decorating nothing is the correct answer; inventing a phase is not.
[ -s "$cache" ] || exit 0

# EXPIRY. `find -mmin +N` rather than `stat`, because the two stat flavours
# disagree on flags (BSD -f %m vs GNU -c %Y) and find is the portable primitive
# the writer already uses for its own lock reclaim.
max_age="${GMCC_STATUSLINE_MAX_AGE_MIN:-10}"
case "$max_age" in
  '' | *[!0-9]* | 0) max_age=10 ;;
esac

# A cache that cannot be dated is a cache that cannot be trusted: find failing
# means the file vanished under us or the filesystem will not answer, and
# either way the honest render is none. Same exit as a stale one.
aged="$(find "$cache" -maxdepth 0 -mmin "+$max_age" 2>/dev/null)" || exit 0
[ -n "$aged" ] && exit 0

out="$(jq -c --slurpfile cache "$cache" '
  def trunc($n): if ($n > 1 and (length > $n)) then (.[0:$n - 1] + "…") else . end;

  ($cache[0] // {}) as $c
  | (($c.blockers // []) | map(select(type == "string" and . != ""))) as $bl
  | (if (($c.refused // "") | length) > 0 then
       "sweep refused: " + ($c.refused | trunc(90))
     else
       ($c.phase // "no phase")
       + " · "
       + (if ($bl | length) == 0 then
            "clear"
          else
            ($bl[0] | trunc(60))
            + (if ($bl | length) > 1
               then " (+" + (($bl | length) - 1 | tostring) + ")"
               else "" end)
          end)
       + (if (($c.baseline_conflict // "") | length) > 0
          then " · baseline held"
          else "" end)
     end) as $tail
  | ((.columns // 80) | if (type == "number" and . > 20) then . else 80 end) as $cols
  | (.tasks // [])[]
  | select((.id | type) == "string")
  | {
      id: .id,
      content: (
        (((.name // .label // .description // "agent") | tostring | trunc(28))
         + " · " + $tail)
        | trunc($cols)
      )
    }
' <<<"$input" 2>/dev/null)" || exit 0

[ -n "$out" ] && printf '%s\n' "$out"
exit 0
