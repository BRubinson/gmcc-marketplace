#!/bin/bash

# GMCC daemon staleness check — v16.0.0
#
# SessionStart hook: warn (never block) when the installed daemon binaries are
# missing or older than the daemon package sources. Plugin root derived from
# this script's location (dirname trick), same as detect_repo.sh.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GMCC_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DAEMON_PKG="$GMCC_PLUGIN_DIR/daemon"
GMCC_BIN="$HOME/gmcc/bin"

# No daemon package in this plugin build — nothing to check.
[ -f "$DAEMON_PKG/Package.swift" ] || exit 0

if [ ! -x "$GMCC_BIN/gmcc_daemon" ] || [ ! -x "$GMCC_BIN/gm" ]; then
    echo "[GMB] gmcc daemon binaries not installed — run /gmcc_daemon build"
    exit 0
fi

if [ -n "$(find "$DAEMON_PKG/Sources" "$DAEMON_PKG/Package.swift" -newer "$GMCC_BIN/gmcc_daemon" -print -quit 2>/dev/null)" ]; then
    echo "[GMB] gmcc daemon binary stale (sources newer than ~/gmcc/bin/gmcc_daemon) — run /gmcc_daemon build"
fi

exit 0
