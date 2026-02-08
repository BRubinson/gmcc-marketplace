# DraftUp KBite Implementation Guide
## Step-by-Step Setup for Optimal Knowledge Management

**Target:** Create production-ready kbite for forge-up development
**Effort:** ~3-4 hours for complete setup
**Outcome:** Developers can find answers in <2 min per question

---

## Phase 1: Directory Structure Creation

### Step 1.1: Create Base Directory
```bash
mkdir -p /gmcc-marketplace/kbites/draftup_project/{primary,secondary}
mkdir -p /gmcc-marketplace/kbites/draftup_project/primary/{documentation,example_project}
mkdir -p /gmcc-marketplace/kbites/draftup_project/primary/documentation/{draftup_v1_retrospective,architecture,swift_realitykit_visionos,euclid_geometry}
mkdir -p /gmcc-marketplace/kbites/draftup_project/secondary/all_others/{bfb_bwain_features,prompt_library,implementation_notes}
```

### Step 1.2: Create Core Metadata Files
Create these in `/draftup_project/`:
- `KBITE_PURPOSE.md`
- `KBITE_INDEX.md` (template provided below)
- `KBITE_TRIGGER_MAP.md` (auto-generated from index)
- `KBITE_RELATIONSHIPS.md`

---

## Phase 2: Resource Chewing (7 Primary Sources)

### Resource 1: V1 Retrospective - Main Summary
**Source:** `/Users/brycerubinson/Dev/DraftUp/TheUltimateDraftUpV1SummaryThereEverWillBe.md`
**Output:** `primary/documentation/draftup_v1_retrospective/THE_ULTIMATE_SUMMARY_chewed.md`

**Chewing Instructions:**
1. Read entire document (3000+ lines)
2. Extract sections: Executive Summary, What Worked, What Failed, Critical Failures
3. Create condensed document (800-1000 words) with:
   - Clear "lessons learned" points
   - Anti-patterns to avoid
   - Code examples (small snippets only)
   - Cross-reference pointers to other resources
4. Add confidence scores per topic
5. Include "gotchas" section

**Confidence Scoring Template:**
```markdown
### Executive Summary (96% confidence)
**What worked (proven in code):**
- Euclid CSG for half-lap joints: 96% confidence
- RealityKit mesh display: 95% confidence
- Constraint concept is sound: 93% confidence

**What failed catastrophically:**
- Monolithic ViewModel: 98% confidence (must avoid)
- Trial-and-error transform math: 97% confidence (must use TDD)
```

---

### Resource 2: V1 Retrospective - Critical Failures Deep-Dive
**Source:** Same file, sections "Critical Architectural Failures" + "Code Guidance Bro Review"
**Output:** `primary/documentation/draftup_v1_retrospective/CRITICAL_FAILURES_chewed.md`

**Extract:**
1. Each failure (1. Monolithic ViewModel, 2. No ECS, 3. Trial-and-error math, 4. Hardcoded logic)
2. Why it failed (cause analysis)
3. Correct approach (from "What Should Have Been Done Instead" section)
4. Code examples (recommended patterns)
5. Testing strategy (how to prevent recurrence)

**Format:**
```markdown
## Failure Pattern 1: Monolithic ViewModel Anti-Pattern (98% confidence)

### What Failed
[2-3 line description]

### Root Cause
[Why the approach was wrong]

### Correct Approach
[Code example of recommended pattern]

### Prevention
[Testing/code review checklist]

### Related Triggers
- "state management" → See STATE_MANAGEMENT_observable.md
- "@Observable" → See OBSERVABLE_STATE_PATTERNS_chewed.md
```

---

### Resource 3: Architecture Discovery (Project Structure)
**Source:** `/Users/brycerubinson/Dev/DraftUp/ARCHITECTURE_DISCOVERY.md`
**Output:** `primary/documentation/architecture/ARCHITECTURE_DISCOVERY_structure.md`

**Extract:**
1. Section: "Project Structure Overview"
2. Section: "File Placement Recommendations"
3. Section: "Existing Patterns to Follow"
4. Section: "5-10 Essential Files with References"
5. Coordinate system convention (critical!)

**Format:**
```markdown
## File Organization Pattern (85% confidence)

### Recommended Structure
[Verbatim from ARCHITECTURE_DISCOVERY.md with inline comments]

### Key Convention: Coordinate System
X-axis: width (left-right)
Y-axis: thickness (front-back, MATING CENTERLINE = Y=0)
Z-axis: height (up-down, vertical)

Source of Truth: /Tests/TransformMath/CoordinateSystem.md

### Cross-Reference Priority
1. COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md (coordinate info)
2. PHASE_1_TRANSFORM_MATH_chewed.md (implementation reference)
```

---

### Resource 4: Coordinate System (SOURCE OF TRUTH)
**Source:** `/Users/brycerubinson/Dev/DraftUp/Tests/TransformMath/CoordinateSystem.md`
**Output:** `primary/documentation/architecture/COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md`

**Extract:**
1. Verbatim: entire coordinate system definition
2. Verbatim: mathematical proofs
3. Add: practical implications section
4. Add: common mistakes section

**Format:**
```markdown
# Coordinate System: SOURCE OF TRUTH (98% confidence)

## Definition
[Verbatim from source]

## Mathematical Proofs
[Verbatim from source]

## Practical Implications
### Half-Lap Joint Positioning
When sheet A (mating edge) meets sheet B (receiving edge):
- Sheet A's right edge attaches to Sheet B's left edge
- Both edges must align at Y=0 (mating centerline)
- Requires transform composition: A_transform * attachment_offset

### Common Mistakes
1. Confusing local vs world space coordinates
2. Forgetting Y=0 is mating centerline
3. Applying rotations in wrong order

## Testing
[Point to transform math tests]
```

---

### Resource 5: Reference Build - Observable & ECS Patterns
**Source:** `/Users/brycerubinson/Dev/DraftUp/bfb_references/reference_build/` (multiple files)
**Output:**
- `primary/documentation/swift_realitykit_visionos/reference_build_summary_chewed.md`
- `primary/documentation/swift_realitykit_visionos/OBSERVABLE_STATE_PATTERNS_chewed.md`
- `primary/documentation/swift_realitykit_visionos/ENTITY_COMPONENT_SYSTEM_chewed.md`

**Chewing Instructions:**
1. Search reference_build/ for: `@Observable`, `Entity`, `Component`
2. Extract code examples (Swift 6 syntax)
3. Create practical guide showing:
   - How to create @Observable service
   - How to use @Environment in SwiftUI
   - How to register RealityKit components
   - How to create systems
4. Connect to DraftUp patterns

**Output Format Example:**
```markdown
# @Observable State Management Pattern (93% confidence)

## Swift 6 Syntax
[Code example from reference_build or working Phase 1 code]

## DraftUp Application
```swift
@MainActor
@Observable
final class CurrentAssembly {
    static let shared = CurrentAssembly()
    var assembly: AssemblyData?
    var selectedSheetIDs: Set<UUID> = []
    // ...
}
```

## Why This Works
[Explanation of actor isolation, MainActor, update propagation]

## Integration with SwiftUI
[Code showing @Environment usage]

## Common Mistakes
1. Forgetting @MainActor decorator
2. Using @ObservableObject (legacy)
3. Modifying state outside Main thread
```

---

### Resource 6: Euclid Documentation
**Source:** `/Users/brycerubinson/Dev/DraftUp/bfb_references/euclid-docs/`
**Output:**
- `primary/documentation/euclid_geometry/EUCLID_API_REFERENCE_chewed.md` (90% conf)
- `primary/documentation/euclid_geometry/CSG_OPERATIONS_PATTERNS_chewed.md` (91% conf)
- `primary/documentation/euclid_geometry/HALF_LAP_JOINT_GEOMETRY_chewed.md` (96% conf)

**Chewing Strategy:**
1. For EUCLID_API: Extract shape generation (cube, extrude, etc.) and CSG operations
2. For CSG_OPERATIONS: Focus on subtract, union, intersection patterns + watertight validation
3. For HALF_LAP: Create tutorial showing:
   - Half-lap geometry algorithm
   - CSG implementation
   - Attachment points
   - Test cases

**Half-Lap Tutorial Template:**
```markdown
# Half-Lap Joint Geometry (96% confidence)

## Concept
A half-lap joint is where two sheets interlock:
- Sheet A has a notch on edge E1
- Sheet B has a matching notch on edge E2
- When assembled, they mate at the 0-height plane

## Algorithm
```
1. Create base mesh for Sheet A (cube of correct dimensions)
2. Create cutout mesh (smaller cube representing the notch)
3. Position cutout at the correct location
4. Subtract: base_mesh.subtracting(cutout_mesh)
5. Validate: result.isWatertight == true
```

## Euclid Implementation Example
[Code from working Phase 2 geometry generator]

## Attachment Points
Half-lap creates new attachment points:
- "lap_notch_edge": where the notch meets the mating face
- "lap_mating_surface": the flat surface created by the cut

## Coordinate System Application
Reference: COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md
- X-axis: sheet width
- Y-axis: thickness (Y=0 is mating plane)
- Z-axis: height
- Notch extends from Y=-thickness/2 to Y=0
```

---

### Resource 7: Transform Math & Constraint Resolution
**Source:** `/Users/brycerubinson/Dev/DraftUp/TRANSFORM_DEBUG_SUMMARY.md` + Phase 1 tests
**Output:** `primary/documentation/architecture/TRANSFORM_MATH_PROOFS.md`

**Extract:**
1. Transform composition algorithm (with proofs)
2. Constraint resolution formula
3. Quaternion multiplication order
4. Test cases showing correctness
5. Common rotation mistakes

**Format:**
```markdown
# Transform Math for Constraint Resolution (94% confidence)

## Formula: Constraint Resolution

Given:
- Sheet A at transform T_A (position and rotation)
- Attachment point on Sheet A at local position P_A_local
- Attachment point on Sheet B at local position P_B_local
- Desired orientation between sheets (quaternion Q_orient)

Calculate:
- Sheet B's transform T_B such that attachment points align

### Mathematical Derivation
[Step-by-step formula]
```
T_B = transform_such_that(
    T_A * P_A_local == T_B_desired * P_B_local
)
```

### Implementation Pseudocode
```swift
func resolveConstraint(
    sourceWorldTransform: simd_float4x4,
    sourceLocalPoint: SIMD3<Float>,
    targetLocalPoint: SIMD3<Float>,
    orientation: simd_quatf
) -> simd_float4x4 {
    // Step 1: Transform source attachment to world space
    let sourceWorldPoint = sourceWorldTransform * SIMD4(sourceLocalPoint, 1)

    // Step 2: Calculate target rotation
    let sourceRotation = simd_quatf(sourceWorldTransform)
    let targetRotation = sourceRotation * orientation

    // Step 3: Calculate target position
    let targetRotMatrix = simd_float4x4(targetRotation)
    let rotatedTargetLocal = targetRotMatrix * SIMD4(targetLocalPoint, 1)
    let targetOrigin = SIMD3(sourceWorldPoint) - SIMD3(rotatedTargetLocal)

    // Step 4: Return combined transform
    return simd_float4x4(translation: targetOrigin) * targetRotMatrix
}
```

### Test Cases Proving Correctness
[Reference to Phase 1 test files with line numbers]

### Why Trial-and-Error Fails
[Explanation of why V1 debugging was painful]
```

---

## Phase 3: Secondary Resources (Feature Summaries)

### Resource Aggregation from BFB Bwains
**Source:** `/Users/brycerubinson/Dev/DraftUp/bfb_bwain/*/`
**Output:** `secondary/all_others/bfb_bwain_features/`

**For each bwain feature, create summary:**

#### Example: HALF_LAP_JOINT_FEATURE_SUMMARY.md
```markdown
# Half-Lap Joint Feature Development (89% confidence)

## Summary
Completed feature implementing half-lap joinery with CSG operations.
Status: COMPLETED | Phase: 2 | Relevance: High

## What Was Built
- SheetOperation enum case for half-lap
- Geometry generation algorithm
- Attachment point calculation
- Test coverage (12+ tests passing)

## Key Implementation Details
[Extract from bwain thoughts, 5-7 key decisions]

## Lessons Learned
[Problems encountered, how resolved]

## Where to Find Working Code
- Primary implementation: `/DraftUp/Services/Geometry/SheetGeometryGenerator.swift`
- Tests: `/Tests/Geometry/SheetGeometryGeneratorTests.swift`
- Architecture: See PHASE_2_GEOMETRY_GENERATION_chewed.md

## Trigger Words
- "half-lap joint"
- "CSG operations"
- "joinery geometry"
- "attachment points"

## Related Features
- dado_joint (similar geometry approach)
- rabbet_joint (simpler variant)
- color_cut_surfaces (visualization enhancement)
```

**Create similar summaries for:**
- DADO_JOINT_FEATURE_SUMMARY.md (87% conf)
- RABBET_JOINT_FEATURE_SUMMARY.md (86% conf)
- COLOR_CUT_SURFACES_FEATURE_SUMMARY.md (82% conf)
- APPVIEW_UI_LAYOUT_FEATURE_SUMMARY.md (75% conf)

---

### Prompt Library Aggregation
**Source:** `/Users/brycerubinson/Dev/DraftUp/bfb_bwain/*/primary_prompts/`
**Output:** `secondary/all_others/prompt_library/`

#### Example: FEATURE_DEVELOPMENT_WORKFLOW_PROMPTS.md
```markdown
# Feature Development Workflow Prompts (85% confidence)

## Overview
Meta-collection of proven prompts used to develop features.
Use these as templates when starting new features.

## Pattern: New Joint Type Implementation

### Prompt Template
```
I'm implementing a [JOINT_TYPE] joint for DraftUp.

Requirements:
1. Geometry: [DESCRIBE SHAPE]
2. Attachment points: [DESCRIBE WHERE SHEETS MEET]
3. Validation: [WHAT MAKES IT VALID/INVALID]

Reference implementations:
- Half-lap: [LINK]
- Dado: [LINK]

Please help me:
1. Design the SheetOperation enum case
2. Implement geometry generation
3. Create attachment points
4. Write tests
```

### Proven Workflow
1. Enum design (reference half-lap pattern)
2. Geometry algorithm (whiteboard math first)
3. Implementation (TDD: tests first)
4. Integration (add to SheetGeometryGenerator)
5. Validation (unit + integration tests)

## Trigger Words
- "new feature development"
- "joint type implementation"
- "feature workflow"

## See Also
- FEATURE_IMPLEMENTATION in primary/documentation/example_project
```

---

## Phase 4: Create Index Files

### KBITE_INDEX.md Template
```markdown
# KBite Index: draftup_project

**Purpose:** See [KBITE_PURPOSE.md](./KBITE_PURPOSE.md)
**Last Updated:** 2025-02-03
**Total Resources:** 18

## Resource Index

| Resource | Axis | Path | Keywords | Relevance | Confidence | Unique Keywords |
|----------|------|------|----------|-----------|------------|-----------------|
| THE_ULTIMATE_SUMMARY | primary/documentation/draftup_v1 | primary/documentation/draftup_v1_retrospective/THE_ULTIMATE_SUMMARY_chewed.md | V1 patterns, lessons learned, data model, architecture | 98 | 96 | anti-patterns, ObservableObject |
| [Continue for all 18 resources...] | | | | | | |

## Keyword Cross-Reference

| Keyword | Resources | Best Resource |
|---------|-----------|---------------|
| coordinate system | COORDINATE_SYSTEM_SOURCE_OF_TRUTH, TRANSFORM_MATH_PROOFS, ARCHITECTURE_DISCOVERY | COORDINATE_SYSTEM_SOURCE_OF_TRUTH (98) |
| [Continue for all 20 keywords...] | | |

## Quick Reference Mappings

| Task | Best Resource | Alternative |
|------|---------------|-------------|
| Add new joint type | HALF_LAP_JOINT_GEOMETRY + FEATURE_DEVELOPMENT_WORKFLOW | DADO_JOINT_FEATURE_SUMMARY |
| Debug positioning bug | TRANSFORM_MATH_PROOFS + COORDINATE_SYSTEM | TRANSFORM_DEBUG_SUMMARY |
| Setup state management | STATE_MANAGEMENT_observable + OBSERVABLE_STATE_PATTERNS | reference_build_summary |
| Implement geometry actor | GEOMETRY_PROCESSING_ACTOR_PATTERN | PHASE_2_GEOMETRY_GENERATION |
```

### KBITE_TRIGGER_MAP.md Template
```markdown
# KBite Trigger Map: draftup_project

Quick lookup from trigger word to relevant resources.

| Trigger | Best Resource | Path | Relevance |
|---------|---------------|------|-----------|
| coordinate system | COORDINATE_SYSTEM_SOURCE_OF_TRUTH | primary/documentation/architecture/COORDINATE_SYSTEM_SOURCE_OF_TRUTH.md | 98 |
| half-lap joint | HALF_LAP_JOINT_GEOMETRY | primary/documentation/euclid_geometry/HALF_LAP_JOINT_GEOMETRY_chewed.md | 96 |
| ECS architecture | ECS_PATTERNS_realitykit | primary/documentation/swift_realitykit_visionos/ENTITY_COMPONENT_SYSTEM_chewed.md | 95 |
| [Continue for all 15 high-confidence triggers...] | | | |
```

---

## Phase 5: Validation & Testing

### Checklist Before Go-Live

- [ ] All 7 primary resources chewed and placed
- [ ] All 5 secondary feature summaries created
- [ ] KBITE_INDEX.md has all 18 resources
- [ ] KBITE_TRIGGER_MAP.md has top 15 triggers
- [ ] KBITE_RELATIONSHIPS.md links to claude_customization
- [ ] Test Scenario 1: Find half-lap documentation in <1 min
- [ ] Test Scenario 2: Get transform math help in <2 min
- [ ] Test Scenario 3: Find feature workflow in <1 min
- [ ] Directory structure matches recommendation (Part 1)
- [ ] All files use consistent formatting (triple-backticks, markdown)
- [ ] Confidence scores are conservative (avoid 99%+)
- [ ] Cross-references form complete network (no isolated docs)

### Test Queries

**Query 1:** "I need to add a mortise joint"
Expected Response Time: <2 min
Expected Resources: HALF_LAP_JOINT, FEATURE_DEVELOPMENT_WORKFLOW, SheetOperation

**Query 2:** "Transform math is broken, sheets overlapping"
Expected Response Time: <3 min
Expected Resources: COORDINATE_SYSTEM, TRANSFORM_MATH_PROOFS, TRANSFORM_DEBUG

**Query 3:** "How do I make async mesh generation?"
Expected Response Time: <2 min
Expected Resources: GEOMETRY_PROCESSING_ACTOR_PATTERN, STATE_MANAGEMENT_OBSERVABLE

---

## Timeline Estimate

| Phase | Task | Hours | Owner |
|-------|------|-------|-------|
| 1 | Create directory structure | 0.5 | code_architect |
| 2.1-2.7 | Chew 7 primary resources | 3.5 | code_architect |
| 3 | Aggregate secondary resources | 1 | code_architect |
| 4 | Create index files | 1 | code_architect |
| 5 | Validation & testing | 0.5 | code_architect |
| **Total** | | **6.5 hours** | |

---

## Success Criteria

**After setup, developers should:**

1. ✅ Find coordinate system in <1 min (trigger: "coordinate system")
2. ✅ Get half-lap geometry tutorial in <2 min
3. ✅ Understand @Observable pattern in <3 min
4. ✅ Know what V1 mistakes to avoid in <5 min
5. ✅ Reference working code examples in <2 min

**If any query takes >3 min, the index needs refinement.**

---

## Maintenance

- Monthly: Review new bwain features, add to secondary/all_others/
- Quarterly: Adjust confidence scores based on real usage
- Annually: Major review, archive old resources, refresh primary docs

---

This guide provides the exact workflow to build a production kbite that accelerates forge-up development.
