# KBite Trigger Awareness Reference

<!-- [FIX #2] Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file when working with kbites or when trigger matching is needed. -->

## Trigger Check Protocol (CRITICAL)

The KBite system provides persistent, indexed knowledge at `$GMCC_CKFS_ROOT/kbites/`.

**On EVERY prompt**, before beginning work:

1. **Scan for triggers**: Parse the user prompt for keywords that might match kbite triggers
2. **Check available kbites**: For each kbite in `$GMCC_CKFS_ROOT/kbites/`:
   - Read `KBITE_TRIGGERS.md`
   - Check for keyword matches with confidence > 70
3. **Load relevant knowledge**: If triggers match:
   - Read `KBITE_TRIGGER_MAP.md` to find relevant resources
   - Load the mapped `*_chewed.md` files
   - Include this knowledge in your working context
4. **Cite sources**: When using kbite knowledge, cite the source:
   - "Per the claude_code_sdk kbite..."
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
