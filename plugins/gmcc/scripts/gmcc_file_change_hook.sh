#!/bin/bash
# PostToolUse(Edit|Write|NotebookEdit) hook: deterministic file-change
# bookkeeping. Replaces the "never forget gm file-change add" instruction
# class — the edit is recorded whether or not the model remembers, attributed
# through the daemon's activation registry (--auto-attribute: this Claude
# instance's claimed prompt first, then the session's single claim, else the
# row stays session-scoped/unattributed).
#
# Known residual gap, accepted: Bash-driven writes don't fire PostToolUse.
#
# Hook contract: NEVER block an edit. Hard no-op unless GMCC is booted; every
# failure path exits 0 silently. async in hooks.json keeps edit latency zero.

[ -z "$GMCC_BOOTED" ] && exit 0

GM_BIN="$(command -v gm)" || exit 0

input="$(cat 2>/dev/null)" || exit 0
file_path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)"
[ -z "$file_path" ] && exit 0

# Only record files inside the BOOTED repo — "inside some git repo" is not
# enough ($HOME itself can be a git toplevel, and ckfs/kbite clones are git
# repos too; foreign paths would land as junk rows in the append-only db).
booted_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
repo_root="$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ "$repo_root" = "$booted_root" ] || exit 0
case "$file_path" in
  "$repo_root"/*) ;;
  *) exit 0 ;;
esac
rel_path="${file_path#"$repo_root"/}"

# Write-to-a-new-path is a create; everything else records as an edit
# (coarse by design — attribution is the value, not kind fidelity).
kind="edit"
tool_name="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
if [ "$tool_name" = "Write" ] && ! git -C "$repo_root" ls-files --error-unmatch "$rel_path" >/dev/null 2>&1; then
  kind="create"
fi

"$GM_BIN" file-change add --path "$rel_path" --kind "$kind" --auto-attribute >/dev/null 2>&1

exit 0
