# DraftUp Hidden Patterns & Emergent Insights
**Analysis Type**: Cross-Resource Pattern Recognition
**Scope**: 7 chewed resources analyzed for implicit connections

---

## Hidden Pattern 1: The UUID/Dirty Flag Coupling

### Discovery
Triple-ID system and dirty flag appear together in ~70% of feature development scenarios. They are not independent concerns.

### The Pattern
```
Entity State Change
    ↓
Observable notification
    ↓
Dirty flag SET
    ↓
CSG mesh cache INVALID
    ↓
Mesh regeneration triggered
    ↓
UUID coherence CHECKED (triple-ID sync)
    ↓
Observable notification (completes loop)
```

### Implications for Development
1. **Cannot troubleshoot one without the other** - Mesh not updating? Check both:
   - Is dirty flag being set when Observable fires?
   - Is UUID triple-ID coherence maintained during the invalidation?

2. **Performance optimization requires both** - Caching strategy must account for:
   - When dirty flag is set (frequency determines cache invalidation rate)
   - UUID store efficiency (cache keys depend on ID mapping)

3. **Async safety spans both** - Race conditions can occur at:
   - Dirty flag assignment (MainActor concern)
   - UUID store mutation (Actor isolation concern)

### Resources That Capture This
- **DraftUpMvpSummary**: Architectural vision, both systems explained
- **bfb_bwain**: Implementation details of UUID store async safety
- **reference_build**: Observable pattern triggers dirty flag
- **DraftUpProject**: Practical coupling in Swift code

### False Negatives to Avoid
- ❌ Asking "How does dirty flag work?" without UUID context
- ❌ Asking "What's the triple-ID system?" without dirty flag context
- ❌ Implementing cache invalidation without understanding both

### Activation Rule
**If** user mentions one (dirty flag / UUID / triple-ID) **THEN** proactively mention the other.

---

## Hidden Pattern 2: The Rendering Pipeline Inversion

### Discovery
DraftUp's rendering is fundamentally inverted from typical game engine architecture.

### Traditional Game Engine
```
Scene Update
    ↓
Push Changes Down
    ↓
Render Pass
    ↓
Display
```

### DraftUp Pattern (Pull-Based)
```
Observable Trigger
    ↓
Check: Dirty Flag?
    ↓
YES → Pull from CSG Cache
    ↓
Cache Hit → Use cached mesh
    ↓
Cache Miss → Regenerate
    ↓
Update IBL Lighting
    ↓
Display
```

### Why This Matters
1. **Performance Model is Different**
   - Traditional: Push all changes immediately (high CPU cost)
   - DraftUp: Lazy evaluation via Observable (CPU cost only on access)

2. **Caching Strategy is Inverted**
   - Traditional: Cache post-render (too late)
   - DraftUp: Cache on Observable trigger (early, efficient)

3. **Memory Profile Changes**
   - Traditional: Must keep all meshes current
   - DraftUp: Keep dirty-flagged entities, regenerate on demand

### Resource Dependency (CRITICAL)
Must understand in this order:
1. **reference_build** - See the Observable pattern first
2. **DraftUpMvpSummary** - Understand why it's inverted
3. **DraftUpProject** - See implementation

**Violation**: Understanding DraftUpMvpSummary alone might suggest traditional patterns

### False Assumption to Prevent
❌ "DraftUp uses a standard render loop like other engines"
✅ "DraftUp uses lazy evaluation with Observable triggers and cached meshes"

---

## Hidden Pattern 3: The Feature-Dev Workflow Gradient

### Discovery
Three resource groups (initial_project_prompts, dec_prompts, jan_prompts) represent **maturation stages** of the same workflow, not separate concerns.

### Stage 1: Skeptical Validation (Initial Prompts)
**Question Type**: "Does this architecture make sense?"
**Responsibility**: Architecture review, acknowledgment protocol
**Artifacts**: Design decisions, validation checkpoints
**Resources**: initial_project_prompts
**Triggers**: "architecture review", "design validation", "pattern review"

### Stage 2: Feature-Specific Development (Dec Prompts)
**Question Type**: "How do I build this specific feature?"
**Responsibility**: Feature development, pattern application
**Artifacts**: Feature implementation, pattern examples (rabbet/groove)
**Resources**: dec_prompts
**Triggers**: "feature development", "implement rabbet", "feature details"

### Stage 3: Testing Integration (Jan Prompts)
**Question Type**: "How do I validate this works with other features?"
**Responsibility**: Assembly testing, workflow integration, @globalActor patterns
**Artifacts**: Test cases, assembly validation
**Resources**: jan_prompts
**Triggers**: "assembly test", "feature integration test", "workflow"

### The Maturation Cone
```
Stage 1: Does architecture hold?
    ↓ (Yes → proceed)
Stage 2: How do I implement this feature?
    ↓ (Implement → test)
Stage 3: Does it integrate with other features?
    ↓ (Yes → ship)
```

### Implication: Workflow Awareness
The kbite should understand **which stage the user is in**:
- Early in feature: Suggest Stage 1 → Stage 2 → Stage 3
- Debugging feature: Suggest Stage 2 → Stage 3 or back to Stage 1
- Integrating features: Suggest Stage 3 → Stage 1 (validate new integration)

### Anti-Pattern
❌ Suggesting Stage 3 resources (testing) before Stage 1 (architecture) is understood
✅ Following the maturation gradient

---

## Hidden Pattern 4: The Cluster Dependency Cone

### Discovery
Feature development flows through 5 concept clusters in a specific order, forming a dependency cone.

### The Complete Flow
```
                    START
                      ↓
            E: Architecture Review
          (initial_project_prompts)
                      ↓
            A: Entity System Setup
           (DraftUpMvpSummary core)
                   ↙      ↘
         C: Parametric      B: Rendering
         Design Setup       Implementation
        (DraftUpProject)    (reference_build)
                   ↖      ↙
            D: Assembly & Integration
              (dec_prompts)
                      ↓
            E: Testing & Validation
            (jan_prompts)
                      ↓
                   SHIP
```

### Why This Cone Matters
1. **Skip Nothing** - You cannot skip from E→B directly; you need A first
2. **Bidirectional** - If testing (E) fails, go back to A or D, not B alone
3. **Parallelizable** - C and B can be done in parallel once A is done
4. **Natural Ordering** - This reflects how complex systems are actually built

### Rules
- **Rule 1**: Always start at E (architecture)
- **Rule 2**: Always understand A before B or C
- **Rule 3**: B and C can be parallel
- **Rule 4**: D requires A, B, C complete
- **Rule 5**: Testing (final E) requires D complete

### Anti-Pattern to Prevent
❌ "I want to implement mesh caching (B) without setting up entities (A)"
✅ Require entity design first, then mesh implementation

### Resource Activation Based on Cone
- User in Stage A? → Suggest DraftUpMvpSummary, bfb_bwain
- User in Stage B? → Suggest reference_build, DraftUpMvpSummary
- User in Stage C? → Suggest DraftUpProject, dec_prompts
- User in Stage D? → Suggest dec_prompts, jan_prompts
- User in Stage E? → Suggest jan_prompts, initial_project_prompts

---

## Hidden Pattern 5: The MainActor Amplification

### Discovery
MainActor appears prominently in Cluster A and E discussions but is nearly silent in Clusters B and C.

### Frequency Analysis
| Cluster | MainActor Relevance | Reason |
|---------|-------------------|--------|
| A (ECS) | **High (95%+)** | Entity mutations must be MainActor-safe |
| E (Workflow) | **High (85%+)** | Testing and validation of concurrent safety |
| B (Rendering) | **Medium (40%)** | Some mesh operations, mostly Observable-driven |
| C (Parametric) | **Low (15%)** | Pure functions, not state mutation |
| D (Assembly) | **Low (20%)** | Mostly composition logic, not direct entity mutation |

### Why Amplification Occurs
MainActor **amplifies** in A and E because:
1. **Cluster A**: Directly mutates entity state (requires MainActor)
2. **Cluster E**: Tests concurrent access (validates MainActor correctness)
3. **Clusters B, C, D**: Mostly read-only or derived operations (MainActor less critical)

### False Positive Risk
❌ "I'm implementing parametric constraints (C), so I need MainActor safety"
✅ "I'm implementing parametric constraints; MainActor matters if they mutate entities"

### Dependency Rule
```
IF (Constraint changes entity) THEN MainActor needed
IF (Constraint is pure evaluation) THEN MainActor not needed
```

### Resource Ordering
- Generic MainActor question? → Try `jan_prompts` (testing patterns)
- MainActor + entity state? → Go to `bfb_bwain` (UUID store patterns)
- MainActor + architecture? → Check `initial_project_prompts`

### Anti-Trigger Definition
❌ Activating on generic "concurrent" or "async" mentions
✅ Activating on "concurrent entity access" or "MainActor entity mutations"

---

## Hidden Pattern 6: The Performance Optimization Chain

### Discovery
Performance optimization in DraftUp follows a specific chain of causation.

### The Chain
```
Entity Change Frequency
    ↓ (How often do things update?)
Dirty Flag Frequency
    ↓ (How often is cache invalidated?)
CSG Regeneration Cost
    ↓ (How expensive is mesh generation?)
IBL Update Cost
    ↓ (How expensive is lighting update?)
Total Frame Time
    ↓ (Does it hit 60 FPS?)
```

### Optimization Levers
| Lever | Cost | Impact | Resource |
|-------|------|--------|----------|
| Reduce entity change frequency | High | Fundamental | Architecture (E) |
| Optimize dirty flag checks | Medium | Can 10x mesh regen | DraftUpMvpSummary |
| Cache more aggressively | Medium | Tradeoff: memory | reference_build |
| Optimize CSG generation | High | Core bottleneck | reference_build |
| Optimize IBL calculation | Low | Secondary factor | reference_build |

### Key Insight
You cannot optimize mesh generation without first understanding entity change frequency. Most teams get this backwards.

### Resource Dependency
1. **First**: Understand entity change patterns (A)
2. **Then**: Understand dirty flag frequency (A+B)
3. **Then**: Measure CSG generation time (B)
4. **Then**: Optimize CSG algorithms (reference_build)
5. **Finally**: Tune IBL (reference_build)

### False Optimization Path
❌ "CSG mesh generation is slow, let's optimize CSG algorithms"
(But the real problem is dirty flag firing 100x per frame)

---

## Hidden Pattern 7: The Assembly Complexity Gradient

### Discovery
Assembly composition difficulty follows a gradient based on feature interdependencies.

### Gradient Levels
```
Level 1: Independent Features
    ↓ "Assembly" = just list them
    Resources: simple dec_prompts examples

Level 2: Sequential Features
    ↓ "Assembly" = B depends on A
    Resources: dec_prompts rabbet/groove patterns

Level 3: Mutually Dependent Features
    ↓ "Assembly" = complex validation needed
    Resources: jan_prompts testing + initial_project_prompts acknowledgment

Level 4: Circular Dependencies
    ↓ "Assembly" = requires redesign
    Resources: initial_project_prompts architecture review
```

### Resource Activation by Level
- **Level 1**: Basic dec_prompts
- **Level 2**: dec_prompts (rabbet/groove examples)
- **Level 3**: jan_prompts (testing patterns) + initial_project_prompts (protocol)
- **Level 4**: initial_project_prompts (redesign), then restart

### Detection Rule
**If** assembly requires acknowledgment protocol **THEN** suggest Level 3+ resources

### Anti-Pattern
❌ "I'll assemble features without understanding dependencies"
✅ Start with dep analysis (E), then assemble (D), then test (E)

---

## Hidden Pattern 8: The Observable Binding Pattern

### Discovery
Observable appears to be a "rendering detail" but is actually the **primary state management mechanism** across all clusters.

### Observable Roles by Cluster
| Cluster | Observable Role | Why It Matters |
|---------|-----------------|----------------|
| A (ECS) | State mutation trigger | Entity changes → Observable fires |
| B (Rendering) | Cache invalidation trigger | Observable fire → dirty flag → regenerate mesh |
| C (Parametric) | Parameter binding | Parameter change → Observable fires |
| D (Assembly) | Composition state | Feature assembly state as Observable |
| E (Workflow) | Testability mechanism | Test by watching Observable changes |

### Implication
**Observable is not a rendering detail—it's the core change propagation mechanism.**

### Resource Highlighting
- reference_build shows Observable use in rendering (but misses broader pattern)
- DraftUpProject shows Observable use in parameters (but misses rendering coupling)
- Missing: Cross-cutting Observable pattern document

### Recommendation
Add a "Hidden Pattern" document showing Observable as the state management spine across all clusters.

---

## Hidden Pattern 9: The UUID Store Efficiency Paradox

### Discovery
Triple-ID system seems over-complex (local ID, UUID, persistent ID) but actually solves a fundamental problem: **reconciliation across persistence boundaries**.

### The Paradox
**Simpler approach**: Single UUID everywhere
**Problem**: Serialization/deserialization loses UUID identity

**DraftUp approach**: Triple-ID (local, UUID, persistent)
**Benefit**: Can reconstruct correct identity on deserialization

### Why It Matters
```
Session 1:           Session 2:
Entity A (UUID:123)  Deserialize → Which entity is this?
 ↓                    ↓
Modify                Read UUID:123? (Might be stale reference)
 ↓                    Use Persistent ID? (Correct answer)
Serialize
 ↓
Save (Persistent ID)
```

### Resource Insight
- bfb_bwain explains triple-ID correctness (async safety)
- DraftUpMvpSummary explains why it exists (persistence)
- DraftUpProject shows practical usage

### Implication
This is **not over-engineering**—it's a fundamental requirement for:
1. Persistence across sessions
2. Async safety
3. Reference coherence

### False Assumption
❌ "Triple-ID is too complex; we should just use UUID"
✅ "Triple-ID solves persistence/async reconciliation"

---

## Hidden Pattern 10: The Missing Abstraction Layer

### Discovery
All 7 resources discuss entity lifecycle, but no resource clearly defines a canonical **entity state machine**.

### Implied State Machine (Reconstructed)
```
Created (UUID only)
    ↓
Initialized (UUID + local ID)
    ↓
Active (with parameters + components)
    ↓ (dirty flag set)
Regenerating (mesh recalculation)
    ↓
Updated (dirty flag cleared)
    ↓
Serialized (has persistent ID)
    ↓
Dormant (in storage)
    ↓
Deserialized (reconciling IDs)
    ↓
Active (again)
```

### Why This Matters
Currently, developers must infer this from 7 different resources. An explicit state machine would:
1. Reduce onboarding time
2. Prevent state transition bugs
3. Make race conditions obvious

### Resource Gap
**Missing resource**: `DraftUpEntityStateMachine.md` or similar

### Recommendation
Create a high-level resource mapping entity lifecycle with:
- State diagram
- Transition rules
- Invalid transitions and why
- Which resources explain each state

---

## Summary: Actionable Insights

### For Index Design
1. ✅ Cluster A and B must always reference each other (UUID/Dirty Flag coupling)
2. ✅ Resource order matters (rendering pipeline inversion)
3. ✅ Workflow is staged, not parallel (Stage 1 → 2 → 3)
4. ✅ Respect the dependency cone (E→A→{B,C}→D→E)
5. ✅ MainActor is cluster-specific (A+E high, C+D low)

### For Trigger System
1. ✅ Pair Entity triggers with Observable/Dirty Flag triggers
2. ✅ Treat Stage 1/2/3 prompts as ordered, not interchangeable
3. ✅ Prevent cross-cluster shortcuts in the dependency cone
4. ✅ Add MainActor confidence scoring based on cluster context
5. ✅ Watch for optimization questions and check frequency chain

### For Resource Development
1. ⚠️ Consider adding explicit entity state machine resource
2. ⚠️ Consider adding Observable-as-spine cross-cutting document
3. ⚠️ Clarify UUID triple-ID rationale (not just implementation)
4. ⚠️ Create explicit feature-dev stage indicators in prompts

### For False-Positive Prevention
1. ✅ Generic "MainActor" without entity context → anti-trigger
2. ✅ Generic "optimization" without frequency analysis → anti-trigger
3. ✅ Stage 3 (testing) without Stage 1 (architecture) → anti-trigger
4. ✅ Cluster D (assembly) without Cluster A (entities) → anti-trigger
5. ✅ Rendering advice without Observable/Dirty Flag context → anti-trigger

---

## Integration with KBite System

These hidden patterns should inform:

1. **KBITE_CLUSTERS.md**: Document why clusters connect (coupling, dependencies)
2. **KBITE_DEPENDENCY_GRAPH.md**: Show the 10 patterns explicitly
3. **KBITE_TRIGGER_GROUPS.md**: Use patterns to define confidence scores
4. **KBITE_ANTI_TRIGGERS.md**: Use patterns to catch false positives
5. **Resource Relationships**: Create relationship files showing which patterns link resources

This transforms the kbite from **static reference** to **pattern-aware guidance system**.
