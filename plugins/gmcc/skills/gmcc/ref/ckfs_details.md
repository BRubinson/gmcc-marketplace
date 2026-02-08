# CKFS Detailed Structure Reference

<!-- [FIX #2] Extracted from core SKILL.md to reduce auto-loaded context.
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
├── REPOSITORY_INDEX.md      # Cross-repo relationships
├── GREATER_PURPOSE.md       # Human-maintained project goal
├── SRC_INDEX.md             # Source file index
├── FAM_INDEX.md             # Branch/FAM index
├── CHANGELOG.md             # Version history
├── resource/                # Reference materials
└── fam/
    └── {branch_name}/
        ├── Purpose.md       # Branch purpose
        ├── Tasks.md         # Task checklist
        ├── ChangedFiles.md  # Modified files
        ├── Famalouge.md     # Compiled thoughts
        ├── compact_recovery.md  # Compaction state (auto-generated)
        ├── thoughts/
        │   ├── mem_{index}_{name}/  # Bot workflow memory sets
        │   │   ├── session_meta.md
        │   │   ├── fully_clarified_prompt.md
        │   │   └── ... (workflow-specific files)
        │   └── {timestamp}_{topic}.md  # Legacy individual thoughts
        └── maw/             # Temporary kbite processing (crunchables)
```

## System-Level KBites
```
~/gmcc_ckfs/kbites/
└── {kbite_name}/
    ├── KBITE_PURPOSE.md
    ├── KBITE_INDEX.md
    ├── KBITE_TRIGGERS.md
    ├── KBITE_TRIGGER_MAP.md
    ├── KBITE_RELATIONSHIPS.md
    ├── primary/
    │   ├── documentation/
    │   ├── example_project/
    │   ├── api_reference/
    │   ├── blogs/
    │   └── all_others/
    └── secondary/
        └── (same structure)
```

## ckfs Maintenance Rules

### SRC_INDEX.md Format
```markdown
| Path | Keywords | Elevator Pitch | Key Exports |
|------|----------|----------------|-------------|
| src/auth/login.ts | auth, login, jwt | Handles user authentication via JWT tokens. | `login()`, `validateToken()` |
```

### FAM_INDEX.md Format
```markdown
| Branch | Purpose | Opened | Closed | Files Changed |
|--------|---------|--------|--------|---------------|
| feature/auth | Implement JWT authentication | 2024-01-15 | 2024-01-20 | src/auth/*, tests/auth/* |
```

### CHANGELOG.md Format
```markdown
## [1.2.0] - 2024-01-20
### Added
- JWT authentication system
### Fixed
- Memory leak in cache manager
```

## FAM Core Files

| File | Purpose | Maintainer |
|------|---------|------------|
| `GREATER_PURPOSE.md` | Project's ultimate goal | Human only |
| `SRC_INDEX.md` | Index of all source files | GMB on merge |
| `FAM_INDEX.md` | Index of all FAMs | GMB on branch events |
| `CHANGELOG.md` | Version history | GMB on merge |

## FAM Per-Branch Files

| File | Purpose | Editable By |
|------|---------|-------------|
| `Purpose.md` | Why this branch exists | Human (GMB can format) |
| `Tasks.md` | Checklist of work items | GMB maintains |
| `ChangedFiles.md` | Files modified + diffs | GMB maintains |
| `Famalouge.md` | Compiled internal monologue | GMB compiles |
| `thoughts/` | Individual thought snapshots | GMB writes (immutable) |

## Thought System

### Bot Workflow Memory (Primary)
Bot workflows write structured artifacts to `$GMCC_FAM_PATH/thoughts/mem_{index}_{name}/`:
- `session_meta.md` - Session metadata, kbites loaded, phase history
- `fully_clarified_prompt.md` - Clarified requirements
- `exploration_report.md` / `relevant_implementation_report.md` - Findings
- `architecture_document.md` / `architecture_discussion_result.md` - Design
- `review_report.md` - Code review findings

### Legacy Individual Thoughts
For decisions outside bot workflows, save to `$GMCC_FAM_PATH/thoughts/{timestamp}_{topic}.md`.
Thoughts are **immutable** once written. Never edit, only append new thoughts.
