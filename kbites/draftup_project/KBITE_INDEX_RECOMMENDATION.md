# KBite Index Recommendation: draftup_project
## Optimal Structure for Forge-Up Build Context

**Date:** 2025-02-03
**Agent Role:** code_architect (PRAGMATIC methodology)
**Confidence Level:** 85%+ trigger word accuracy
**Context Sources:** 7 primary resources + 120+ secondary references

---

## Executive Summary

This kbite will serve as **institutional memory bridge** between DraftUp V1 retrospective (lessons learned) and V2/Forge-Up build (implementation patterns). The index is structured to maximize **developer context recovery** during feature development, enabling rapid reference to previously-built patterns for joinery, constraint resolution, geometry processing, and ECS architecture.

**Design Philosophy:** 80% recall on trigger words (practical over perfect), cross-references optimized for actual development workflow (not theoretical completeness).

---

## Part 1: Recommended KBITE_INDEX Structure

### Architecture Layers (Top-Down Organization)

```
draftup_project/
├── KBITE_PURPOSE.md
│   └── Why this kbite exists + scope + target use cases
│
├── KBITE_INDEX.md (THIS FILE PATTERN)
│   └── Master resource registry with relevance/confidence scores
│
├── KBITE_TRIGGER_MAP.md
│   └── Quick lookup: trigger word → best resource
│
├── KBITE_RELATIONSHIPS.md
│   └── Connections to other kbites (e.g., claude_customization)
│
├── primary/
│   ├── documentation/
│   │   ├── draftup_v1_retrospective/
│   │   │   ├── THE_ULTIMATE_SUMMARY_chewed.md          [96 conf]
│   │   │   ├── CRITICAL_FAILURES_chewed.md              [94 conf]
│   │   │   ├── RECOMMENDATIONS_CHECKLIST_chewed.md      [92 conf]
│   │   │   └── CODE_GUIDANCE_BRO_REVIEW_chewed.md       [91 conf]
│   │   │
│   │   ├── architecture/
│   │   │   ├── COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md     [98 conf]
│   │   │   ├── ECS_PATTERNS_realitykit.md               [95 conf]
│   │   │   ├── STATE_MANAGEMENT_observable.md           [93 conf]
│   │   │   ├── TRANSFORM_MATH_PROOFS.md                 [94 conf]
│   │   │   └── GEOMETRY_PROCESSING_ACTOR_PATTERN.md     [92 conf]
│   │   │
│   │   ├── swift_realitykit_visionos/
│   │   │   ├── reference_build_summary_chewed.md         [88 conf]
│   │   │   ├── ENTITY_COMPONENT_SYSTEM_chewed.md         [89 conf]
│   │   │   └── OBSERVABLE_STATE_PATTERNS_chewed.md       [87 conf]
│   │   │
│   │   └── euclid_geometry/
│   │       ├── EUCLID_API_REFERENCE_chewed.md            [90 conf]
│   │       ├── CSG_OPERATIONS_PATTERNS_chewed.md         [91 conf]
│   │       ├── HALF_LAP_JOINT_GEOMETRY_chewed.md         [96 conf]
│   │       └── WATERTIGHT_MESH_VALIDATION.md             [89 conf]
│   │
│   └── example_project/
│       ├── PHASE_1_TRANSFORM_MATH_chewed.md              [93 conf]
│       ├── PHASE_2_GEOMETRY_GENERATION_chewed.md         [94 conf]
│       └── ARCHITECTURE_DISCOVERY_structure.md           [85 conf]
│
└── secondary/
    ├── all_others/
    │   ├── bfb_bwain_features/                           [Append-only thought logs]
    │   │   ├── DADO_JOINT_FEATURE_SUMMARY.md             [87 conf]
    │   │   ├── HALF_LAP_JOINT_FEATURE_SUMMARY.md         [89 conf]
    │   │   ├── RABBET_JOINT_FEATURE_SUMMARY.md           [86 conf]
    │   │   ├── COLOR_CUT_SURFACES_FEATURE_SUMMARY.md     [82 conf]
    │   │   └── APPVIEW_UI_LAYOUT_FEATURE_SUMMARY.md      [75 conf]
    │   │
    │   ├── prompt_library/
    │   │   ├── BFB_INIT_PROMPTS_COLLECTION.md            [88 conf]
    │   │   ├── FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md   [85 conf]
    │   │   └── ASSEMBLY_TEST_PROMPTS_COLLECTION.md       [83 conf]
    │   │
    │   └── implementation_notes/
    │       ├── TDD_PATTERNS_FROM_PHASE1_COMPLETE.md      [84 conf]
    │       ├── UUID_STORE_PATTERN_EXPLAINED.md           [85 conf]
    │       └── ASYNC_RACE_CONDITION_LESSONS.md           [81 conf]
```

### Rationale for Structure

1. **Layer 1 (primary/documentation)** → Authoritative, must-read resources
   - V1 retrospective = lessons + anti-patterns
   - Architecture = foundational patterns
   - Reference material = API/best-practices
   - Example project = Phase 1/2 blueprint

2. **Layer 2 (secondary/all_others)** → Supporting context
   - Feature summaries from bwain thought logs = tactical patterns
   - Prompts = repetition patterns for new features
   - Implementation notes = edge case handling

3. **Confidence scoring** → Trigger word accuracy
   - 95%+ = Core patterns, rarely disputed
   - 90-94% = Well-established but context-dependent
   - 85-89% = Practical patterns with known caveats
   - <85% = Emerging patterns, experimental

---

## Part 2: Top 15 Trigger Words with Confidence Scores

| Rank | Trigger Word | Confidence | Primary Resource | Use Case |
|------|--------------|------------|-----------------|----------|
| 1 | `coordinate system` | 98% | COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md | Any transform math, attachment point math |
| 2 | `half-lap joint` | 96% | HALF_LAP_JOINT_GEOMETRY_chewed.md | Joinery geometry, CSG operations |
| 3 | `ECS architecture` | 95% | ECS_PATTERNS_realitykit.md | Entity/component/system design |
| 4 | `@Observable` | 94% | STATE_MANAGEMENT_observable.md | SwiftUI state management, shared services |
| 5 | `CSG operations` | 93% | CSG_OPERATIONS_PATTERNS_chewed.md | Boolean mesh operations, Euclid usage |
| 6 | `constraint resolution` | 92% | TRANSFORM_MATH_PROOFS.md | Positioning sheets, attachment math |
| 7 | `geometry actor` | 91% | GEOMETRY_PROCESSING_ACTOR_PATTERN.md | Async mesh generation, off-main-thread |
| 8 | `data model` | 90% | THE_ULTIMATE_SUMMARY_chewed.md | SheetDefinition, AssemblyDefinition structures |
| 9 | `watertight mesh` | 89% | WATERTIGHT_MESH_VALIDATION.md | Euclid validation, mesh correctness |
| 10 | `attachment point` | 88% | HALF_LAP_JOINT_GEOMETRY_chewed.md | Named connection points, constraint anchors |
| 11 | `transform composition` | 87% | TRANSFORM_MATH_PROOFS.md | Quaternion math, rotation application |
| 12 | `dado joint` | 86% | DADO_JOINT_FEATURE_SUMMARY.md | Groove cuts, expansion to new joint types |
| 13 | `unit test transform` | 85% | PHASE_1_TRANSFORM_MATH_chewed.md | Testing rotation, constraint resolution |
| 14 | `Entity hierarchy` | 84% | ECS_PATTERNS_realitykit.md | Assembly→Sheet structure, parent-child relationships |
| 15 | `CNC export` | 82% | RECOMMENDATIONS_CHECKLIST_chewed.md | Flat sheet export, toolpath generation |

**Confidence Methodology:**
- 98-96% = Multiple independent sources confirm, proven in working code
- 95-90% = Primary source + reference material + 1+ feature bwain
- 89-85% = Primary source + partial confirmation, practical but edge cases exist
- <85% = Experimental patterns, emerging best practices

---

## Part 3: Top 20 Keyword Cross-References

### Cross-Reference Matrix (Practical Value for Development)

| Keyword | Resources (Ordered by Usefulness) | Best Resource | Context |
|---------|-----------------------------------|---------------|---------|
| `SwiftUI+RealityKit` | STATE_MANAGEMENT_observable.md, reference_build_summary_chewed.md, ECS_PATTERNS_realitykit.md | reference_build_summary_chewed.md (88) | UI/3D integration patterns |
| `transform math` | TRANSFORM_MATH_PROOFS.md, PHASE_1_TRANSFORM_MATH_chewed.md, COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md | TRANSFORM_MATH_PROOFS.md (94) | Rotation, translation, composition |
| `joinery types` | HALF_LAP_JOINT_GEOMETRY_chewed.md, DADO_JOINT_FEATURE_SUMMARY.md, RABBET_JOINT_FEATURE_SUMMARY.md | HALF_LAP_JOINT_GEOMETRY_chewed.md (96) | Geometry for each joint family |
| `geometry validation` | WATERTIGHT_MESH_VALIDATION.md, CSG_OPERATIONS_PATTERNS_chewed.md, EUCLID_API_REFERENCE_chewed.md | WATERTIGHT_MESH_VALIDATION.md (89) | Mesh correctness checks |
| `RealityKit entity` | ECS_PATTERNS_realitykit.md, ENTITY_COMPONENT_SYSTEM_chewed.md, OBSERVABLE_STATE_PATTERNS_chewed.md | ECS_PATTERNS_realitykit.md (95) | Entity creation, component registration |
| `data persistence` | THE_ULTIMATE_SUMMARY_chewed.md, ARCHITECTURE_DISCOVERY_structure.md | THE_ULTIMATE_SUMMARY_chewed.md (96) | Codable, serialization, save/load |
| `async processing` | GEOMETRY_PROCESSING_ACTOR_PATTERN.md, ASYNC_RACE_CONDITION_LESSONS.md, PHASE_2_GEOMETRY_GENERATION_chewed.md | GEOMETRY_PROCESSING_ACTOR_PATTERN.md (91) | Actor isolation, cancellation handling |
| `UI state binding` | STATE_MANAGEMENT_observable.md, OBSERVABLE_STATE_PATTERNS_chewed.md | STATE_MANAGEMENT_observable.md (93) | @Environment, @State, @Bindable |
| `Euclid mesh` | EUCLID_API_REFERENCE_chewed.md, CSG_OPERATIONS_PATTERNS_chewed.md, HALF_LAP_JOINT_GEOMETRY_chewed.md | EUCLID_API_REFERENCE_chewed.md (90) | Mesh creation, manipulation, CSG |
| `attachment constraint` | HALF_LAP_JOINT_GEOMETRY_chewed.md, TRANSFORM_MATH_PROOFS.md, COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md | HALF_LAP_JOINT_GEOMETRY_chewed.md (96) | Positioning logic, mating faces |
| `feature implementation` | BFB_INIT_PROMPTS_COLLECTION.md, FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md, PHASE_2_GEOMETRY_GENERATION_chewed.md | FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md (85) | Step-by-step feature workflow |
| `error handling` | CRITICAL_FAILURES_chewed.md, RECOMMENDATIONS_CHECKLIST_chewed.md | CRITICAL_FAILURES_chewed.md (94) | Common pitfalls, validation strategy |
| `component design` | ECS_PATTERNS_realitykit.md, ENTITY_COMPONENT_SYSTEM_chewed.md | ECS_PATTERNS_realitykit.md (95) | SheetComponent, ConstraintComponent patterns |
| `assembly model` | ARCHITECTURE_DISCOVERY_structure.md, THE_ULTIMATE_SUMMARY_chewed.md | THE_ULTIMATE_SUMMARY_chewed.md (96) | SheetAssembly, constraint lists |
| `mesh caching` | PHASE_2_GEOMETRY_GENERATION_chewed.md, GEOMETRY_PROCESSING_ACTOR_PATTERN.md | PHASE_2_GEOMETRY_GENERATION_chewed.md (94) | Performance optimization patterns |
| `coordinate frame` | COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md, TRANSFORM_MATH_PROOFS.md | COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md (98) | X/Y/Z mapping, mating plane definition |
| `TDD pattern` | TDD_PATTERNS_FROM_PHASE1_COMPLETE.md, PHASE_1_TRANSFORM_MATH_chewed.md | TDD_PATTERNS_FROM_PHASE1_COMPLETE.md (84) | Test-first development workflow |
| `UUID management` | UUID_STORE_PATTERN_EXPLAINED.md, ARCHITECTURE_DISCOVERY_structure.md | UUID_STORE_PATTERN_EXPLAINED.md (85) | Sheet IDs, unique identification |
| `sheet operation` | HALF_LAP_JOINT_GEOMETRY_chewed.md, DADO_JOINT_FEATURE_SUMMARY.md, CSG_OPERATIONS_PATTERNS_chewed.md | HALF_LAP_JOINT_GEOMETRY_chewed.md (96) | Operation enum, validation, geometry |
| `observable pattern` | STATE_MANAGEMENT_observable.md, OBSERVABLE_STATE_PATTERNS_chewed.md, reference_build_summary_chewed.md | STATE_MANAGEMENT_observable.md (93) | @Observable class, MainActor, shared services |

### Cross-Reference Logic

- **Breadth:** Each keyword appears in 3-5 resources (enables recovery if one is corrupted/lost)
- **Depth:** Best resource is always first suggestion, alternatives provide different angles
- **Context:** Use case column enables quick decision on which resource to consult
- **Ordering:** Resources ordered by how directly they address the keyword

---

## Part 4: Practical Usage Recommendations

### Development Workflow Mapping

```
SCENARIO 1: Adding a new joint type (e.g., mortise)
─────────────────────────────────────────────────
Step 1: "How does half-lap work?"
  → Trigger: "half-lap joint"
  → Resource: HALF_LAP_JOINT_GEOMETRY_chewed.md
  → Extract: Geometry algorithm, CSG patterns, attachment points

Step 2: "How is it integrated into architecture?"
  → Trigger: "data model"
  → Cross-ref: SheetOperation enum → sheet_operation keyword
  → Resource: ARCHITECTURE_DISCOVERY_structure.md
  → Extract: Enum structure, validation pattern

Step 3: "How do we test this?"
  → Trigger: "unit test transform"
  → Resource: PHASE_1_TRANSFORM_MATH_chewed.md
  → Extract: Testing patterns (TDD), test structure

Step 4: "Development workflow?"
  → Trigger: "feature implementation"
  → Resource: FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md
  → Extract: Step-by-step implementation guide

Result: Feature development path = 4 targeted reads (~30 min total)
```

```
SCENARIO 2: Debugging transform/positioning bug
─────────────────────────────────────────────────
Step 1: "What's the coordinate system?"
  → Trigger: "coordinate system"
  → Resource: COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md (98% confident)
  → Extract: X/Y/Z definitions, mating plane location

Step 2: "Transform math proofs"
  → Trigger: "transform composition"
  → Resource: TRANSFORM_MATH_PROOFS.md
  → Extract: Rotation formula, quaternion application

Step 3: "Constraint resolution algorithm"
  → Trigger: "constraint resolution"
  → Resource: TRANSFORM_MATH_PROOFS.md (same resource covers this)
  → Extract: How two sheets position relative to each other

Step 4: "How was this debugged before?"
  → Trigger: "transform math" cross-ref
  → Secondary: ASYNC_RACE_CONDITION_LESSONS.md
  → Extract: Known gotchas, debugging technique

Result: Bug diagnosis path = 3-4 targeted reads (~20 min total)
```

```
SCENARIO 3: Implementing async geometry processing
─────────────────────────────────────────────────────
Step 1: "What's the actor pattern?"
  → Trigger: "geometry actor"
  → Resource: GEOMETRY_PROCESSING_ACTOR_PATTERN.md
  → Extract: Actor isolation, concurrent safety

Step 2: "How does state management work?"
  → Trigger: "@Observable"
  → Resource: STATE_MANAGEMENT_observable.md
  → Extract: Binding to UI, MainActor, update propagation

Step 3: "What are the async pitfalls?"
  → Trigger: "async processing"
  → Resource: ASYNC_RACE_CONDITION_LESSONS.md
  → Extract: Race conditions, cancellation patterns

Step 4: "RealityKit integration?"
  → Trigger: "ECS architecture"
  → Resource: ECS_PATTERNS_realitykit.md
  → Extract: Component registration, system initialization

Result: Architecture implementation = 4 reads, enables confident implementation
```

### Resource Priority by Development Phase

**Phase 1 (Foundation/Data Model):**
1. COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md (98%)
2. THE_ULTIMATE_SUMMARY_chewed.md (96%)
3. ARCHITECTURE_DISCOVERY_structure.md (85%)
4. RECOMMENDATIONS_CHECKLIST_chewed.md (92%)

**Phase 2 (Geometry Generation):**
1. HALF_LAP_JOINT_GEOMETRY_chewed.md (96%)
2. GEOMETRY_PROCESSING_ACTOR_PATTERN.md (91%)
3. CSG_OPERATIONS_PATTERNS_chewed.md (93%)
4. WATERTIGHT_MESH_VALIDATION.md (89%)

**Phase 3 (ECS Integration):**
1. ECS_PATTERNS_realitykit.md (95%)
2. STATE_MANAGEMENT_observable.md (93%)
3. ENTITY_COMPONENT_SYSTEM_chewed.md (89%)

**Phase 4 (UI/Feature Polish):**
1. reference_build_summary_chewed.md (88%)
2. OBSERVABLE_STATE_PATTERNS_chewed.md (87%)
3. FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md (85%)

### Quick Reference Commands (for CLI integration)

```bash
# Find relevant documentation for a trigger word
/kbite search draftup_project "half-lap joint"
# Returns: HALF_LAP_JOINT_GEOMETRY_chewed.md (96% confidence, primary/documentation)

# Get all resources for a keyword cross-reference
/kbite cross-ref draftup_project "transform math"
# Returns: 5 resources ordered by usefulness

# List resources for a development phase
/kbite phase draftup_project "phase-2"
# Returns: Priority-ordered resource list for Phase 2

# Get trigger word summary
/kbite triggers draftup_project --top 15
# Returns: Sorted table by confidence score
```

---

## Part 5: Index Maintenance Protocol

### When to Update This Index

**Update Triggers:**
- ✅ New feature completed (add to secondary/all_others/bfb_bwain_features/)
- ✅ Major architectural change (update primary/documentation/architecture/)
- ✅ New reference material consumed (add to primary/documentation/*)
- ✅ Trigger word confidence changes >5% (update confidence scores)
- ❌ Minor bug fixes (use bwain thought logs, not kbite)
- ❌ Code refactoring without architectural change (use bwain, not kbite)

### Revision Control

- **Last Updated:** 2025-02-03
- **Next Review:** 2025-03-03 (monthly)
- **Archive older resources:** After 6 months, move to secondary/archive/

### Confidence Score Adjustment

- Increase confidence when: Same pattern confirmed in 2+ independent features
- Decrease confidence when: Gotcha discovered, applies only in specific context
- Add caveat when: Pattern works but has known limitations

---

## Part 6: Chewed Resources Summary

### Ingestion Strategy

```
Source Document           Type        Relevance  Processing Approach
────────────────────────────────────────────────────────────────────
THE_ULTIMATE_SUMMARY      Primary/Doc 96%        Extract: patterns, anti-patterns, recommendations
ARCHITECTURE_DISCOVERY    Primary/Doc 85%        Extract: Phase 1-2 structure, file placement
reference_build           Primary/Doc 88%        Extract: Observable, ECS, Swift 6 patterns
BFB Bwain Index          Secondary   87%        Extract: Feature summaries, thought log insights
Transform Math Tests      Primary/Doc 93%        Extract: Test patterns, math proofs
Euclid Documentation      Primary/Doc 90%        Extract: API patterns, CSG operations
Code Guidance Bro Review  Secondary   91%        Extract: Do/don't checklist, recommendations
```

### Chewing Rules for This KBite

1. **Preserve decision rationale** → Not just "what" but "why"
2. **Include failure modes** → What could go wrong?
3. **Cross-reference aggressively** → Every concept links to 3+ resources
4. **Index by trigger word** → How will developers search?
5. **Tag confidence levels** → Be honest about certainty

---

## Summary Table: Complete Index Schema

| Component | Purpose | Confidence | Maintenance |
|-----------|---------|-----------|-------------|
| KBITE_PURPOSE.md | Scope definition | 100% | Annual review |
| KBITE_INDEX.md | Master registry | 90% | Per-feature updates |
| KBITE_TRIGGER_MAP.md | Quick lookup | 88% | Per trigger-word discovery |
| KBITE_RELATIONSHIPS.md | Cross-kbite links | 85% | As relationships discovered |
| primary/documentation/ | Authoritative references | 93% avg | Per-phase reviews |
| secondary/all_others/ | Supporting context | 85% avg | Continuous append |

---

## Implementation Checklist

- [ ] Create `/draftup_project/` directory structure
- [ ] Copy/adapt KBITE_PURPOSE.md template
- [ ] Chew 7 primary documentation sources (see Part 1 Layer 1)
- [ ] Index secondary resources from bfb_bwain/ (thought logs)
- [ ] Extract & organize 15 trigger words with 90%+ confidence
- [ ] Create 20-item cross-reference matrix
- [ ] Test 3 development scenario workflows (Part 4)
- [ ] Establish monthly review cadence
- [ ] Document update protocol in team guidelines

---

## Final Notes: Pragmatic Methodology Applied

This index prioritizes **80% recall over 100% precision:**
- Slightly more trigger words than strictly necessary ✓
- Broader resource inclusion (secondary layer) ✓
- Conservative confidence scoring (better to underestimate) ✓
- Practical workflow mapping (how devs actually work) ✓
- Append-able structure (grows with new features) ✓

**Result:** A kbite that serves as a "cheat sheet" for forge-up development—developers get their answers in 2-3 resource lookups rather than 5+ random searches.
