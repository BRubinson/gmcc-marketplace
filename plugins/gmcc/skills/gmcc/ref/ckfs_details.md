# CKFS Detailed Structure Reference

<!-- Extracted from core SKILL.md to reduce auto-loaded context.
     Read this file on-demand when performing ckfs operations. -->

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json  # Plugin manifest
├── skills/gmcc/SKILL.md        # Core rules (slim)
├── skills/gmcc/ref/            # Reference files (read on-demand)
├── skills/gmcc_agent/          # Agent system definition
├── skills/gmcc_kbite/          # KBite knowledge system definition
├── commands/gm_*.md            # All GM commands
├── prompts/gmcc_agent_*.md     # GMCC agent prompt files
├── scripts/                    # Hook scripts
├── hooks/hooks.json            # Hook configuration
├── output-styles/              # Methodology output styles
└── ckfs_templates/             # Templates for ckfs initialization
```

## Shared Runtime Files (Per-Repository CKFS)
```
~/gmcc_ckfs/{repo}/
└── fam/
    └── {branch_name}/
        ├── ChangedFiles.md         # Files modified on this branch
        ├── compact_recovery.md     # Compaction state (auto-generated)
        └── thoughts/
            └── mem_{index}_{name}/ # Bot workflow memory sets
                ├── session_meta.md
                ├── fully_clarified_prompt.md
                └── ... (workflow-specific files)
```

The repo CKFS holds nothing above `fam/` — no indexes, no purpose docs, no changelog. Everything lives in the branch FAM, and only `ChangedFiles.md` + immutable `thoughts/` survive there.

## System-Level KBites
```
~/gmcc_ckfs/kbites/                       # $GMCC_KBITE
├── digested/                             # $GMCC_KBITE_DIGESTED
│   └── {kbite_name}/
│       ├── KBITE_PURPOSE.md
│       ├── KBITE_INDEX.md
│       ├── KBITE_TRIGGERS.md
│       ├── KBITE_TRIGGER_MAP.md
│       ├── KBITE_RELATIONSHIPS.md
│       ├── primary/{axis2}/...
│       └── secondary/{axis2}/...
└── open/                                 # $GMCC_KBITE_OPEN — in-progress maws
    └── {kbite_name}/
        ├── MAW_INDEX.md
        ├── primary/{axis2}/...
        └── secondary/{axis2}/...
```

## FAM Per-Branch Files

| File | Purpose | Editable By |
|------|---------|-------------|
| `ChangedFiles.md` | Files modified + diffs | GMB maintains |
| `thoughts/` | Bot memory sets and snapshots | GMB writes (immutable) |

## Thought System

Bot workflows write structured artifacts to `$GMCC_FAM_PATH/thoughts/mem_{index}_{name}/`:
- `session_meta.md` — Session metadata, kbites loaded, phase history
- `fully_clarified_prompt.md` — Clarified requirements
- `exploration_report.md` / `relevant_implementation_report.md` — Findings
- `architecture_document.md` / `architecture_discussion_result.md` — Design
- `review_report.md` — Code review findings

Thoughts are **immutable** once written. Never edit — only append new files.
