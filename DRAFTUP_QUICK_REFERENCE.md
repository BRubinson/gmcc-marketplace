# DraftUp KBite: Quick Reference Card

## 5 Concept Clusters at a Glance

| Cluster | Focus | Resources | Trigger Keywords |
|---------|-------|-----------|------------------|
| **A: ECS Arch** | Entity management, component systems | DraftUpMvpSummary, bfb_bwain, DraftUpProject | triple-id, UUID store, entity, component, dirty flag |
| **B: Rendering** | Meshes, lighting, visualization | reference_build, DraftUpMvpSummary | mesh caching, CSG, IBL, geometry, rendering |
| **C: Parametric** | Expressions, constraints, parameters | DraftUpProject, dec_prompts, jan_prompts | expression, parameter, constraint, formula, binding |
| **D: Assembly** | Feature composition, joinery, integration | dec_prompts, jan_prompts, initial_project_prompts | assembly, feature integration, rabbet, groove, joinery |
| **E: Workflow** | Architecture, testing, validation, patterns | initial_project_prompts, jan_prompts, bfb_bwain | architecture review, test, feature dev, pattern, @globalActor |

---

## 6 Usage Pattern Shortcuts

### 1. 🚀 "Bootstrap New Feature"
**Pattern**: Architecture → Entities → Parameters → Rendering → Assembly → Test
**Resources**: E → A → C → B → D → E
**Keywords**: new feature, feature development, starting feature

### 2. 🐛 "Debug Entity/Scene Issues"
**Pattern**: Observable → Dirty Flag → UUID Reconciliation → Race Condition?
**Resources**: A → B
**Keywords**: entity not showing, UUID mismatch, scene graph, rendering problem

### 3. 🔧 "Implement Mesh Generation"
**Pattern**: CSG Strategy → Caching → Observable Binding → IBL
**Resources**: B → A
**Keywords**: mesh caching, CSG, geometry generation, IBL, lighting

### 4. ⚠️ "Resolve Race Conditions"
**Pattern**: UUID Store → MainActor → Actor Pattern → Testing
**Resources**: A → E
**Keywords**: race condition, async safety, MainActor, @globalActor, concurrent

### 5. 🧩 "Assemble Features Together"
**Pattern**: Joinery Logic → Feature Integration → Acknowledgment → Testing
**Resources**: D → E
**Keywords**: assembly, feature assembly, rabbet, groove, compose, validate

### 6. 💾 "Optimize Mesh Cache"
**Pattern**: Cache Invalidation → Dirty Flag → UUID Coherence → Performance Testing
**Resources**: B → A → E
**Keywords**: mesh caching, cache invalidation, optimization, CSG

---

## 6 Symptom-Based Trigger Groups

### Group 1: "The Triple-ID Problem" (Cluster A)
**Symptoms**: Entity identity questions, UUID confusion, ID sync failures
**Confidence**: 95%
**Go To**: bfb_bwain, then DraftUpMvpSummary

### Group 2: "The Dirty Flag Dance" (Cluster A+B)
**Symptoms**: Rendering not updating, stale views, change detection failures
**Confidence**: 92%
**Go To**: DraftUpMvpSummary, then reference_build

### Group 3: "The Parametric Expression Tango" (Cluster C)
**Symptoms**: Expression parsing, constraint issues, formula evaluation
**Confidence**: 88%
**Go To**: DraftUpProject, then dec_prompts

### Group 4: "The Async MainActor Maze" (Cluster A+E)
**Symptoms**: Race conditions, MainActor violations, concurrent entity access
**Confidence**: 94%
**Go To**: bfb_bwain, then jan_prompts

### Group 5: "The Assembly Alignment" (Cluster D+E)
**Symptoms**: Feature composition, integration issues, joinery validation
**Confidence**: 90%
**Go To**: dec_prompts, then jan_prompts

### Group 6: "The Mesh Cache Quest" (Cluster B)
**Symptoms**: Geometry generation, caching strategy, rendering performance
**Confidence**: 93%
**Go To**: DraftUpMvpSummary, then reference_build

---

## Anti-Triggers Checklist

### 🚫 Don't Trigger On:
- ❌ Generic `swift` or `code` (need DraftUp context)
- ❌ `visionOS` alone (use with "DraftUp rendering")
- ❌ `SwiftUI` alone (use with "DraftUp preview")
- ❌ `bug`, `performance`, `refactor` (too generic)
- ❌ `git workflow`, `testing` alone (too broad)
- ❌ Generic `documentation` (use context)

### ✅ DO Trigger On:
- ✅ `triple-id` or `UUID store` (specific to DraftUp ECS)
- ✅ `dirty flag` (specific pattern)
- ✅ `CSG mesh` (specific to rendering)
- ✅ `expression parser` (specific to parametric)
- ✅ `rabbet groove` (specific to assembly)
- ✅ `MainActor` + entity context (specific domain)

---

## Dependency Cone (Resource Order)

```
     Start Here: E (Architecture)
           ↓
     A (Entity Setup)
         ↙    ↘
    C (Param) B (Render)
         ↘    ↙
     D (Assembly)
           ↓
     End Here: E (Testing/Validation)
```

**Rule**: Never suggest Cluster D before understanding Cluster A

---

## Resource Quick-Reference

| Resource | Best For | Weakness | Cluster |
|----------|----------|----------|---------|
| **DraftUpMvpSummary** | Architecture overview, triple-ID, dirty flag | High-level, not implementation details | A, B |
| **reference_build** | VisionOS patterns, IBL, Observable, CSG caching | Platform-specific, not all patterns | B, E |
| **DraftUpProject** | Practical examples, UUID store, expression parser | Project-specific, may not generalize | A, C |
| **dec_prompts** | Feature dev details, rabbet/groove, assembly | December-specific, older patterns | D, E |
| **jan_prompts** | Testing patterns, GM-CDE workflow, @globalActor | January-specific, newer patterns | E, A |
| **initial_project_prompts** | Architecture review, acknowledgment protocol | Abstract, not code-focused | E |
| **bfb_bwain** | UUID race conditions, Actor patterns, async safety | Deep-dive only, not overview | A, E |

---

## Decision Matrix

| Question | Activation Path | Primary Resource | Backup |
|----------|-----------------|------------------|--------|
| "How do entities work?" | Cluster A | DraftUpMvpSummary | bfb_bwain |
| "Why isn't my mesh showing?" | Triple-ID Problem → Dirty Flag Dance | DraftUpMvpSummary | reference_build |
| "How do I cache meshes?" | Mesh Cache Quest | DraftUpMvpSummary | reference_build |
| "How do I make parameters?" | Parametric Expression Tango | DraftUpProject | dec_prompts |
| "How do I assemble features?" | Assembly Alignment | dec_prompts | jan_prompts |
| "Race condition in entities?" | Async MainActor Maze | bfb_bwain | jan_prompts |
| "How should I structure features?" | Bootstrap New Feature (E path) | initial_project_prompts | jan_prompts |
| "How do I test assembly?" | Assembly Alignment (E path) | jan_prompts | initial_project_prompts |

---

## Implementation Checklist

### To Enable This System:

- [ ] Create `KBITE_CLUSTERS.md` with 5 cluster definitions
- [ ] Create `KBITE_PATTERNS.md` with 6 usage patterns
- [ ] Create `KBITE_ANTI_TRIGGERS.md` with false-positive rules
- [ ] Create `KBITE_DEPENDENCY_GRAPH.md` with resource chains
- [ ] Create `KBITE_TRIGGER_GROUPS.md` with 6 symptom groups
- [ ] Update trigger system to recognize pattern types
- [ ] Add confidence scores to activation logic
- [ ] Test with sample prompts from each cluster

---

## Example Activation Flows

### Flow 1: Mesh Debugging
```
User: "The CSG mesh isn't showing up"
    ↓ Recognize "mesh" + "not showing"
    ↓ Activate: Dirty Flag Dance (92% confidence)
    ↓ Recommend: DraftUpMvpSummary → reference_build
    ↓ Check: Is dirty flag being set? Is Observable firing?
```

### Flow 2: Feature Assembly
```
User: "I need to assemble rabbet and groove features"
    ↓ Recognize "rabbet" + "groove" + "assemble"
    ↓ Activate: Assembly Alignment (90% confidence)
    ↓ Recommend: dec_prompts → jan_prompts
    ↓ Check: Feature parameters defined? Integration tested?
```

### Flow 3: Race Condition
```
User: "Race condition when updating entity UUID"
    ↓ Recognize "race" + "UUID" + "entity"
    ↓ Activate: Async MainActor Maze (94% confidence)
    ↓ Recommend: bfb_bwain → jan_prompts
    ↓ Check: MainActor isolation? Actor boundaries?
```

---

## Notes for Forge Build

When building DraftUp during "forge up":
1. **Check Architecture First** (Cluster E) - Understand design decisions
2. **Understand Entity System** (Cluster A) - Core to everything else
3. **Implement in Order** - E → A → C → B → D → E
4. **Use Symptom Groups** - When stuck, use trigger groups not keywords
5. **Check Anti-Triggers** - Avoid unrelated documentation
6. **Reference Dependencies** - Use dependency cone to order learning

This keeps the knowledge organized **by how it's actually used**, not by tier.
