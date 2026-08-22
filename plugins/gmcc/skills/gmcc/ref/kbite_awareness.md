# KBite Awareness Reference

<!-- Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when working with kbites. -->

## KBite Loading Protocol

The KBite system provides persistent, indexed knowledge. Digested text,
keywords, and search live in the daemon db (read via `gm kbite`); the
filesystem keeps each kbite's identity (`$GMCC_KBITE/{name}/KBITE_PURPOSE.md`)
and raw-source archive (`$GMCC_KBITE_DIGESTED/{name}/`).

KBites are **inherited, not trigger-matched**. The kbites relevant to the
current work are seeded down the hierarchy — project → instance → session →
prompt — into the db's active-kbite registries at row-create time. There is
no per-prompt keyword scan and no automatic activation.

To use kbite knowledge:

1. **Read the registry**: the active kbites for the current session are the
   `kbite_codes` in `gm session get --json` / `gm context get --json` (for a
   specific prompt, `gm prompt get --prompt-uuid U --json`); scoped listing
   via `gm kbite list --scope project|instance|session|prompt`
   (`gm kbite list --all` for every kbite in the db).
2. **Load on demand**: for a registered kbite, read
   `$GMCC_KBITE/{name}/KBITE_PURPOSE.md`, then query the db:
   `gm kbite get --code {name} --json` (resources + file stubs + keywords),
   `gm kbite search "<query>" --json` (ranked stubs across kbites; scope with
   `--kbite-uuids`), and `gm kbite file-get --file-uuid U --json` (full file
   content — the targeted load).
3. **Explicit add only**: add a kbite to a registry only when the user
   explicitly asks for it (`gm kbite add --code C --scope S [--owner-uuid U]`).
   Never add one on your own initiative.
4. **Cite sources**: when using kbite knowledge, cite the source:
   - "Per the swift_code_edit kbite..."
   - "According to kbite knowledge..."

## When to Suggest New KBites

GMB should suggest creating a kbite when:
- User repeatedly references the same external documentation
- A new SDK/library/tool is being integrated
- Complex domain knowledge needs persistent reference
- Current context would benefit from pre-analyzed material

Suggest: "This looks like a good candidate for a kbite. Run `/gm_crunch_open_maw {suggested_name}` to start collecting resources."

## KBite System Reference

Full kbite system documentation is in `$GMCC_PLUGIN_ROOT/skills/gmcc_kbite/SKILL.md`
