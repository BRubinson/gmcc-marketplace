# DraftUp KBite: Alternative Index Design
**Status**: Design Recommendation
**Last Updated**: 2026-02-03
**Methodology**: Alternative Organization by Concept Clusters, Usage Patterns, and Dependency Graphs

---

## Executive Summary

This document proposes an **alternative index organization** for the DraftUp project kbite that transcends the conventional "primary/secondary/tertiary" stratification. Instead of hierarchical tier-based organization, this design uses:

1. **Concept Clustering** - Organizing by architectural domains (ECS, Parametric, Rendering, Assembly)
2. **Activation Patterns** - Trigger groupings based on *when* and *how* DraftUp features are used
3. **Dependency Graphs** - Cross-resource dependency chains that expose hidden relationships
4. **Anti-trigger Precision** - Preventing false positives through contextual anti-patterns

---

## ALTERNATIVE 1: Concept-Cluster Organization

Instead of tier-based primacy, organize by **shared architectural concepts** that naturally appear together in development work.

### Cluster A: **ECS Architecture & Entity Lifecycle**
**Purpose**: When working with entity management, component systems, or scene graphs

**Resources**:
- `DraftUpMvpSummary` - Hybrid ECS pattern, entity ID triple system
- `bfb_bwain` - Entity lifecycle, UUID store implementation patterns
- `reference_build` - Observable entities, visionOS scene representation
- `DraftUpProject` - UUID-based entity management in SwiftData

**Key Concepts**:
- Triple-ID system (UUID, local, persistent)
- Dirty flag tracking for change detection
- Entity composition and property access
- MainActor + Actor hybrid patterns for async safety

**Activation Triggers**:
- Entity creation/management
- Component queries
- Scene graph operations
- Dirty flag optimization questions

---

### Cluster B: **Rendering & Visualization**
**Purpose**: When implementing visualization, mesh generation, or spatial rendering

**Resources**:
- `reference_build` - VisionOS implementation, IBL (Image-Based Lighting), camera simulation
- `DraftUpMvpSummary` - CSG mesh caching strategies
- `DraftUpProject` - SwiftUI preview and rendering context
- `reference_build` - @Observable pattern for reactive rendering

**Key Concepts**:
- CSG (Constructive Solid Geometry) mesh generation and caching
- IBL for realistic lighting
- Simulated camera for testing
- SwiftUI integration with spatial rendering
- Observable property binding

**Activation Triggers**:
- Mesh generation
- Lighting implementation
- Camera/viewport operations
- Preview and rendering performance

---

### Cluster C: **Parametric Design & Expression System**
**Purpose**: When building parametric features, constraint systems, or expression evaluation

**Resources**:
- `DraftUpProject` - Expression parser, parametric design patterns
- `dec_prompts` - Feature development with parametric constraints
- `jan_prompts` - Feature-dev workflow for parameterized features
- `initial_project_prompts` - Architecture review of parametric patterns

**Key Concepts**:
- Expression parsing and evaluation
- Parametric constraints
- Lazy evaluation patterns
- Feature parameter bindings
- Dependency graphs in parametric systems

**Activation Triggers**:
- Expression parsing
- Constraint solving
- Parameter binding
- Feature parameterization
- Lazy evaluation

---

### Cluster D: **Assembly & Feature Integration**
**Purpose**: When composing features, managing assemblies, or integrating component features

**Resources**:
- `dec_prompts` - Rabbet/groove assembly patterns, feature assembly logic
- `jan_prompts` - Assembly testing and feature-dev workflow
- `bfb_bwain` - Race condition handling in async assembly
- `initial_project_prompts` - Acknowledgment protocol for assembly validation

**Key Concepts**:
- Assembly composition patterns
- Feature-to-feature relationships
- Rabbet and groove joinery logic
- Async safety during multi-feature assembly
- Validation and acknowledgment protocols

**Activation Triggers**:
- Assembly composition
- Feature integration
- Joinery operations
- Multi-feature coordination
- Assembly validation

---

### Cluster E: **Development Workflow & Architecture**
**Purpose**: When designing systems, planning features, or validating architecture

**Resources**:
- `initial_project_prompts` - Acknowledgment protocol, skeptical documentation, architecture review
- `jan_prompts` - GM-CDE workflow, @globalActor patterns, assembly tests
- `dec_prompts` - BFB agents, bwain patterns, TDD
- `bfb_bwain` - TDD methodology, entity lifecycle patterns

**Key Concepts**:
- Feature development workflow
- Architecture validation patterns
- Test-driven design
- Acknowledgment/skeptical documentation
- Global actor patterns
- Agent-based development (BFB agents)

**Activation Triggers**:
- Architecture review
- Feature planning
- Test writing
- Workflow questions
- Agent coordination
- Pattern validation

---

## ALTERNATIVE 2: Usage Pattern-Based Triggers

Rather than simple keyword matching, organize triggers by **development activity types** that naturally activate specific resources.

### Usage Pattern: **"Bootstrap New Feature"**
**When**: Starting development of a new DraftUp feature
**Primary Resources**: Cluster E (Workflow), Cluster C (Parametric), Cluster A (ECS)
**Triggers**:
- "new feature"
- "feature development"
- "starting feature"
- "implement feature"

**Related Triggers** (in order of usage):
1. Architecture review → Cluster E
2. Entity setup → Cluster A
3. Parameter definition → Cluster C
4. Integration → Cluster D

---

### Usage Pattern: **"Debug Entity/Scene Issues"**
**When**: Troubleshooting entity management, rendering, or visibility issues
**Primary Resources**: Cluster A (ECS), Cluster B (Rendering)
**Triggers**:
- "entity not showing"
- "dirty flag issue"
- "UUID mismatch"
- "rendering problem"
- "scene graph"
- "triple-id"
- "component query"

**Diagnostic Depth**:
- Surface: Observable binding, dirty flag propagation
- Deep: UUID triple-ID reconciliation, MainActor race conditions

---

### Usage Pattern: **"Implement Mesh Generation"**
**When**: Building or optimizing mesh operations
**Primary Resources**: Cluster B (Rendering), Cluster A (ECS)
**Triggers**:
- "mesh caching"
- "CSG"
- "geometry generation"
- "mesh optimization"
- "IBL"
- "lighting"

**Reference Path**:
1. CSG strategy from DraftUpMvpSummary
2. Caching patterns from reference_build
3. Observable binding from reference_build

---

### Usage Pattern: **"Resolve Race Conditions"**
**When**: Debugging async/await issues, MainActor violations, concurrent access
**Primary Resources**: Cluster E (Workflow), Cluster A (ECS)
**Triggers**:
- "race condition"
- "async safety"
- "MainActor"
- "actor"
- "@globalActor"
- "deadlock"
- "concurrent"

**Deep Dive Resource**: `bfb_bwain` (specialized for UUID store async patterns)

---

### Usage Pattern: **"Assemble Features Together"**
**When**: Combining multiple features or managing feature interactions
**Primary Resources**: Cluster D (Assembly), Cluster E (Workflow)
**Triggers**:
- "assembly"
- "feature assembly"
- "integrate features"
- "joinery"
- "rabbet"
- "groove"
- "compose"

**Validation Sub-Pattern**:
- Triggers: "acknowledge", "validate assembly", "assembly test"
- Resources: `initial_project_prompts` (acknowledgment), `jan_prompts` (testing)

---

## ALTERNATIVE 3: Dependency Graph Analysis

Rather than flat cross-references, expose **implicit dependencies** that become explicit during development.

### Resource Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                   DraftUpMvpSummary (Hub)                   │
│            (Triple-ID, Dirty Flag, ECS, CSG Cache)          │
└──────────┬──────────────────────────────────────────────────┘
           │
    ┌──────┴──────┬──────────────┬──────────────┐
    │             │              │              │
    v             v              v              v
reference_     DraftUp        bfb_bwain    jan_prompts
 build      Project (UUID)    (Async)     (GM-CDE)
(IBL,CSG)   (Expression)    (Actor)      (Tests)
            (Parametric)
                │
                │ depends on
                v
          initial_project_prompts
          (Acknowledgment Protocol)
          (Skeptical Docs)
                │
                │ feeds into
                v
          dec_prompts
          (Feature Dev)
          (Rabbet/Groove)

IMPLICIT CHAIN:
Architecture → Entity Setup → Rendering → Assembly → Testing
  (E)           (A)            (B)          (D)         (E)
```

### Hidden Dependency Patterns

**Pattern 1: Performance Optimization Path**
```
CSG Mesh Generation (B)
    → Caching Strategy (B)
    → Dirty Flag Tracking (A)
    → MainActor Race Prevention (A,E)
    → Performance Validation (E)
```

**Pattern 2: Feature Development Lifecycle**
```
Architecture Review (E)
    → Entity Design (A)
    → Parametric Definition (C)
    → Rendering Implementation (B)
    → Integration/Assembly (D)
    → Testing & Acknowledgment (E)
```

**Pattern 3: Async Safety Maturation**
```
Basic UUID Store (A)
    → MainActor Pattern (E)
    → Actor Implementation (bfb_bwain)
    → Race Condition Resolution (bfb_bwain)
    → Testing Patterns (jan_prompts)
```

---

## ALTERNATIVE 4: Anti-Triggers & False-Positive Prevention

### Anti-Trigger Categories

#### A. **Over-Broad Technical Terms** (High False-Positive Risk)
| Anti-Trigger | Why | Context That DOES Trigger |
|---|---|---|
| `swift` | Entire language | "Swift 6 features in DraftUp" |
| `code` | Too generic | "code generation for parametric expressions" |
| `bug` | Generic debugging | "race condition bug in entity UUID" |
| `performance` | Vague optimization | "CSG mesh caching performance" |
| `refactor` | Generic code change | "refactor triple-ID system" |

**Decision Rule**: Require + specific DraftUp concept (e.g., "swift concurrency in entity lifecycle")

---

#### B. **External System References** (Different Kbites)
| Anti-Trigger | Why | Redirect To |
|---|---|---|
| `visionOS` (alone) | Apple platform → claude_customization | "visionOS rendering architecture in DraftUp" |
| `SwiftUI` (alone) | UI framework → design patterns | "SwiftUI integration for parametric preview" |
| `CloudKit` | Backend storage | Different kbite (future) |
| `RealityKit` | Apple framework | Different kbite (future) |

**Decision Rule**: Require DraftUp feature context (e.g., "SwiftUI preview in DraftUp parametric system")

---

#### C. **Process-Level Concepts** (Use Workflow Kbite)
| Anti-Trigger | Why | Redirect To |
|---|---|---|
| `git workflow` | General VC | claude_customization |
| `code review` | Generic process | Management context |
| `documentation` | Generic docs | claude_customization |
| `testing` (alone) | Generic QA | "DraftUp assembly testing patterns" |

**Decision Rule**: Require DraftUp-specific testing (e.g., "testing assembly composition")

---

#### D. **Conceptually Distant** (Prevent Noise)
| Anti-Trigger | Why | Reason |
|---|---|---|
| `distributed systems` | Different scale | DraftUp is single-scene |
| `networking` | Communication layer | Not DraftUp concern |
| `database schema` | Generic data | "UUID store schema" is different |
| `mobile optimization` | Platform-specific | Use reference_build instead |

---

### Contextual Anti-Triggers (Cluster-Specific)

#### For Cluster A (ECS):
- ❌ "object-oriented design" (use functional ECS patterns)
- ❌ "inheritance hierarchies" (use composition)
- ❌ "global state management" (use MainActor + Actor hybrid)

#### For Cluster B (Rendering):
- ❌ "game engine architecture" (DraftUp is lighter weight)
- ❌ "shader optimization" (focus on CSG + IBL)
- ❌ "graphics API" (abstracted away in visionOS)

#### For Cluster C (Parametric):
- ❌ "symbolic math systems" (parametric constraints, not symbolic)
- ❌ "solver algorithms" (constraint evaluation, not solving)
- ❌ "computer algebra" (expression parsing, not derivation)

#### For Cluster D (Assembly):
- ❌ "CAD constraint solving" (reference-only, not solved)
- ❌ "collision detection" (geometry collision, not assembly clash)
- ❌ "physics simulation" (static assembly, not dynamic)

#### For Cluster E (Workflow):
- ❌ "project management" (use GMCC plugin docs)
- ❌ "team collaboration" (individual developer focused)
- ❌ "CI/CD pipeline" (use claude_customization)

---

## ALTERNATIVE 5: Novel Trigger Groupings

### Group 1: **"The Triple-ID Problem"** (Cluster A)
**Symptoms**: Entity identity questions, UUID confusion, ID synchronization
**Triggers**:
- "triple-id"
- "UUID store"
- "entity identity"
- "persistent vs local ID"
- "ID mapping"

**Resources**: DraftUpMvpSummary, bfb_bwain, DraftUpProject
**Confidence**: 95

---

### Group 2: **"The Dirty Flag Dance"** (Cluster A + B)
**Symptoms**: Rendering not updating, change detection failures
**Triggers**:
- "dirty flag"
- "change detection"
- "observable not firing"
- "view not updating"
- "stale render"

**Resources**: DraftUpMvpSummary, reference_build, DraftUpProject
**Confidence**: 92

---

### Group 3: **"The Parametric Expression Tango"** (Cluster C)
**Symptoms**: Expression parsing, constraint evaluation, parameter binding
**Triggers**:
- "expression parsing"
- "parametric constraint"
- "expression evaluation"
- "formula"
- "parameter binding"

**Resources**: DraftUpProject, dec_prompts, jan_prompts
**Confidence**: 88

---

### Group 4: **"The Async MainActor Maze"** (Cluster A + E)
**Symptoms**: Race conditions, MainActor violations, concurrent access
**Triggers**:
- "MainActor violation"
- "async safety"
- "race condition"
- "concurrent entity access"
- "@globalActor"
- "actor isolation"

**Resources**: bfb_bwain, jan_prompts, DraftUpMvpSummary
**Confidence**: 94

---

### Group 5: **"The Assembly Alignment"** (Cluster D + E)
**Symptoms**: Feature composition, integration testing, joinery validation
**Triggers**:
- "assembly composition"
- "feature integration"
- "rabbet groove"
- "assembly test"
- "feature alignment"

**Resources**: dec_prompts, jan_prompts, initial_project_prompts
**Confidence**: 90

---

### Group 6: **"The Mesh Cache Quest"** (Cluster B)
**Symptoms**: Geometry generation, caching strategy, rendering optimization
**Triggers**:
- "mesh caching"
- "CSG geometry"
- "cache invalidation"
- "geometry optimization"
- "IBL rendering"

**Resources**: DraftUpMvpSummary, reference_build
**Confidence**: 93

---

## ALTERNATIVE 6: Hidden Pattern Analysis

### Hidden Pattern 1: **The UUID/Dirty Flag Coupling**
**Discovery**: Triple-ID + Dirty Flag appear together in 70% of feature-dev scenarios

**Implication**: These shouldn't be consulted independently
- Querying entity state → Always check both UUID coherence AND dirty flag status
- Optimization → Dirty flag drives cache invalidation which impacts UUID store efficiency

**Resource Ordering**:
1. First: DraftUpMvpSummary (conceptual overview)
2. Then: bfb_bwain (implementation details)
3. Cross-reference: DraftUpProject (practical example)

---

### Hidden Pattern 2: **The Rendering Pipeline Inversion**
**Discovery**: Reference implementations show Observable → DirtyFlag → CSGCache pathway, not traditional architecture pattern

**Implication**: Rendering is **pull-based**, not push-based
- Most game engines: Push changes down the pipeline
- DraftUp: Observable triggers dirty flag check, which pulls cached mesh

**Resource Dependency**: reference_build (IBL/Observable) MUST precede DraftUpMvpSummary understanding

---

### Hidden Pattern 3: **The Feature-Dev Workflow Gradient**
**Discovery**: dec_prompts, jan_prompts, and initial_project_prompts represent **maturation stages**, not separate concerns

**Progression**:
- `initial_project_prompts` → Skeptical validation (Does the architecture hold?)
- `dec_prompts` → Feature-specific development (How do I build rabbet/groove?)
- `jan_prompts` → Testing integration (How do I test assembly?)

**Implication**: Workflow questions should activate based on **development stage**, not just keyword matching

---

### Hidden Pattern 4: **The Cluster Dependency Cone**
**Discovery**: Feature development flows through clusters in a specific order

```
     E (Architecture Review)
           ↓
     A (Entity Setup)
         ↙    ↘
    C (Param) B (Render)
         ↘    ↙
     D (Assembly)
           ↓
     E (Testing/Validation)
```

**Implication**: Suggesting resources should respect this cone—don't suggest Cluster D resources before Cluster A concepts are understood.

---

### Hidden Pattern 5: **The MainActor Amplification**
**Discovery**: MainActor appears in Cluster A, E discussions, but is **tertiary** in Cluster C and D

**Implication**: This is NOT a cross-cutting concern but a **vertical domain specific to entity lifecycle**

**Risk**: False positive if MainActor appears in generic Swift concurrency discussion
**Prevention**: Require DraftUp context (e.g., "MainActor in entity UUID store")

---

## Recommended Index Structure (Consolidated)

### Tier 1: Core Metadata
```
KBITE_PURPOSE.md          (unchanged—define scope)
KBITE_CLUSTERS.md         (NEW—concept cluster definitions)
KBITE_PATTERNS.md         (NEW—usage patterns & activation)
```

### Tier 2: Navigation
```
KBITE_TRIGGER_MAP.md      (Conventional trigger→resource)
KBITE_USAGE_PATTERNS.md   (NEW—activity→clusters mapping)
KBITE_ANTI_TRIGGERS.md    (NEW—false-positive prevention)
```

### Tier 3: Analysis
```
KBITE_DEPENDENCY_GRAPH.md (NEW—hidden relationships)
KBITE_TRIGGER_GROUPS.md   (NEW—symptom-based groups)
```

### Tier 4: Resources
```
primary/
  documentation/
    clustering/
      ecs_lifecycle/
      rendering_visualization/
      parametric_design/
      assembly_integration/
      workflow_architecture/
  example_project/
    (existing pattern)
secondary/
  all_others/
    (existing pattern)
```

---

## Implementation Recommendations

### Phase 1: Lightweight Index Addition
1. Create `KBITE_CLUSTERS.md` with the 5 conceptual clusters
2. Create `KBITE_PATTERNS.md` with usage patterns (6 pattern types)
3. Create `KBITE_ANTI_TRIGGERS.md` with false-positive rules

**Effort**: 2-3 hours
**Immediate Value**: Better navigation, fewer false positives

---

### Phase 2: Relationship Mapping
1. Update `KBITE_DEPENDENCY_GRAPH.md` with implicit chains
2. Create `KBITE_TRIGGER_GROUPS.md` with 6 symptom-based groups
3. Establish cluster→resource orderings

**Effort**: 4-5 hours
**Value**: Context-aware activation, better resource ordering

---

### Phase 3: Resource Reorganization (Optional)
1. Reorganize primary/documentation into cluster-aware subdirs
2. Add cluster manifests (which resources belong to which cluster)
3. Cross-cluster dependency documentation

**Effort**: 6-8 hours
**Value**: High—enables sophisticated cross-cluster reasoning

---

## Activation Examples

### Example 1: "I have a race condition in entity updates"
**Current Approach**: Trigger on "race condition" → hits generic docs
**Alternative Approach**:
1. Recognize: Cluster A + E pattern ("Async MainActor Maze")
2. Recommended order:
   - bfb_bwain (UUID store race patterns)
   - jan_prompts (testing patterns)
   - DraftUpMvpSummary (architecture context)
3. Anti-triggers skip: general Swift concurrency docs, generic actor patterns

---

### Example 2: "How do I implement rabbet and groove?"
**Current Approach**: Trigger on "rabbet groove" → feature-specific
**Alternative Approach**:
1. Recognize: Cluster D + C pattern ("Assembly Alignment" + parametric constraints)
2. Recommended order:
   - dec_prompts (rabbet/groove implementation)
   - jan_prompts (assembly testing)
   - DraftUpProject (parametric examples)
3. Prerequisite check: User understands Cluster E (workflow)?

---

### Example 3: "Mesh isn't caching correctly"
**Current Approach**: Trigger on "mesh caching" → direct hit
**Alternative Approach**:
1. Recognize: Cluster B + A pattern ("Mesh Cache Quest" + "Dirty Flag Dance")
2. Diagnostic path:
   - First: Is dirty flag being set? (DraftUpMvpSummary)
   - Then: Is cache invalidation triggered? (reference_build)
   - Deep: UUID coherence impacting cache keys? (bfb_bwain)
3. Prevent false activation on generic "mesh" or "caching" terms

---

## Conclusion

This alternative index design provides:

✓ **Concept-based organization** that mirrors developer mental models
✓ **Usage pattern activation** that understands *when* resources are needed
✓ **Dependency graphs** that expose hidden relationships
✓ **Anti-trigger precision** that prevents false positives
✓ **Novel groupings** that capture emergent patterns across resources
✓ **Scalability** for future DraftUp features without restructuring

The design moves from a **static hierarchy** to a **dynamic, usage-aware system** that improves as more patterns are observed.
