---
name: gm_compile
description: Run a YEETS pass over a project / instance / session. Validates `.yeet.yaml` files, inline `<YEET>` blocks in markdown, and any `.yaml` file with a top-level `yeet:` imports list. Reports pass/fail per file. Read-only.
argument-hint: <project> <instance> <session>
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# GM-CDE Compile — YEETS Validation Pass (v6.2.0)

You are running a YEETS type-check over a specific session of a specific instance of a specific project. The full YEETS grammar lives in `$GMCC_PLUGIN_ROOT/skills/gmcc/SKILL.md` under `## YEETS`. Read that section if it is not already in context — it is the authoritative spec, and this command must agree with it.

`/gm_compile` is **read-only by contract**. Do NOT modify any file.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

---

## Argument Parsing

Parse `$ARGUMENTS` as exactly three positional tokens: `<project> <instance> <session>`.

- `<project>` — project name (matches an entry in `$GMCC_PROJECTS_INDEX` / a directory under `$GMCC_PROJECTS/`).
- `<instance>` — instance id (a directory under `$GMCC_PROJECTS/<project>/instances/`).
- `<session>` — sanitized branch name (a directory under `$GMCC_PROJECTS/<project>/instances/<instance>/sessions/`).

If fewer than three tokens, AskUserQuestion to gather what's missing. If a path does not resolve, error with the **deepest existing ancestor directory** (longest path prefix that exists when walking the segments left-to-right):
```
[GM_COMPILE] Path does not resolve: <attempted path>
Deepest existing ancestor: <prefix>
```

Resolved paths (use these throughout):
- `TARGET_PROJECT_PATH = $GMCC_PROJECTS/<project>`
- `TARGET_INSTANCE_PATH = $TARGET_PROJECT_PATH/instances/<instance>`
- `TARGET_SESSION_PATH = $TARGET_INSTANCE_PATH/sessions/<session>`

---

## Glob Conventions

For every Glob/Grep across the four roots, exclude:
- `.git/`, `node_modules/`, `dist/`, `build/`, `_archive/`
- `$GMCC_PLUGIN_ROOT/templates/` (template tree may carry stub `.yeet.yaml` files in the future; not live packages)

For Phase 4 only, additionally exclude the YEETS spec docs themselves so prose mentions of `<YEET>` don't false-fail:
- `$GMCC_PLUGIN_ROOT/skills/gmcc/SKILL.md`
- `$GMCC_PLUGIN_ROOT/commands/gm_compile.md`
- `$GMCC_PLUGIN_ROOT/MIGRATION.md`

---

## Phase 1: Discover `.yeet.yaml` Files

Glob the union of:
- `$GMCC_PLUGIN_ROOT/*.yeet.yaml` (plugin-shipped packages live flat at plugin root, not nested)
- `$TARGET_PROJECT_PATH/**/*.yeet.yaml`
- `$TARGET_INSTANCE_PATH/**/*.yeet.yaml`
- `$TARGET_SESSION_PATH/**/*.yeet.yaml`

For each, parse as pure YAML. Read the following keys:

**Top-level keys:**
- `name:` — required, string. The human-readable name of the type package.
- `uuid:` — required, uuid. A v4 UUID unique to this package.
- `package:` — required, string. The dotted package identifier (e.g. `gmcc`, `payments`, `ui.graphs.line`).
- `yeet_version:` — optional, string. The YEETS grammar version this file targets. Defaults to the current version when absent.
- `yeet:` — optional, list of dotted-package strings. Declares package-level imports. Defaults to `[]` when absent.
- `description:` — optional, string (YAML literal block). Free-text description of the package.
- `sections:` — required, map. Keyed by section name (snake_case). The `default:` section (lowercase) is mandatory.

**Per-section value:**
- `description:` — optional, string.
- `enums:` — required, default `{}`.
- `structs:` — required, default `{}`.

Note: the v6.1.x `.yeet.md` format is removed — `.yeet.yaml` is the only type package format.

Record violations: missing required top-level key (`name:`, `uuid:`, `package:`, `sections:`), nil UUID that isn't the canonical `gmcc` bootstrap package (warning only), duplicate UUID across files (error), missing `default:` section, missing `enums:` or `structs:` inside any section, unresolved import (no other `.yeet.yaml` declares that `package:`), circular import chain.

---

## Phase 2: Discover Importing `.yaml` Files

Glob `.yaml` files across all four roots (same union as Phase 1, with the same exclusions). For each yaml with a top-level `yeet:` key, record:
- The list of declared imports.
- Whether each import resolves to a package discovered in Phase 1.
- The value of the top-level `yeet_type:` key, if present (dotted form: `<package>.<struct_name>` or `<package>.<section>.<struct_name>` for non-DEFAULT sections).

A yaml with `yeet:` but no `yeet_type:` is documentation-only — imports must resolve, but field-level validation is skipped (treated as a pass with an informational note).

---

## Phase 3: Validate Field Types

For each yaml from Phase 2 that has a `yeet_type:`:
1. Resolve `yeet_type:` to a specific struct in the imported scope. If unresolvable, record error.
2. Build the type scope: union of every struct + enum declared in the imported packages' relevant sections. On name collision across imports, require a qualified reference (`<package>.<name>`); unqualified collisions are an error.
3. For every field declared in the target struct:
   - Required fields (no `?` suffix) must be present.
   - Nullable fields (`?` suffix) tolerate missing/null.
   - Field value's surface type matches the declared YEETS type — primary types (`string`, `int`, `decimal`, `timestamp`, `character`), collections (`Map<...>`, `List<...>`, `Set<...>`), `Enum<...>`, `Struct<...>`.
   - Enum values match a declared enum variant (per the `variable | string` pair).

v6.0.x scope: **outer type only**. Parametric type arguments inside `Map<K,V>`, `List<T>`, `Set<T>` are NOT recursively validated against element-level structs in this release. Deep nested-generic validation lands in v6.1.

Record each violation with file + line + expected vs actual.

---

## Phase 4: Validate Inline `<YEET>` Blocks

Grep every `.md` file under the same union of roots (with the spec-docs exclusion noted above) using a **case-insensitive** pattern (`<[Yy][Ee][Ee][Tt]>`). For each opening match:
- If the tag is not exactly `<YEET>` (any other casing), record violation: "wrong tag casing".
- If the match is inside a fenced code block (between ```` ``` ```` lines), skip — these are illustrative.
- Otherwise, locate the matching `</YEET>` closing tag and validate the body as the `enums:` / `structs:` parent-map grammar from `SKILL.md ## YEETS`. Both keys are required (use `{}` when empty). No `###` headers in inline form.

Record: unmatched tags, wrong-case tags outside code fences, malformed bodies.

---

## Phase 5: Report

Emit a structured pass/fail report:

```
GM-CDE Compile — YEETS Pass
Project: <project>
Instance: <instance>
Session: <session>

Yeet files:      N total, P passed, W warnings, F failed
Yaml imports:    N total, P passed, F failed
Inline <YEET>:   N total, P passed, F failed

Warnings:
  <relative path>  <one-line reason>
  ...

Failures:
  <relative path>:<line>  <one-line reason>
  ...
```

If no failures, conclude with `YEETS pass: clean`. Otherwise surface the failure list and conclude with `YEETS pass: <N> failure(s)`. Either way, no files are modified.

---

## Error Handling

**No yeet artifacts found:**
```
[GM_COMPILE] Nothing to compile.

No `.yeet.yaml`, no yaml with `yeet:` imports, and no `<YEET>` blocks found
under the target paths. Nothing to do.
```
