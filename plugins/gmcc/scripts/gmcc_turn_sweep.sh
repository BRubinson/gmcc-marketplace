#!/bin/bash
# Stop / SubagentStop hook: per-turn capture. ONE process closes two holes.
#
#   1. Bash-driven writes never fire PostToolUse, so an agent that edits with
#      sed/heredocs and self-reports nothing leaves no file_change rows at all.
#      `gm bot sweep` diffs the working tree against the workflow's baseline
#      and records the delta with real create/edit/delete/rename kinds — the
#      same engine `gm bot reconcile` runs at phase gates, on a hook-safe skin.
#   2. The same invocation returns the derived phase and gate blockers, which
#      this script caches. The subagent status line reads that cache and never
#      spawns gm at all — the only shape that survives a command which runs on
#      every status refresh tick.
#
# MATCHERS: Stop and SubagentStop entries carry NO matcher key, deliberately.
# A workflow-spawned agent is launched with a prompt plus a schema/label and
# carries no `gmcc:` agent type, so an anchored alternation can never reach the
# agents that need this most.
#
# CORRECTNESS BOUNDARY — read this before trusting a row:
#   * PROMPT-level attribution and change KINDS are EXACT. They come from the
#     workflow's baseline tree and git's own diff, and they are what the audit
#     and the arch-get comparison read.
#   * AGENT-level attribution (--agent-id/--agent-name) is BEST-EFFORT and may
#     be WRONG under parallel fan-out: N agents race one baseline cursor, so
#     whoever's turn ends first is credited with whatever is on disk. agent_id
#     is bookkeeping, not evidence. Do not build a refusal on it until it has
#     been watched across a real parallel run.
#
# TWO ACTIVE WORKFLOWS IN ONE REPO is a normal state, and the sweep refuses it
# rather than guessing. `gm bot sweep` resolves only the workflow THIS
# session's client key claims; when more than one is in play and none is
# claimed, it records the refusal in the payload and sweeps nothing. A wrong
# row written at per-turn frequency is worse than a visible gap, and the
# refusal is surfaced in the status line rather than swallowed. Concurrent
# prompts in one repo therefore DO leave gaps — close them with an explicit
# `gm bot reconcile --prompt-uuid U` at the phase gate.
#
# The workflow is resolved BEFORE the git snapshot is taken (inside gm), so a
# turn in a booted repo with no active workflow — the overwhelmingly common
# case — costs one socket round trip and never re-hashes the tracked tree.
#
# CACHE CONTRACT (the status line's only input):
#   ${GMCC_ROOT:-$HOME/gmcc}/run/turn_sweep/<session_id>.json
#   {recorded, prompt_uuid, variant, phase, blockers[], refused?,
#    baseline_conflict?}
# There is deliberately NO per-agent array: the per-task JSON a status line
# receives carries no id that joins to a file_change row, so the honest
# delivered surface is one session-level phase/blocker line. Caching a field
# no consumer can use would only look like the feature.
#
# Hook contract: NEVER wedge a turn. Hard no-op unless GMCC is booted, every
# failure path exits 0 with no output, and nothing is ever written to stdout.
# A malformed Stop hook stalls every turn in the session, not just GMCC's.

[ -z "$GMCC_BOOTED" ] && exit 0

GM_BIN="$(command -v gm)" || exit 0

input="$(cat 2>/dev/null)" || input=""
session_id="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"
agent_id="$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)"
agent_name="$(jq -r '.agent_type // .agent_name // empty' <<<"$input" 2>/dev/null)"

# Filename hygiene: the session id lands in a path.
session_id="$(printf '%s' "${session_id:-default}" | tr -c 'A-Za-z0-9_.-' '_')"

root="${GMCC_ROOT:-$HOME/gmcc}"
lock="$root/sweep.lock"
cache_dir="$root/run/turn_sweep"
cache="$cache_dir/$session_id.json"

mkdir -p "$cache_dir" 2>/dev/null || exit 0

# Advisory lock. macOS ships no flock(1), so the portable atomic primitive is
# mkdir. This exists so two concurrent SubagentStop sweeps cannot interleave
# snapshot and baseline-advance; the compare-and-swap inside gm is the
# correctness backstop, never the thing that "handles" concurrency.
if ! mkdir "$lock" 2>/dev/null; then
  # Reclaim a lock orphaned by a killed turn; otherwise yield this turn — the
  # next sweep re-derives everything from the baseline, so nothing is lost.
  if [ -z "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    exit 0
  fi
  rmdir "$lock" 2>/dev/null
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

payload="$("$GM_BIN" bot sweep --json \
  ${agent_id:+--agent-id "$agent_id"} \
  ${agent_name:+--agent-name "$agent_name"} 2>/dev/null)" || payload=""

# gm exits 0 and reports refusals in the payload; an empty payload means gm
# itself could not run, which is still worth showing rather than hiding.
if [ -z "$payload" ] || ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
  payload='{"recorded":0,"blockers":[],"refused":"gm bot sweep produced no payload"}'
fi

# Atomic publish: the status line may read this file at any moment.
tmp="$cache.$$"
printf '%s\n' "$payload" >"$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null
rm -f "$tmp" 2>/dev/null

exit 0
