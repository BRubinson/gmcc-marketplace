# DraftUp KBite Implementation Guide
**Purpose**: Step-by-step integration of alternative index design
**Timeline**: Phase 1 (lightweight) = 2-3 hours; Phase 2 (full) = 6-8 hours
**Target**: Forge build support and feature development acceleration

---

## Phase 1: Lightweight Implementation (2-3 hours)

### Step 1.1: Create KBITE_CLUSTERS.md

**File Location**: `/kbites/draftup_project/KBITE_CLUSTERS.md`

**Template Content**:
```markdown
# KBite Clusters: draftup_project

## Cluster A: ECS Architecture & Entity Lifecycle
**When to use**: Entity management, component systems, identity questions
**Primary Resources**:
- DraftUpMvpSummary
- bfb_bwain
- DraftUpProject

**Key Concepts**:
- Triple-ID system (UUID, local, persistent)
- Dirty flag tracking
- MainActor safety

## Cluster B: Rendering & Visualization
[Similar structure...]

## Cluster C: Parametric Design
[Similar structure...]

## Cluster D: Assembly & Feature Integration
[Similar structure...]

## Cluster E: Development Workflow
[Similar structure...]
```

**Effort**: 30 minutes

---

### Step 1.2: Create KBITE_PATTERNS.md

**File Location**: `/kbites/draftup_project/KBITE_PATTERNS.md`

**Template Content**:
```markdown
# Usage Patterns: draftup_project

## Pattern 1: Bootstrap New Feature
**Typical Workflow**: E → A → C → B → D → E
**Questions Asked**:
- "How should I structure this?"
- "What entities do I need?"
- "How do I add parameters?"

## Pattern 2: Debug Entity/Scene Issues
[Similar structure...]

## Pattern 3: Implement Mesh Generation
[Similar structure...]

## Pattern 4: Resolve Race Conditions
[Similar structure...]

## Pattern 5: Assemble Features Together
[Similar structure...]

## Pattern 6: Optimize Mesh Cache
[Similar structure...]
```

**Effort**: 30 minutes

---

### Step 1.3: Create KBITE_ANTI_TRIGGERS.md

**File Location**: `/kbites/draftup_project/KBITE_ANTI_TRIGGERS.md`

**Template Content**:
```markdown
# Anti-Triggers: draftup_project

## Over-Broad Terms
| Term | Problem | Context Needed |
|------|---------|---|
| swift | Language, not framework | "Swift concurrency in entity updates" |
| code | Too generic | "Code for triple-ID reconciliation" |
| bug | Generic debugging | "Bug in UUID store race condition" |

## External Systems
| Term | Reason | Use Instead |
|------|--------|---|
| visionOS | Platform feature | "visionOS rendering in DraftUp" |
| SwiftUI | UI framework | "SwiftUI preview for parametric design" |

[Continue with full anti-trigger table...]
```

**Effort**: 45 minutes

---

### Step 1.4: Update KBITE_INDEX.md

**Location**: `/kbites/draftup_project/KBITE_INDEX.md`

Add sections:
```markdown
## Cluster Organization
See [KBITE_CLUSTERS.md](./KBITE_CLUSTERS.md) for concept-based organization

## Usage Patterns
See [KBITE_PATTERNS.md](./KBITE_PATTERNS.md) for development workflows

## False-Positive Prevention
See [KBITE_ANTI_TRIGGERS.md](./KBITE_ANTI_TRIGGERS.md) for what NOT to activate on
```

**Effort**: 15 minutes

---

### Phase 1 Deliverables
- ✅ 3 new index files (CLUSTERS, PATTERNS, ANTI_TRIGGERS)
- ✅ Updated main INDEX
- ✅ 70% false-positive reduction (estimated)
- ✅ Easier navigation for developers

**Phase 1 Total**: ~2 hours

---

## Phase 2: Full Implementation (6-8 hours)

### Step 2.1: Create Dependency Graph Documents

**File Location**: `/kbites/draftup_project/KBITE_DEPENDENCY_GRAPH.md`

**Content Structure**:
```markdown
# Dependency Graph: draftup_project

## Resource Dependency Chains

### Chain 1: UUID/Dirty Flag Coupling
- Resources: DraftUpMvpSummary, bfb_bwain, DraftUpProject
- Activation: Mention one → suggest all
- Precedence: DraftUpMvpSummary (overview) → bfb_bwain (implementation)

### Chain 2: Rendering Pipeline
- Resources: reference_build, DraftUpMvpSummary, DraftUpProject
- Activation: Mesh/rendering questions
- Precedence: reference_build (patterns) → DraftUpMvpSummary (why)

[10 chains total from DRAFTUP_HIDDEN_PATTERNS.md]

## Activation Rules
[Matrix of trigger combinations and precedence]
```

**Effort**: 2 hours (copy from DRAFTUP_HIDDEN_PATTERNS.md)

---

### Step 2.2: Create Trigger Groups Document

**File Location**: `/kbites/draftup_project/KBITE_TRIGGER_GROUPS.md`

**Content Structure**:
```markdown
# Trigger Groups: draftup_project

## Group 1: Triple-ID Problem
**Symptoms**: Entity identity confusion, UUID sync failures
**Keywords**: triple-id, UUID store, entity identity
**Confidence**: 95%
**Resource Order**: bfb_bwain → DraftUpMvpSummary → DraftUpProject

[6 groups total from DRAFTUP_QUICK_REFERENCE.md]
```

**Effort**: 1.5 hours

---

### Step 2.3: Enhance Resource Metadata

**File Location**: `/kbites/draftup_project/resources.json` (new)

**Content**:
```json
{
  "resources": [
    {
      "name": "DraftUpMvpSummary",
      "clusters": ["A", "B"],
      "patterns": ["bootstrap", "debug", "cache"],
      "stage": "1-2",
      "confidence": 95,
      "dependencies": ["none"],
      "antiTriggers": ["game_engine", "shader_optimization"]
    },
    ...
  ],
  "clusters": {
    "A": { "name": "ECS Architecture", ... },
    ...
  }
}
```

**Effort**: 2 hours

---

### Step 2.4: Create Decision Matrix

**File Location**: `/kbites/draftup_project/KBITE_DECISION_MATRIX.md`

**Content**:
```markdown
# Decision Matrix: draftup_project

| User Question | Pattern | Primary | Secondary | Tertiary |
|---|---|---|---|---|
| "How do entities work?" | Cluster-A-Intro | DraftUpMvpSummary | bfb_bwain | reference_build |
| "Why isn't mesh showing?" | Dirty-Flag-Dance | DraftUpMvpSummary | reference_build | DraftUpProject |
| ... | ... | ... | ... | ... |

[30+ rows covering common questions]
```

**Effort**: 1.5 hours

---

### Step 2.5: Create Relationship Map

**File Location**: `/kbites/draftup_project/KBITE_RELATIONSHIPS.md`

**Content**:
```markdown
# Relationships: draftup_project

## Outgoing Dependencies
- draftup_project → claude_customization (for @globalActor, MainActor patterns)
- draftup_project → future_kbite:swift_concurrency (async/await deep dives)

## Resource Relationships
| From | To | Strength | Type |
|------|----|----|------|
| DraftUpMvpSummary | bfb_bwain | HIGH | explains-implementation |
| DraftUpMvpSummary | DraftUpProject | HIGH | provides-example |
| reference_build | DraftUpMvpSummary | MEDIUM | shows-application |
```

**Effort**: 1 hour

---

### Phase 2 Deliverables
- ✅ Dependency graph with 10 implicit patterns
- ✅ 6 symptom-based trigger groups with confidence scores
- ✅ Resource metadata in structured format
- ✅ Decision matrix for 30+ common questions
- ✅ Relationship map for kbite ecosystem

**Phase 2 Total**: ~6.5 hours

---

## Phase 3: Infrastructure (Optional, 4-6 hours)

### Step 3.1: Reorganize Resources into Clusters

Move resources from flat structure:
```
primary/documentation/
  DraftUpMvpSummary/
  reference_build/
  DraftUpProject/
  ...
```

To cluster-aware structure:
```
primary/documentation/
  cluster-a-ecs/
    DraftUpMvpSummary/
    bfb_bwain/
    DraftUpProject/
  cluster-b-rendering/
    reference_build/
    DraftUpMvpSummary/ (symlink)
  cluster-c-parametric/
    DraftUpProject/
    dec_prompts/
  cluster-d-assembly/
    dec_prompts/
    jan_prompts/
  cluster-e-workflow/
    initial_project_prompts/
    jan_prompts/
```

**Effort**: 2 hours

---

### Step 3.2: Add Cluster Manifest Files

Create `MANIFEST.md` in each cluster directory:
```markdown
# Cluster A: ECS Architecture Manifest

**Primary Resources**:
- DraftUpMvpSummary - Architectural overview
- bfb_bwain - Implementation details
- DraftUpProject - Practical examples

**Key Concepts**:
- Triple-ID system
- Dirty flag tracking
- MainActor safety

**Entry Points**:
- Starting point: DraftUpMvpSummary (architecture first)
- Deep dive: bfb_bwain (implementation)
- Practical: DraftUpProject (see it work)

**Related Clusters**: B (rendering), E (testing)
```

**Effort**: 1.5 hours

---

### Step 3.3: Create Search Index

Add `SEARCH_INDEX.json`:
```json
{
  "triggers": {
    "triple-id": {
      "cluster": "A",
      "group": "Triple-ID-Problem",
      "confidence": 95,
      "resources": ["bfb_bwain", "DraftUpMvpSummary"],
      "patterns": ["debug", "bootstrap"]
    },
    ...
  },
  "antiTriggers": {
    "game_engine": ["B", "ignore"],
    ...
  }
}
```

**Effort**: 1.5 hours

---

### Phase 3 Deliverables
- ✅ Cluster-aware directory structure
- ✅ Cluster manifests
- ✅ Searchable index with anti-triggers
- ✅ Scalable infrastructure for future clusters

**Phase 3 Total**: ~5 hours (optional)

---

## Integration Checklist

### Before Phase 1
- [ ] Read DRAFTUP_KBITE_ALTERNATIVE_INDEX.md (this design doc)
- [ ] Review DRAFTUP_QUICK_REFERENCE.md (activation patterns)
- [ ] Review DRAFTUP_HIDDEN_PATTERNS.md (understanding)

### Phase 1 Checklist
- [ ] Create KBITE_CLUSTERS.md
- [ ] Create KBITE_PATTERNS.md
- [ ] Create KBITE_ANTI_TRIGGERS.md
- [ ] Update KBITE_INDEX.md with cross-references
- [ ] Test with 5 sample prompts (one per pattern)

### Phase 2 Checklist
- [ ] Create KBITE_DEPENDENCY_GRAPH.md
- [ ] Create KBITE_TRIGGER_GROUPS.md
- [ ] Create resources.json metadata
- [ ] Create KBITE_DECISION_MATRIX.md
- [ ] Create/update KBITE_RELATIONSHIPS.md
- [ ] Test with 20 sample prompts (diverse questions)

### Phase 3 Checklist
- [ ] Reorganize resource directories (optional)
- [ ] Create cluster manifests
- [ ] Build search index
- [ ] Test cross-cluster activation
- [ ] Document reorganization in README

---

## Testing Strategy

### Unit Tests (Phase 1)
```
Test: "triple-id" trigger
Expected: Activates Group 1, confidence 95%
Suggests: bfb_bwain, DraftUpMvpSummary
Skips: generic UUID docs

Test: "MainActor" trigger (no entity context)
Expected: Anti-trigger blocks activation
Suggests: "Need more context"

Test: "swiftui preview" trigger
Expected: Activates Cluster C pattern
Suggests: DraftUpProject, dec_prompts
```

### Integration Tests (Phase 2)
```
Scenario 1: "How do entities work?"
Expected Path: E (architecture) → A (entities) → examples

Scenario 2: "Mesh isn't showing in visionOS"
Expected Path: Dirty Flag Dance → UUID verification → rendering check

Scenario 3: "Race condition in entity updates"
Expected Path: Async MainActor Maze → bfb_bwain → testing patterns
```

### Stress Tests (Phase 2)
```
Test: 20 common developer questions
Success: >80% correct primary resource suggested
Metric: Confidence scores align with resource quality
Metric: No anti-triggers false-positive
```

---

## Rollout Timeline

### Week 1: Phase 1 (Lightweight, Safe)
- Day 1-2: Create cluster and pattern docs
- Day 2-3: Create anti-trigger doc
- Day 3: Update INDEX, test with developers
- Minimum viable improvement: 70% false-positive reduction

### Week 2: Phase 2 (Full Implementation)
- Day 1-2: Create dependency graph and trigger groups
- Day 2-3: Build resource metadata and decision matrix
- Day 3: Relationship mapping, comprehensive testing
- Full system ready: All 10 hidden patterns captured

### Week 3: Phase 3 (Infrastructure, Optional)
- Day 1: Resource reorganization
- Day 2: Cluster manifests
- Day 3: Search index, integration testing
- Advanced features: Cross-cluster reasoning, predictive activation

---

## Success Metrics

### Phase 1 Success
- ✅ Developers use clusters to understand organization (+40% faster navigation)
- ✅ Anti-triggers reduce noise (-70% false positives)
- ✅ Usage patterns guide feature development (+30% confidence)

### Phase 2 Success
- ✅ Dependency graph reveals hidden connections (discover 5+ new patterns)
- ✅ Trigger groups accelerate debugging (-50% time finding info)
- ✅ Decision matrix covers 90%+ common questions

### Phase 3 Success (Optional)
- ✅ Cluster structure scales to 10+ future clusters
- ✅ Search performance <100ms for complex queries
- ✅ New developers onboard 2x faster

---

## Maintenance & Evolution

### Quarterly Review
- Collect usage data on most-activated clusters/patterns
- Identify new patterns from developer feedback
- Update confidence scores based on actual success

### Annual Redesign
- Review if cluster structure still fits
- Consider new clusters for new features
- Consolidate redundant patterns

### Feedback Loop
- Developers report false positives → update anti-triggers
- Developers request cluster → assess if new pattern
- Performance metrics → optimize activation order

---

## Quick Start (TL;DR)

**To implement immediately**:
1. Copy KBITE_CLUSTERS section from DRAFTUP_QUICK_REFERENCE.md
2. Create KBITE_CLUSTERS.md with 5 clusters
3. Create KBITE_ANTI_TRIGGERS.md with top 10 anti-triggers
4. Update existing triggers to check anti-triggers first
5. Test with 5 prompts

**Time commitment**: 1.5 hours
**Impact**: 50-70% false-positive reduction
**Next step**: Phase 2 when resources allow

---

## Resources for Implementation

- **Design Document**: DRAFTUP_KBITE_ALTERNATIVE_INDEX.md
- **Quick Reference**: DRAFTUP_QUICK_REFERENCE.md
- **Hidden Patterns**: DRAFTUP_HIDDEN_PATTERNS.md
- **Existing KBite**: `/kbites/claude_customization/` (reference structure)

All files should be in same directory as this guide.
