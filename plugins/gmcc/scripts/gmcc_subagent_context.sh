#!/bin/bash
# SubagentStart hook: provision every gmcc agent with the compact cheatsheet
# core plus its daemon-composed briefing stub — zero primary-context tokens,
# zero paste mandates. The daemon does the thinking (gm briefing stub walks
# session -> this instance's activation -> the role's step); this script is a
# deliberately dumb shim.
#
# Hook contract: NEVER wedge a spawn. Hard no-op unless GMCC is booted, every
# failure path exits 0 with no output.

[ -z "$GMCC_BOOTED" ] && exit 0

GM_BIN="$(command -v gm)" || exit 0

agent_type="$(jq -r '.agent_type // empty' 2>/dev/null)" || agent_type=""

core="$("$GM_BIN" cheatsheet 2>/dev/null)" || core=""
stub="$("$GM_BIN" briefing stub ${agent_type:+--agent-type "$agent_type"} 2>/dev/null)" || stub=""

ctx="$core"
if [ -n "$stub" ]; then
  ctx="$ctx

$stub"
fi
[ -z "$ctx" ] && exit 0

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $ctx}}' 2>/dev/null

exit 0
