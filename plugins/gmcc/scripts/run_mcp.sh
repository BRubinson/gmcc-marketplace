#!/bin/bash

# GMCC MCP server launcher (m0025) — the plugin's .mcp.json points here.
#
# Call-time resolver shim (the gm setup --install-path precedent): resolves
# the installed gmcc_mcp under the runtime bin, self-heal-building via
# build_daemon.sh when it is missing (the gm shim's self-heal rule) — a
# session must never run a stale or absent MCP server against a newer
# daemon. Sandbox sessions honor GMCC_ROOT exactly like every other
# launcher.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_BIN="${GMCC_ROOT:-$HOME/gmcc}/bin"

# build_daemon.sh runs its own find -newer staleness check and no-ops fast
# when fresh — run it unconditionally so a stale gmcc_mcp never serves a
# newer daemon (stdout belongs to the MCP protocol from exec onward).
bash "$SCRIPT_DIR/build_daemon.sh" >&2 || exit 1

exec "$GMCC_BIN/gmcc_mcp"
