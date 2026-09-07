# gmcc-marketplace

Monorepo for the GM-CDE (Green Mountain Contextual Development
Environment). GMB identity and behavioral rules are NOT here — they live
plugin-globally in `plugins/gmcc/skills/gmcc/SKILL.md` so every
gmcc-booted repo gets them, not just this one.

## Layout

- `plugins/gmcc/` — the Claude Code plugin: skills, commands, prompts,
  hooks, scripts, and the daemon Swift package
  (`plugins/gmcc/daemon/` → `GMCCDaemonKit` + `gm` + `gmcc_daemon`).
- `gmvibes/` — the GMVibes macOS app (Swift/SwiftUI), building against the
  daemon package via a direct local package reference. Release via the
  `release-dmg` skill.
- `.gmcc/dope/` — this repo's committed DOPE tree (Domain Optimized
  Project Essence); sessions boot-sync their dope scope from it.

## Build / test loop

```bash
cd plugins/gmcc/daemon && swift test          # full suite; must stay green
bash plugins/gmcc/scripts/build_daemon.sh     # release build → ~/gmcc/bin/
gm daemon restart                             # pick up the new daemon
```

- `CheatsheetTests` fails the build when a verb ships without a
  `Cheatsheet.text` line; `DocsContractTests` fails it when docs regress
  (hardcoded gm paths, retired env names, retired DOPE acronym).
- Wire protocol: bump `GMCCWireProtocol.version` only for a new message
  type or an incompatible change. Additive OPTIONAL fields on existing
  messages do NOT bump — they decode safely in both directions (that
  convention is what keeps GMVibes' vendored kit compatible).
- Schema: migrations are append-only. The db at `~/gmcc/gmcc.db` is
  append-only history — NEVER wipe it; `gm backup` before risky work.

## Environment rules

- Sessions are provisioned by `gm context env` at SessionStart; the only
  env vars are GMCC_BOOTED, GMCC_PLUGIN_ROOT, GMCC_CKFS_ROOT, PATH
  (+ GMCC_ROOT when sandboxed). Everything else: `gm paths --json`.
- GMCC never writes the user's shell profile. PATH install is
  `gm setup --install-path` (a call-time resolver shim), and remediation
  lines are printed, not applied.
- env and db must always agree on the roots (mismatch = warning at boot;
  `gm doctor` audits it). Sandbox snapshots keep them in agreement by
  construction (`gm sandbox refresh` retargets the staged db).

## Sandbox dev loop

`gm sandbox refresh` (prod only) stands up
`{ckfs_root}/development/local_sandbox` — snapshot db, repo clone,
binaries, launchers. Sessions started inside the snapshot auto-sandbox via
`.gmcc_sandbox`; sandboxed gm/daemon never touch the prod db. Never
`gm setup --launchd` or `gm setup --install-path` in a sandbox (both
refuse under GMCC_ROOT).

## Working-tree note

Uncommitted sandbox-feature edits in the working tree are usually
intentional — validate against the working tree, don't "fix" them back to
HEAD without asking.
