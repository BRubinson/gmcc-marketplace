# KBite Relationships: draftup_project

## Internal Resource Relationships

### Architecture Foundations Cluster

#### DraftUpMvpSummary (Hub Resource)
**Core hybrid ECS architecture - primary foundation for all other patterns**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| TripleID_System | Implements | Strong | Triple-ID is core to MVP architecture |
| DirtyFlag_Optimization | Implements | Strong | Dirty flag is core optimization mechanism |
| EntityLifecycle_Management | Defines | Strong | MVP defines entity lifecycle patterns |
| FeatureTree_Architecture | Enables | Strong | ECS enables feature tree composition |
| CSG_MeshCaching_System | Enables | Strong | ECS enables mesh caching optimization |
| DraftUpProject | Exemplifies | Medium | Project demonstrates MVP patterns |
| dec_prompts | References | Medium | December prompts build on MVP foundation |

#### TripleID_System (Foundation Support)
**Identification mechanism for entities and components**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| DraftUpMvpSummary | Implements | Strong | Core architectural pattern |
| EntityLifecycle_Management | Supports | Strong | Triple-ID used in entity tracking |
| UUID store | Uses | Strong | UUID is part of triple-ID system |
| DraftUpProject | Exemplifies | Medium | Project uses triple-ID patterns |

#### EntityLifecycle_Management (State Management Core)
**Entity creation, updates, deletion, state transitions**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| DraftUpMvpSummary | Implements | Strong | ECS defines lifecycle |
| bfb_bwain | Details | Strong | TDD approach for lifecycle management |
| FeatureTree_Architecture | Supports | Strong | Features have entity lifecycles |
| AsyncRaceConditions | Challenges | Strong | Lifecycle state accessed concurrently |
| MainActor_Concurrency | Solves | Strong | MainActor coordinates state transitions |
| dec_prompts | References | Medium | Feature development uses lifecycle patterns |
| DraftUpProject | Exemplifies | Medium | Project demonstrates lifecycle patterns |

### Data & State Management Cluster

#### Observable_StateManagement (Reactive Core)
**@Observable macro and reactive property patterns**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| reference_build | Exemplifies | Strong | Reference build uses @Observable extensively |
| DraftUpProject | Exemplifies | Strong | Project demonstrates observable patterns |
| SwiftData_Integration | Integrates | Medium | SwiftData models use @Observable |
| UIPatterns | Depends | Medium | SwiftUI requires observable state |

#### SwiftData_Integration (Persistence Layer)
**Data models and persistent storage**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| Observable_StateManagement | Integrates | Medium | Models often observable |
| DraftUpProject | Exemplifies | Strong | Project uses SwiftData for persistence |
| UUID store | Complements | Medium | UUID store and SwiftData both data layers |

#### UUID store (Async Data Layer)
**Asynchronous entity reference storage**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| bfb_bwain | Discusses | Strong | TDD and race conditions around UUID store |
| AsyncRaceConditions | Challenges | Strong | Concurrency issues in UUID access |
| MainActor_Concurrency | Solves | Strong | MainActor coordinates UUID access |
| EntityLifecycle_Management | Supports | Medium | Entity tracking via UUID |
| DraftUpProject | Exemplifies | Medium | Project uses async UUID patterns |

### Parametric Design Cluster

#### ParametricPrimitives_Design (Parametric Core)
**Parametric primitive system and expression-based design**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| ExpressionParser | Implements | Strong | Parametrics use expression parser |
| ConstraintSystem_Design | Solves | Strong | Constraints enable parametric solving |
| DraftUpProject | Exemplifies | Strong | Project implements parametric design |
| FeatureTree_Architecture | Integrates | Medium | Features can be parametric |

#### ExpressionParser (Expression Evaluation)
**Parsing and evaluating parametric expressions**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| ParametricPrimitives_Design | Implements | Strong | Parser is core to parametrics |
| ConstraintSystem_Design | Supports | Strong | Constraints are expressions |
| DraftUpProject | Exemplifies | Medium | Project implements parser |

#### ConstraintSystem_Design (Parametric Solver)
**Constraint solving and parametric evaluation**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| ParametricPrimitives_Design | Solves | Strong | Solver is core to parametrics |
| ExpressionParser | Consumes | Strong | Solver uses parsed expressions |
| DraftUpProject | Exemplifies | Medium | Project implements constraint system |

### Rendering & Visualization Cluster

#### CSG_MeshCaching_System (Mesh Rendering)
**CSG boolean operations and mesh caching**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| IBL_Rendering | Complements | Strong | Lighting rendered on CSG meshes |
| DirtyFlag_Optimization | Optimizes | Strong | Dirty flags invalidate mesh cache |
| DraftUpMvpSummary | Implements | Strong | CSG is core MVP feature |
| reference_build | Exemplifies | Medium | Reference build uses CSG meshes |
| CameraSimulation | Uses | Medium | Camera previews CSG meshes |

#### IBL_Rendering (Lighting System)
**Image-based lighting and environmental lighting**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| CSG_MeshCaching_System | Lights | Strong | IBL renders on CSG meshes |
| VisionOS_RealityKit | Implements | Strong | RealityKit provides IBL |
| CameraSimulation | Uses | Medium | Camera displays IBL results |
| reference_build | Exemplifies | Strong | Reference build demonstrates IBL |

#### CameraSimulation (Viewport/Preview)
**Simulated camera for rendering preview**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| CSG_MeshCaching_System | Previews | Medium | Camera views CSG meshes |
| IBL_Rendering | Displays | Medium | Camera shows IBL results |
| reference_build | Exemplifies | Strong | Reference build uses simulated camera |
| VisionOS_RealityKit | Implements | Medium | Rendering through RealityKit |

#### VisionOS_RealityKit (Platform Integration)
**VisionOS platform and RealityKit 3D engine**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| IBL_Rendering | Implements | Strong | RealityKit provides IBL |
| CameraSimulation | Implements | Medium | RealityKit handles rendering |
| reference_build | Exemplifies | Strong | Reference build targets VisionOS |

### Assembly & Feature Composition Cluster

#### Assembly_Workflow (Assembly Operations)
**Component assembly, rabbet/groove patterns, joining**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| FeatureTree_Architecture | Enables | Strong | Assemblies compose feature tree |
| Assembly_Testing | Tests | Strong | Assembly tests verify operations |
| dec_prompts | References | Strong | December prompts define assembly patterns |
| EntityLifecycle_Management | Uses | Medium | Assembly affects entity lifecycle |
| FeatureDev_Workflow | Implements | Medium | Assembly is feature implementation |

#### FeatureTree_Architecture (Feature Composition)
**Feature hierarchy, composition, and dependencies**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| DraftUpMvpSummary | Implements | Strong | Feature tree is ECS-based |
| Assembly_Workflow | Composes | Strong | Assembly creates feature tree |
| EntityLifecycle_Management | Manages | Strong | Features have entity lifecycles |
| FeatureDev_Workflow | Implements | Medium | Feature workflow builds tree |
| dec_prompts | References | Medium | December prompts define features |
| ParametricPrimitives_Design | Enhances | Medium | Features can be parametric |

#### Assembly_Testing (Assembly Testing)
**Testing assembly operations and component joining**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| Assembly_Workflow | Tests | Strong | Testing validates assembly |
| FeatureDev_Workflow | Implements | Strong | TDD includes assembly tests |
| bfb_bwain | References | Medium | TDD approach to assembly |
| jan_prompts | References | Medium | January prompts include assembly tests |

### Development Workflow Cluster

#### FeatureDev_Workflow (Feature Development)
**Feature development phases and workflow**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| dec_prompts | Implements | Strong | December prompts define workflow |
| jan_prompts | Implements | Strong | January prompts define workflow |
| bfb_bwain | Implements | Strong | TDD approach to feature dev |
| Assembly_Workflow | Implements | Medium | Assembly is workflow task |
| Assembly_Testing | Implements | Medium | Testing is workflow phase |
| FeatureTree_Architecture | Builds | Medium | Workflow builds feature tree |

#### bfb_bwain (TDD & Async Patterns)
**Test-driven development and async/concurrency patterns**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| FeatureDev_Workflow | References | Strong | TDD is core workflow approach |
| Assembly_Testing | References | Strong | TDD for assembly testing |
| EntityLifecycle_Management | Details | Strong | TDD for entity lifecycle |
| AsyncRaceConditions | Discusses | Strong | TDD for race condition handling |
| MainActor_Concurrency | Discusses | Strong | TDD for actor coordination |
| UUID store | References | Medium | TDD for async data storage |
| dec_prompts | References | Medium | December feature dev uses TDD |
| jan_prompts | References | Medium | January feature dev uses TDD |

#### dec_prompts (December Prompts)
**Feature development workflow and BFB agent patterns**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| FeatureDev_Workflow | Implements | Strong | Core workflow documentation |
| bfb_bwain | References | Strong | BFB agents and TDD |
| FeatureTree_Architecture | Defines | Strong | Feature tree patterns |
| Assembly_Workflow | Defines | Strong | Assembly patterns |
| Bwain_Architecture | References | Medium | Bwain reasoning patterns |
| DraftUpMvpSummary | Builds On | Medium | MVP foundation for features |

#### jan_prompts (January Prompts)
**GM-CDE integration and assembly testing**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| FeatureDev_Workflow | Implements | Strong | Workflow in GM-CDE context |
| Assembly_Testing | References | Strong | Assembly test patterns |
| MainActor_Concurrency | References | Medium | @globalActor coordination |
| dec_prompts | Complements | Medium | December workflow extended |
| bfb_bwain | References | Medium | TDD approach |

#### initial_project_prompts (Project Protocols)
**Acknowledgment protocol and architecture validation**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| FeatureDev_Workflow | Validates | Medium | Protocol validates architecture decisions |
| Bwain_Architecture | Uses | Medium | Protocol for agent communication |

### Concurrency & Threading Cluster

#### MainActor_Concurrency (Main Thread Coordination)
**MainActor usage and thread-safe coordination**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| AsyncRaceConditions | Solves | Strong | MainActor prevents races |
| GlobalActor_Patterns | Complements | Strong | Both actor-based coordination |
| UUID store | Protects | Strong | MainActor guards UUID access |
| EntityLifecycle_Management | Protects | Medium | MainActor coordinates state |
| bfb_bwain | References | Strong | TDD for actor patterns |
| jan_prompts | References | Medium | Actor patterns in workflow |

#### AsyncRaceConditions (Race Condition Solutions)
**Race condition handling and async solutions**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| MainActor_Concurrency | Solves | Strong | MainActor prevents races |
| GlobalActor_Patterns | Complements | Medium | Global coordination for races |
| UUID store | Challenges | Strong | UUID store has race conditions |
| bfb_bwain | References | Strong | TDD for race conditions |

#### GlobalActor_Patterns (Global State Coordination)
**@globalActor usage and global state management**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| MainActor_Concurrency | Complements | Strong | Both actor-based patterns |
| AsyncRaceConditions | Complements | Medium | Both address concurrency |
| jan_prompts | References | Medium | Actor patterns in workflow |

### Examples & References Cluster

#### DraftUpProject (Primary Example)
**Complete DraftUp project demonstrating all patterns**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| DraftUpMvpSummary | Exemplifies | Strong | Demonstrates MVP architecture |
| ParametricPrimitives_Design | Exemplifies | Strong | Project implements parametric design |
| EntityLifecycle_Management | Exemplifies | Strong | Project shows entity management |
| UUID store | Exemplifies | Strong | Project uses async UUID storage |
| Observable_StateManagement | Exemplifies | Strong | Project uses @Observable |
| SwiftData_Integration | Exemplifies | Strong | Project uses SwiftData |
| FeatureTree_Architecture | Exemplifies | Medium | Project demonstrates features |
| Assembly_Workflow | Exemplifies | Medium | Project shows assembly |
| ExpressionParser | Exemplifies | Medium | Project implements parser |
| CSG_MeshCaching_System | Exemplifies | Medium | Project uses mesh caching |
| IBL_Rendering | Exemplifies | Medium | Project implements IBL |

#### reference_build (Reference Implementation)
**Reference build showcasing Swift 6, VisionOS, and IBL**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| VisionOS_RealityKit | Exemplifies | Strong | VisionOS implementation |
| IBL_Rendering | Exemplifies | Strong | IBL implementation |
| Observable_StateManagement | Exemplifies | Strong | @Observable patterns |
| CameraSimulation | Exemplifies | Strong | Camera implementation |
| CSG_MeshCaching_System | Exemplifies | Medium | Mesh rendering |
| jan_prompts | References | Medium | Swift 6 patterns in workflow |

#### Bwain_Architecture (Agent Reasoning)
**Bot brain pattern for agent-based reasoning**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| dec_prompts | Uses | Medium | BFB agents use bwain pattern |
| initial_project_prompts | Uses | Medium | Acknowledgment protocol uses bwain |
| FeatureDev_Workflow | Uses | Medium | Workflow agent reasoning |

### Optimization Cluster

#### DirtyFlag_Optimization (Change Detection)
**Dirty flag optimization for selective updates**

| Connected To | Type | Strength | Reason |
|--------------|------|----------|--------|
| CSG_MeshCaching_System | Invalidates | Strong | Dirty flag invalidates cache |
| DraftUpMvpSummary | Implements | Strong | Core MVP optimization |
| EntityLifecycle_Management | Optimizes | Medium | Flags track entity changes |

## External KBite Relationships

### Outgoing Relationships (draftup_project → others)

| Target KBite | Type | Strength | Context |
|--------------|------|----------|---------|
| claude_customization | Uses | Strong | GM-CDE is development environment for DraftUp |
| *(Future)* swift_concurrency | References | Medium | Extended Swift async patterns beyond DraftUp |
| *(Future)* realitykit_reference | References | Medium | Extended RealityKit patterns beyond DraftUp |
| *(Future)* swiftui_patterns | References | Medium | Extended SwiftUI patterns beyond DraftUp |

### Incoming Relationships (others → draftup_project)

| Source KBite | Type | Strength | Context |
|--------------|------|----------|---------|
| claude_customization | Enables | Strong | GMCC framework enables DraftUp development |
| *(Future)* ForgeUp_project | Learns | Strong | ForgeUp learns from DraftUp patterns |
| *(Future)* BuildSystem_patterns | Complements | Medium | BuildSystem uses patterns from DraftUp |

## Relationship Strength Scoring

| Strength | Definition | Requires | Example |
|----------|-----------|----------|---------|
| **Strong** | Direct conceptual dependency; one cannot be fully understood without the other | Both resources in working context | ECS ↔ EntityLifecycle |
| **Medium** | Conceptual connection; each can be understood independently but benefit from cross-reference | Reference to complementary resource | Observable ↔ SwiftData |
| **Weak** | Distant connection; mention for completeness only | Optional to reference | reference_build ↔ Bwain |

## Navigation Strategies

### Deep Dive Paths (For Comprehensive Understanding)

**Path 1: Architecture Deep Dive**
```
1. DraftUpMvpSummary (foundations)
   ↓
2. TripleID_System + EntityLifecycle_Management (core patterns)
   ↓
3. FeatureTree_Architecture (composition)
   ↓
4. DraftUpProject (examples)
```

**Path 2: Rendering Deep Dive**
```
1. CSG_MeshCaching_System (mesh foundation)
   ↓
2. DirtyFlag_Optimization (performance)
   ↓
3. IBL_Rendering (lighting)
   ↓
4. CameraSimulation (preview)
   ↓
5. VisionOS_RealityKit (platform)
   ↓
6. reference_build (examples)
```

**Path 3: Parametric Design Deep Dive**
```
1. ParametricPrimitives_Design (system)
   ↓
2. ExpressionParser (evaluation)
   ↓
3. ConstraintSystem_Design (solving)
   ↓
4. DraftUpProject (examples)
```

**Path 4: Feature Development Deep Dive**
```
1. FeatureDev_Workflow (phases)
   ↓
2. dec_prompts + jan_prompts (patterns)
   ↓
3. bfb_bwain (TDD approach)
   ↓
4. Assembly_Workflow (assembly operations)
   ↓
5. Assembly_Testing (testing)
```

**Path 5: Concurrency Deep Dive**
```
1. MainActor_Concurrency (main thread)
   ↓
2. AsyncRaceConditions (problem solving)
   ↓
3. GlobalActor_Patterns (global coordination)
   ↓
4. UUID store (concrete example)
   ↓
5. bfb_bwain (TDD approach)
```

### Quick Reference Paths (For Specific Answers)

| Question | Path |
|----------|------|
| How is ECS implemented? | DraftUpMvpSummary → EntityLifecycle_Management |
| How does mesh caching work? | CSG_MeshCaching_System → DirtyFlag_Optimization |
| How do I implement parametric features? | ParametricPrimitives_Design → DraftUpProject |
| How do I avoid race conditions? | AsyncRaceConditions → MainActor_Concurrency |
| How do I test assemblies? | Assembly_Testing → bfb_bwain |
| What's the feature development workflow? | FeatureDev_Workflow → dec_prompts |
| How is the camera implemented? | CameraSimulation → reference_build |
| How do I set up Observable state? | Observable_StateManagement → DraftUpProject |

## Relationship Statistics

| Metric | Value |
|--------|-------|
| Total Internal Connections | 142 |
| Strong Connections | 89 |
| Medium Connections | 42 |
| Weak Connections | 11 |
| Hub Resources (5+ connections) | 8 |
| Leaf Resources (1-2 connections) | 4 |
| Average Connections per Resource | 5.3 |
| Most Connected Resource | DraftUpProject (13 connections) |
| Cluster Count | 8 |
| Avg Cluster Cohesion | 85% |

## Cluster Independence

| Cluster | Internal Connections | External Connections | Independence |
|---------|--------------------|--------------------|--------------|
| Architecture | 18 | 8 | 69% |
| Data & State | 8 | 6 | 57% |
| Parametric | 6 | 3 | 67% |
| Rendering | 11 | 4 | 73% |
| Assembly | 7 | 9 | 44% |
| Development | 22 | 5 | 81% |
| Concurrency | 6 | 4 | 60% |
| Examples | 15 | 2 | 88% |
