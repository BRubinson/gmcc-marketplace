#!/bin/bash
# PreToolUse(Bash) hook: refuse a spawned agent's `gm` WRITE invocations and
# name the pen tool that replaces each one.
#
# WHY THIS EXISTS. Withholding a tool from an MCP surface withholds the TOOL,
# never the CAPABILITY: every agent also holds Bash and `gm` is on the session
# PATH, so an agent that has no `file_change_add` pen tool still writes the row
# by typing `gm file-change add`. This run proved it empirically. The pen
# roster and the daemon's role door constrain the COMPLIANT channel; this hook
# is the only thing that sees the other one.
#
# HONEST STATEMENT OF WHAT THIS IS. String matching on a command line. `sh -c
# 'gm arch decide ...'`, an absolute path to the binary instead of the PATH
# name, an alias, or any script that wraps it all sail straight through, by
# construction and not by oversight. This is HABIT SHAPING, NOT ACCESS
# CONTROL. The server-side role refusal in VerbRegistry/Server.dispatch is the
# real boundary, and it covers only the pen. Anything an agent can reach
# through Bash it can still reach.
#
# AND IT CANNOT FIRE FOR TEAM-VARIANT TEAMMATES AT ALL. A teammate is a
# separate Claude Code session, not a Task subagent: its hook input carries no
# agent_id, so the first gate below lets it through, and `gm` stamps its
# messages .primary so the daemon door does not refuse it either. Team is the
# flagship variant. For teammates, the agent definitions and the workflow
# instructions are the whole of the enforcement.
#
# FAIL-OPEN IS THE CONTRACT, and it is not negotiable. A deny is emitted ONLY
# when BOTH hold:
#   1. agent_id is present in the hook input  (so this can never fire for the
#      primary — the primary's hook input has no agent_id), AND
#   2. a command position in the command line starts with a `gm` write verb
#      taken from `gm verbs --json`.
# Everything else — no agent_id, unparseable input, no jq, no gm, a registry
# that will not parse, a gm READ verb, any non-gm command — falls through to
# ALLOW by exiting 0 with no output. A bug in the matching below must never be
# able to wedge the primary's shell.
#
# KILL SWITCH: GMCC_PEN_ENFORCE=0 exits 0 before anything else runs.
#
# THE DENY REASON IS GENERATED, NEVER WRITTEN DOWN. It comes from
# `gm verbs --json` (VerbRegistry is the single declaration), so the tool it
# names cannot drift away from the pen roster the way a hand-maintained list
# in a hook would the moment the pen grows a tool. `gm verbs` is purely local
# — no daemon, no socket — because a guard that needs a live daemon to decide
# would fail closed exactly when the daemon is down.
#
# The `if` field in hooks.json is documented as BEST-EFFORT for Bash and is
# deliberately not used: the decision is made here, on the parsed command.
#
# SELF-TEST. `bash gmcc_gm_write_guard.sh --self-test` runs the ALLOW/DENY
# fixture table at the bottom of this file against this script, through a
# hermetic stand-in registry (no built binary, no daemon, no PATH `gm`). The
# parser below is the only thing in this change that can deny a command, and
# it is wrong in BOTH directions when it is wrong — run the fixtures after any
# edit to the segmenter or the peel loop.

GUARD_SELF="${BASH_SOURCE[0]:-$0}"

# ═══════════════════════════════════════════════════════════════════════════
#  The hook
# ═══════════════════════════════════════════════════════════════════════════
guard_main() {

# ── Gate 0: kill switch ────────────────────────────────────────────────────
[ "$GMCC_PEN_ENFORCE" = "0" ] && exit 0

# ── Gate 1: unbooted / no tools → allow ────────────────────────────────────
[ -z "$GMCC_BOOTED" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)" || exit 0
[ -z "$input" ] && exit 0
jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

# ── Gate 2: THE PRIMARY IS NEVER TOUCHED ───────────────────────────────────
# No agent_id means the primary (or a team teammate, see header). Allow.
agent_id="$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)"
[ -z "$agent_id" ] && exit 0

cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Cheap prefilter before the character scan below. A `gm` invocation contains
# the digraph `gm`; the overwhelming majority of Bash calls in a turn do not,
# and those must not pay for a parse at all — this hook runs on EVERY Bash
# tool call in every booted repo.
case "$cmd" in *gm*) ;; *) exit 0 ;; esac

# ── Find the COMMAND POSITIONS that invoke `gm` ────────────────────────────
# Only a segment that STARTS with `gm` counts. `gm explore finding-add` quoted
# inside an argument, or a path containing "gm", is not an invocation, and a
# guard that denied those would train agents to work around it.
#
# QUOTING IS TRACKED, because that rule is meaningless without it. A `;` or a
# `&&` or a `(` inside `git commit -m "note: x; gm review rank later"` is text,
# not a separator, and splitting on it manufactures a command position that
# never existed — a deny on a command that is not a gm invocation at all. The
# scanner below walks the command once, maintaining a context stack:
#   U  top-level unquoted      S  inside '…'      D  inside "…"
#   C  inside $( … )           B  inside ` … `
# Separators split only in U/C/B. Inside D, `$(` and a backtick still open a
# real command position (they are substitutions even when double-quoted) and
# everything else is literal text. Inside S nothing is a separator at all. A
# newline inside S or D becomes a space rather than a segment break, so a
# multi-line commit message cannot manufacture a command position either.
#
# HEREDOCS STOP THE SCAN, deliberately and in the fail-open direction: a line
# of heredoc BODY that happens to begin with `gm arch decide` (an agent writing
# documentation about this very rule) is indistinguishable from an invocation
# without parsing the shell, so inspection stops at an unquoted `<<`. Anything
# before it — including `gm arch general-add --code "$(cat <<EOF` — is still
# checked.
#
# An unbalanced quote leaves the scanner inside that context to the end of the
# command, which yields FEWER segments, never more: every failure mode of this
# parser has to land on the allow side.
#
# `e()` streams the result out in blocks instead of growing one string a
# character at a time: `out = out c` across a 200KB `--body` is quadratic in
# this awk and measured 3.4s, which is most of the hook's timeout budget spent
# on concatenation alone.
segments="$(printf '%s' "$cmd" | awk '
  function e(s) { p = p s; if (length(p) > 4096) { printf "%s", p; p = "" } }
  { buf = (NR > 1 ? buf "\n" : "") $0 }
  END {
    n = length(buf); depth = 0; st[0] = "U"; p = ""
    for (i = 1; i <= n; i++) {
      c = substr(buf, i, 1)
      nx = (i < n) ? substr(buf, i + 1, 1) : ""
      top = st[depth]
      if (top == "S") {                       # single quotes: nothing is special
        if (c == "\047") depth--
        else e(c)
        continue
      }
      if (top == "D") {                       # double quotes: only substitutions
        if (c == "\\")            { e(c nx); i++; continue }
        if (c == "\"")            { depth--; continue }
        if (c == "$" && nx == "(") { e("\n"); depth++; st[depth] = "C"; i++; continue }
        if (c == "`")             { e("\n"); depth++; st[depth] = "B"; continue }
        if (c == "\n")            { e(" "); continue }
        e(c)
        continue
      }
      # U / C / B — unquoted command text
      if (c == "\\")              { e(c nx); i++; continue }
      if (c == "\047")            { depth++; st[depth] = "S"; continue }
      if (c == "\"")              { depth++; st[depth] = "D"; continue }
      if (c == "`")               { if (top == "B") depth--; else { depth++; st[depth] = "B" }
                                    e("\n"); continue }
      if (c == "$" && nx == "(")  { e("\n"); depth++; st[depth] = "C"; i++; continue }
      if (c == ")")               { if (top == "C") depth--; e("\n"); continue }
      if (c == "<" && nx == "<")  { e("\n"); break }
      if (c == ";" || c == "&" || c == "|" || c == "(" || c == "{" || c == "}" || c == "\n") {
        e("\n"); continue
      }
      e(c)
    }
    printf "%s\n", p
  }' 2>/dev/null)" || exit 0

candidates=()
while IFS= read -r seg; do
  # strip leading whitespace
  seg="${seg#"${seg%%[![:space:]]*}"}"
  # Peel a leading `VAR=value` assignment and the transparent wrappers. THE
  # ASSIGNMENT TEST LOOKS AT THE FIRST WORD ONLY: a `case` glob cannot express
  # "identifier immediately followed by `=`" (its `*` are unanchored, so
  # `[A-Za-z_][A-Za-z0-9_]*=*` matches any segment with an `=` anywhere in it
  # — including every `--body "rating=0 …"` this guard exists to catch), so the
  # first word is split off and its name half is checked character-class-wise.
  # No `;&` fallthrough and no associative arrays anywhere in this file:
  # /bin/bash on macOS is 3.2. Each pass strictly shortens the string, so this
  # terminates.
  while :; do
    peel=0
    first="${seg%%[[:space:]]*}"
    case "$first" in
      *=*)
        name="${first%%=*}"
        case "$name" in
          ""|[0-9]*|*[!A-Za-z0-9_]*) ;;   # not a shell identifier → not an assignment
          *) peel=1 ;;
        esac
        ;;
    esac
    if [ "$peel" != 1 ]; then
      case "$seg" in
        "env "*|"command "*|"nohup "*|"time "*|"exec "*) peel=1 ;;
      esac
    fi
    [ "$peel" = 1 ] || break
    case "$seg" in
      *[[:space:]]*)
        seg="${seg#*[[:space:]]}"
        seg="${seg#"${seg%%[![:space:]]*}"}"
        ;;
      *) break ;;
    esac
  done
  case "$seg" in
    gm|gm[[:space:]]*) ;;
    *) continue ;;
  esac
  # collapse whitespace runs so `gm   arch    decide` compares like the
  # canonical invocation string
  norm="$(printf '%s' "$seg" | tr '\t' ' ' | tr -s ' ')"
  candidates+=("$norm")
done <<<"$segments"

[ ${#candidates[@]} -eq 0 ] && exit 0

# ── Ask the registry which invocations are writes ──────────────────────────
GM_BIN="$(command -v gm)" || exit 0
registry="$("$GM_BIN" verbs --json --writes-only 2>/dev/null)" || exit 0
[ -z "$registry" ] && exit 0
jq -e '.verbs' >/dev/null 2>&1 <<<"$registry" || exit 0

writes=()
while IFS= read -r v; do
  [ -n "$v" ] && writes+=("$v")
done < <(jq -r '.verbs[]? | select(.write == true) | .gm' <<<"$registry" 2>/dev/null)
[ ${#writes[@]} -eq 0 ] && exit 0

matched=""
for cand in "${candidates[@]}"; do
  for verb in "${writes[@]}"; do
    case "$cand" in
      "$verb"|"$verb "*) matched="$verb"; break 2 ;;
    esac
  done
done
[ -z "$matched" ] && exit 0

# ── Deny, with a reason generated from the registry ────────────────────────
pen="$(jq -r --arg gm "$matched" '.pen_replacements[$gm] // empty' <<<"$registry" 2>/dev/null)"
role="$(jq -r --arg gm "$matched" '[.verbs[]? | select(.gm == $gm) | .role][0] // empty' <<<"$registry" 2>/dev/null)"

if [ -n "$pen" ]; then
  reason="\`$matched\` is a gm WRITE verb, and agents record through the pen, not the CLI. Use the MCP tool mcp__plugin_gmcc_pen__${pen} instead — same row, attributed to you."
elif [ "$role" = "primary_door" ]; then
  doors="$(jq -r '(.primary_doors // []) | join(", ")' <<<"$registry" 2>/dev/null)"
  reason="\`$matched\` is one of the primary's gate doors (${doors:-$matched}). No spawned agent may walk one, through the pen or the CLI. Report your result and let the primary decide."
else
  reason="\`$matched\` is a gm WRITE verb with no pen replacement, so no agent may call it. Report what needs writing and let the primary run it."
fi
reason="$reason  (GMCC PreToolUse guard — read-only gm verbs are unaffected; GMCC_PEN_ENFORCE=0 disables this.)"

jq -cn --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}' 2>/dev/null || exit 0

exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
#  FIXTURES — `bash gmcc_gm_write_guard.sh --self-test`
#
#  Every row is a command line an agent could plausibly type and the decision
#  this guard must reach for it. The table is hermetic: it stands up a fake
#  `gm` that prints a fixed registry, so it exercises the SEGMENTER and the
#  PEEL LOOP and nothing else — it will not drift when VerbRegistry grows, and
#  it does not need a built binary or a live daemon to run.
#
#  Both halves matter and they pull in opposite directions:
#    DENY rows  guard against the guard going inert (fail-open).
#    ALLOW rows guard against the guard blocking real work (fail-closed) —
#               the more expensive failure, because it costs an agent a retry
#               with a deny reason that talks about pen tools for a command
#               that was never a gm invocation.
# ═══════════════════════════════════════════════════════════════════════════
guard_self_test() {
  command -v jq >/dev/null 2>&1 || { echo "self-test: jq is required"; return 2; }
  local tmp
  tmp="$(mktemp -d)" || return 2
  mkdir -p "$tmp/bin"

  cat >"$tmp/registry.json" <<'REGISTRY'
{
  "verbs": [
    { "gm": "gm review finding-add",  "write": true, "role": "record" },
    { "gm": "gm explore finding-add", "write": true, "role": "record" },
    { "gm": "gm file-change add",     "write": true, "role": "record" },
    { "gm": "gm backup",              "write": true, "role": "record" },
    { "gm": "gm arch decide",         "write": true, "role": "primary_door" },
    { "gm": "gm review rank",         "write": true, "role": "primary_door" }
  ],
  "pen_replacements": {
    "gm review finding-add":  "review_finding_add",
    "gm explore finding-add": "explore_finding_add",
    "gm file-change add":     "file_change_add"
  },
  "primary_doors": [ "gm arch decide", "gm review rank" ]
}
REGISTRY
  printf '%s\n' '#!/bin/sh' "cat '$tmp/registry.json'" >"$tmp/bin/gm"
  chmod +x "$tmp/bin/gm"

  guard_test_run=0
  guard_test_failed=0

  # $1 expected decision (deny|allow)   $2 command line   $3 mode
  # mode: agent (default) | primary (no agent_id) | killswitch
  _gt() {
    local expect="$1" cmdstr="$2" mode="${3:-agent}" json out got enforce=1
    if [ "$mode" = "primary" ]; then
      json="$(jq -n --arg c "$cmdstr" '{tool_input:{command:$c}}')"
    else
      json="$(jq -n --arg c "$cmdstr" '{agent_id:"agent-1", agent_type:"gmcc:explorer", tool_input:{command:$c}}')"
    fi
    [ "$mode" = "killswitch" ] && enforce=0
    out="$(printf '%s' "$json" | PATH="$tmp/bin:$PATH" GMCC_BOOTED=1 GMCC_PEN_ENFORCE="$enforce" \
             bash "$GUARD_SELF" 2>/dev/null)"
    got="allow"
    [ -n "$out" ] && got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
    guard_test_run=$((guard_test_run + 1))
    if [ "$got" = "$expect" ]; then
      printf 'ok    %-5s  %s\n' "$got" "$(printf '%s' "$cmdstr" | tr '\n' '~')"
    else
      printf 'FAIL  want=%s got=%s  %s\n' "$expect" "$got" "$(printf '%s' "$cmdstr" | tr '\n' '~')"
      guard_test_failed=$((guard_test_failed + 1))
    fi
  }

  echo "── DENY: real invocations in command position ─────────────────────────"
  _gt deny  'gm review finding-add --summary-uuid S --title T'
  _gt deny  'gm file-change add --path a --kind edit'
  _gt deny  'cd /tmp && gm explore finding-add --title T'
  _gt deny  'x=$(gm explore finding-add --title T)'
  _gt deny  'echo hi; gm arch decide --uuid U'
  _gt deny  'FOO=bar gm arch decide --uuid U'
  _gt deny  'FOO=bar BAZ=qux env gm review rank --uuid U'
  _gt deny  'gm   review    finding-add --title T'
  _gt deny  $'cd /tmp\ngm review rank --uuid U'

  echo "── DENY: an \`=\` in the PAYLOAD must not peel the invocation away ───────"
  # The shape this guard exists to catch is prose about code, and `x = y` is
  # near-universal in that prose. A peel that scans the argument list instead
  # of the first word makes the guard inert on its most common input.
  _gt deny  'gm review finding-add --body "rating=0 is critical" --title T'
  _gt deny  'gm explore finding-add --body "a=b and more"'
  _gt deny  'gm review finding-add --body "callerRole = .primary means x" --title T'

  echo "── ALLOW: a gm verb quoted inside another command's argument ──────────"
  # A separator inside a quoted string is text, not a command position.
  _gt allow 'git commit -m "note: x; gm review rank later"'
  _gt allow 'git commit -m "wire gm arch decide && gm review rank"'
  _gt allow 'echo "(gm arch decide)"'
  _gt allow "echo 'x; gm arch decide'"
  _gt allow 'rg "gm review rank" docs/'
  _gt allow 'echo gm review rank'
  _gt allow $'git commit -m "line one\ngm review rank in the body"'

  echo "── ALLOW: the fail-open contract ──────────────────────────────────────"
  _gt allow 'gm review finding-add --title T' primary      # no agent_id = the primary
  _gt allow 'gm review finding-add --title T' killswitch   # GMCC_PEN_ENFORCE=0
  _gt allow 'gm explore get --prompt-uuid U'               # a READ verb
  _gt allow 'ls -la'
  _gt allow 'cat <<EOF'
  _gt allow $'cat <<EOF\ngm arch decide --uuid U\nEOF'      # heredoc body is not scanned

  echo "── The deny reason is generated from the registry ─────────────────────"
  _gr() {
    local cmdstr="$1" want="$2" got
    got="$(jq -n --arg c "$cmdstr" '{agent_id:"agent-1", tool_input:{command:$c}}' \
           | PATH="$tmp/bin:$PATH" GMCC_BOOTED=1 bash "$GUARD_SELF" 2>/dev/null \
           | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
    guard_test_run=$((guard_test_run + 1))
    case "$got" in
      *"$want"*) printf 'ok    reason  names %s\n' "$want" ;;
      *) printf 'FAIL  reason  missing %s  (got: %s)\n' "$want" "$got"
         guard_test_failed=$((guard_test_failed + 1)) ;;
    esac
  }
  _gr 'gm review finding-add --title T' 'mcp__plugin_gmcc_pen__review_finding_add'
  _gr 'gm arch decide --uuid U'         "primary's gate doors"
  _gr 'gm backup'                       'no pen replacement'

  rm -rf "$tmp"
  echo "──────────────────────────────────────────────────────────────────────"
  echo "$guard_test_run checks, $guard_test_failed failed"
  [ "$guard_test_failed" -eq 0 ]
}

case "$1" in
  --self-test) guard_self_test; exit $? ;;
esac

guard_main
exit 0
