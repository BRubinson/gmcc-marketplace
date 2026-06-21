# KBite Awareness Reference

<!-- Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when working with kbites. -->

## KBite Loading Protocol

The KBite system provides persistent, indexed knowledge at `$GMCC_KBITE_DIGESTED/`.

KBites are **inherited, not trigger-matched**. The kbites relevant to the current
work are declared up the ckfs hierarchy — project → instance → session → prompt —
and recorded in each level's `kbite:` registry. There is no per-prompt keyword
scan and no automatic activation.

To use kbite knowledge:

1. **Read the registry**: the active kbites are listed in
   `$GMCC_SESSION_PATH/session_data.gmcc.yaml`'s `kbite:` field (and, for a
   specific prompt, the prompt's own `kbite:` list). Wider context — the instance
   and project `kbite:` registries — is available on demand.
2. **Load on demand**: for a registered kbite, read
   `$GMCC_KBITE/{name}/KBITE_PURPOSE.md` + `$GMCC_KBITE_DIGESTED/{name}/KBITE_INDEX.md`,
   then load the relevant `*_chewed.md` files. Explore freely with Bash
   (`find`, `cat`, `rg`) — you have read-only run of the ckfs tree.
3. **Explicit add only**: add a kbite to a registry only when the user explicitly
   asks for it. Never add one on your own initiative.
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
