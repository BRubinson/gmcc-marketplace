# DraftUp KBite - Quick Reference Card
## One-Page Developer Cheat Sheet

**Last Updated:** 2025-02-03 | **Confidence Levels:** 80%+ across all triggers

---

## Top 15 Trigger Words (Sorted by Confidence)

| # | Trigger | Resource | Why Use It | Confidence |
|---|---------|----------|-----------|-----------|
| 1 | **coordinate system** | COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md | X/Y/Z definitions, mating plane | 98% |
| 2 | **half-lap joint** | HALF_LAP_JOINT_GEOMETRY_chewed.md | Joinery geometry, CSG algorithm | 96% |
| 3 | **ECS architecture** | ECS_PATTERNS_realitykit.md | Entity/component/system design | 95% |
| 4 | **@Observable** | STATE_MANAGEMENT_observable.md | SwiftUI state management | 94% |
| 5 | **CSG operations** | CSG_OPERATIONS_PATTERNS_chewed.md | Boolean mesh operations | 93% |
| 6 | **constraint resolution** | TRANSFORM_MATH_PROOFS.md | Positioning sheets | 92% |
| 7 | **geometry actor** | GEOMETRY_PROCESSING_ACTOR_PATTERN.md | Async mesh generation | 91% |
| 8 | **data model** | THE_ULTIMATE_SUMMARY_chewed.md | SheetDefinition, types | 90% |
| 9 | **watertight mesh** | WATERTIGHT_MESH_VALIDATION.md | Euclid validation | 89% |
| 10 | **attachment point** | HALF_LAP_JOINT_GEOMETRY_chewed.md | Connection points | 88% |
| 11 | **transform composition** | TRANSFORM_MATH_PROOFS.md | Quaternion math | 87% |
| 12 | **dado joint** | DADO_JOINT_FEATURE_SUMMARY.md | Groove cuts | 86% |
| 13 | **unit test transform** | PHASE_1_TRANSFORM_MATH_chewed.md | Test patterns | 85% |
| 14 | **Entity hierarchy** | ECS_PATTERNS_realitykit.md | Assembly→Sheet structure | 84% |
| 15 | **CNC export** | RECOMMENDATIONS_CHECKLIST_chewed.md | Toolpath generation | 82% |

---

## 4-Step Problem-Solving Workflow

### Problem: "I need to add a new joint type"

```
STEP 1: How does half-lap work?
└─ Trigger: "half-lap joint" → HALF_LAP_JOINT_GEOMETRY_chewed.md
   Extract: geometry algorithm, CSG patterns, attachment points
   Time: 3 min

STEP 2: How does it fit into the data model?
└─ Trigger: "data model" → THE_ULTIMATE_SUMMARY_chewed.md
   Extract: SheetOperation enum, validation pattern
   Time: 2 min

STEP 3: How do I test this?
└─ Trigger: "unit test transform" → PHASE_1_TRANSFORM_MATH_chewed.md
   Extract: TDD patterns, test structure
   Time: 2 min

STEP 4: What's the development workflow?
└─ See: FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md
   Extract: step-by-step checklist
   Time: 3 min

TOTAL: 10 min to confident implementation
```

### Problem: "Sheets are overlapping/positioning bug"

```
STEP 1: Verify coordinate system
└─ Trigger: "coordinate system" → COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md
   Confirm: X=width, Y=thickness (Y=0 mating), Z=height
   Time: 1 min

STEP 2: Check transform math
└─ Trigger: "transform composition" → TRANSFORM_MATH_PROOFS.md
   Review: formula, quaternion order, local vs world space
   Time: 3 min

STEP 3: Debug constraint resolution
└─ Trigger: "constraint resolution" → TRANSFORM_MATH_PROOFS.md (same doc)
   Review: algorithm, step-by-step calculation
   Time: 2 min

STEP 4: Check for known gotchas
└─ See: TRANSFORM_DEBUG_SUMMARY.md (in same primary/documentation/)
   What: common mistakes, debugging technique
   Time: 2 min

TOTAL: 8 min to root cause identification
```

### Problem: "Async geometry processing is crashing"

```
STEP 1: Check actor pattern
└─ Trigger: "geometry actor" → GEOMETRY_PROCESSING_ACTOR_PATTERN.md
   Review: actor isolation, concurrent safety
   Time: 2 min

STEP 2: Check state management
└─ Trigger: "@Observable" → STATE_MANAGEMENT_observable.md
   Review: MainActor, update propagation
   Time: 2 min

STEP 3: Review async pitfalls
└─ See: ASYNC_RACE_CONDITION_LESSONS.md
   Learn: race conditions, cancellation patterns
   Time: 3 min

STEP 4: Check RealityKit integration
└─ Trigger: "ECS architecture" → ECS_PATTERNS_realitykit.md
   Verify: component registration, system init
   Time: 2 min

TOTAL: 9 min to fix identification
```

---

## Key Architectural Patterns (At a Glance)

### Pattern 1: Coordinate System (NEVER FORGET)
```
X-axis: width (left-right)      [0,0,0] = center
Y-axis: thickness (front-back)  Y=0 is mating centerline
Z-axis: height (up-down)        Vertical orientation

Reference: COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md
```

### Pattern 2: Half-Lap Joinery (Reference Implementation)
```
1. Create base sheet mesh: Euclid.Mesh.cube(dimensions)
2. Create cutout mesh: Euclid.Mesh.cube(notch_size)
3. Subtract: base.subtracting(cutout_at_correct_position)
4. Validate: result.isWatertight == true

Reference: HALF_LAP_JOINT_GEOMETRY_chewed.md
```

### Pattern 3: State Management (@Observable)
```swift
@MainActor
@Observable
final class CurrentAssembly {
    static let shared = CurrentAssembly()
    var assembly: AssemblyData?
    // Use @Environment in SwiftUI to access
}

Reference: STATE_MANAGEMENT_observable.md
```

### Pattern 4: ECS Component Registration
```swift
@main struct DraftUpApp: App {
    init() {
        SheetComponent.registerComponent()
        AttachmentPointsComponent.registerComponent()
        ConstraintResolutionSystem.registerSystem()
    }
}

Reference: ECS_PATTERNS_realitykit.md
```

### Pattern 5: Constraint Resolution (Math)
```
Given:
- Sheet A at position P_A, rotation R_A
- Attachment point A_local, B_local
- Desired orientation Q

Calculate:
- Sheet B's transform such that points align

Formula: See TRANSFORM_MATH_PROOFS.md (with proofs)
```

---

## What to AVOID (Anti-Patterns)

| Anti-Pattern | Why It Failed | Do This Instead |
|--------------|---------------|-----------------|
| Monolithic ViewModel | Can't test logic, tight coupling | Use @Observable + separate services |
| ObservableObject | Legacy Swift, poor isolation | Use @Observable (Swift 6) |
| Entity subclassing | Anti-pattern in ECS | Use plain Entity + Components |
| Trial-and-error rotations | Debugging nightmare, unreliable | Write unit tests first (TDD) |
| Hardcoded demo data | Can't serialize, not user-facing | Data-driven AssemblyDefinition |
| Per-frame updates for static | Wastes CPU | Use event-driven (ComponentEvents.DidAdd) |

**Reference:** CRITICAL_FAILURES_chewed.md, CODE_GUIDANCE_BRO_REVIEW_chewed.md

---

## Resource Priority by Phase

### Phase 1: Foundation (Data Model)
1. COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md ⭐⭐⭐
2. THE_ULTIMATE_SUMMARY_chewed.md ⭐⭐⭐
3. ARCHITECTURE_DISCOVERY_structure.md ⭐⭐
4. RECOMMENDATIONS_CHECKLIST_chewed.md ⭐⭐

### Phase 2: Geometry Generation
1. HALF_LAP_JOINT_GEOMETRY_chewed.md ⭐⭐⭐
2. GEOMETRY_PROCESSING_ACTOR_PATTERN.md ⭐⭐⭐
3. CSG_OPERATIONS_PATTERNS_chewed.md ⭐⭐
4. WATERTIGHT_MESH_VALIDATION.md ⭐⭐

### Phase 3: ECS Integration
1. ECS_PATTERNS_realitykit.md ⭐⭐⭐
2. STATE_MANAGEMENT_observable.md ⭐⭐⭐
3. ENTITY_COMPONENT_SYSTEM_chewed.md ⭐⭐

### Phase 4: UI & Polish
1. reference_build_summary_chewed.md ⭐⭐
2. OBSERVABLE_STATE_PATTERNS_chewed.md ⭐⭐
3. FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md ⭐

---

## File Locations (Quick Access)

| Resource Type | Primary Path |
|--------------|--------------|
| Coordinate system | `primary/documentation/architecture/COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md` |
| Half-lap geometry | `primary/documentation/euclid_geometry/HALF_LAP_JOINT_GEOMETRY_chewed.md` |
| State management | `primary/documentation/swift_realitykit_visionos/STATE_MANAGEMENT_observable.md` |
| ECS patterns | `primary/documentation/swift_realitykit_visionos/ECS_PATTERNS_realitykit.md` |
| Transform math | `primary/documentation/architecture/TRANSFORM_MATH_PROOFS.md` |
| Feature workflows | `secondary/all_others/prompt_library/FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md` |
| Half-lap feature | `secondary/all_others/bfb_bwain_features/HALF_LAP_JOINT_FEATURE_SUMMARY.md` |

---

## Confidence Scoring Legend

| Level | Meaning | Example |
|-------|---------|---------|
| 95%+ | Proven in multiple features, core pattern | coordinate system, half-lap geometry |
| 90-94% | Well-established, minor edge cases | CSG operations, ECS patterns |
| 85-89% | Practical, some context-dependence | geometry actor, feature workflow |
| 80-84% | Emerging, experimental patterns | CNC export, new joint types |
| <80% | Avoid relying on without verification | - |

---

## When to Use Secondary Resources

**Use secondary resources when:**
- ✅ Learning how a specific feature was implemented
- ✅ Debugging an issue related to a completed feature
- ✅ Finding proven prompt templates for new features
- ✅ Looking for thought logs explaining design decisions

**Examples:**
- "How was half-lap implemented?" → `HALF_LAP_JOINT_FEATURE_SUMMARY.md`
- "What prompts work for new features?" → `FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md`
- "What did they learn building dado?" → `DADO_JOINT_FEATURE_SUMMARY.md`

---

## Getting Started (First 5 Minutes)

1. **Read this page** (2 min) ← You are here
2. **Bookmark these resources:**
   - `COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md` (always needed)
   - `THE_ULTIMATE_SUMMARY_chewed.md` (context)
   - `KBITE_TRIGGER_MAP.md` (quick lookup)
3. **Skim these sections:**
   - `CRITICAL_FAILURES_chewed.md` → "What to AVOID"
   - `RECOMMENDATIONS_CHECKLIST_chewed.md` → "Do this first"
4. **Bookmark:** This quick reference card

**Then:** Use trigger words to find answers to specific questions

---

## Master Trigger Word Lookup

**Can't find what you need? Use these:**

```
"How do I..." → Look for "feature development", "implementation pattern"
"Why did X fail?" → Look for "critical failures", "anti-patterns"
"Where's the math?" → Look for "coordinate system", "transform math"
"What's the code?" → Look for specific feature summary in secondary/
"Which pattern?" → Look for "ECS patterns", "state management"
"Is this right?" → Look for "validation", "testing", "confidence score"
```

---

## Contact/Questions

**For questions about this kbite:**
- See: `KBITE_PURPOSE.md` (scope, target users)
- See: `IMPLEMENTATION_GUIDE.md` (setup details)

**For questions about DraftUp development:**
- Triggers in this card will get you to answers
- Most queries resolve in <3 minutes with proper trigger word

**If you find a trigger word that doesn't work:**
- Note it down
- Add to `KBITE_TRIGGER_MAP.md` for next update
- Confidence scores will improve over time with usage data

---

## Revision History

| Date | Changes | Version |
|------|---------|---------|
| 2025-02-03 | Initial creation, 15 triggers, 4 workflows | 1.0 |
| TBD | Monthly updates with new features | 1.1+ |

---

**⚡ Pro Tip:** Copy this URL to your clipboard for fast access during development.

**Remember:** If a query takes >3 minutes, the kbite needs refinement. Report it!
