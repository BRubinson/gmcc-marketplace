# KBite Trigger Map: draftup_project

Quick lookup from trigger word to relevant resources. **Use this as the primary navigation tool for rapid knowledge retrieval.**

## High-Confidence Primary Triggers (98-94%)

| Trigger | Best Resource | Alternative Resources | Path | Relevance | Use When |
|---------|---------------|----------------------|------|-----------|----------|
| ECS | DraftUpMvpSummary | FeatureTree_Architecture, EntityLifecycle_Management | primary/documentation/DraftUpMvpSummary | 100 | Discussing entity-component architecture |
| entity lifecycle | EntityLifecycle_Management | bfb_bwain, dec_prompts | primary/documentation/EntityLifecycle_Management | 95 | Managing entity states and transitions |
| dirty flag | DirtyFlag_Optimization | DraftUpMvpSummary | primary/documentation/DirtyFlag_Optimization | 92 | Optimizing change detection |
| CSG mesh | CSG_MeshCaching_System | DraftUpMvpSummary, IBL_Rendering | primary/documentation/CSG_MeshCaching_System | 90 | Working with CSG rendering |
| triple-ID | TripleID_System | DraftUpMvpSummary | primary/documentation/TripleID_System | 89 | Entity identification patterns |
| UUID store | DraftUpProject | bfb_bwain, AsyncRaceConditions | primary/example_project/DraftUpProject | 88 | Async entity storage |
| parametric design | ParametricPrimitives_Design | ExpressionParser, DraftUpProject, ConstraintSystem_Design | primary/documentation/ParametricPrimitives_Design | 87 | Parametric feature implementation |
| feature tree | FeatureTree_Architecture | dec_prompts, FeatureDev_Workflow | primary/documentation/FeatureTree_Architecture | 86 | Feature hierarchy and composition |
| assembly workflow | Assembly_Workflow | Assembly_Testing, dec_prompts, jan_prompts | primary/documentation/Assembly_Workflow | 85 | Component assembly operations |

## High-Confidence Secondary Triggers (93-88%)

| Trigger | Best Resource | Alternative Resources | Path | Relevance | Use When |
|---------|---------------|----------------------|------|-----------|----------|
| IBL | IBL_Rendering | reference_build, VisionOS_RealityKit | primary/documentation/IBL_Rendering | 84 | Image-based lighting implementation |
| Observable | Observable_StateManagement | reference_build, DraftUpProject | primary/documentation/Observable_StateManagement | 83 | @Observable state management |
| SwiftData | SwiftData_Integration | DraftUpProject | primary/documentation/SwiftData_Integration | 82 | Data persistence and models |
| camera simulation | CameraSimulation | reference_build, IBL_Rendering | primary/documentation/CameraSimulation | 81 | Camera viewport and rendering |
| VisionOS | VisionOS_RealityKit | reference_build, IBL_Rendering | primary/documentation/VisionOS_RealityKit | 80 | VisionOS platform integration |
| MainActor | MainActor_Concurrency | bfb_bwain, jan_prompts | primary/documentation/MainActor_Concurrency | 79 | Actor-based concurrency |
| race condition | AsyncRaceConditions | bfb_bwain, MainActor_Concurrency | primary/documentation/AsyncRaceConditions | 78 | Race condition solutions |
| feature-dev | FeatureDev_Workflow | dec_prompts, jan_prompts, bfb_bwain | primary/all_others/FeatureDev_Workflow | 77 | Feature development workflow |
| expression parser | ExpressionParser | ParametricPrimitives_Design, DraftUpProject | primary/documentation/ExpressionParser | 76 | Expression parsing and evaluation |

## Moderate-High Confidence Triggers (87-82%)

| Trigger | Best Resource | Path | Relevance | Context |
|---------|---------------|----|-----------|---------|
| assembly test | Assembly_Testing | primary/documentation/Assembly_Testing | 74 | Testing assembly operations |
| constraint system | ConstraintSystem_Design | primary/documentation/ConstraintSystem_Design | 73 | Parametric constraint solving |
| rabbet groove | Assembly_Workflow | primary/documentation/Assembly_Workflow | 71 | Specific assembly pattern |
| acknowledgment protocol | initial_project_prompts | primary/all_others/initial_project_prompts | 70 | Architecture validation pattern |
| bwain | Bwain_Architecture | primary/all_others/Bwain_Architecture | 76 | Bot brain reasoning pattern |
| global actor | GlobalActor_Patterns | primary/documentation/GlobalActor_Patterns | 75 | Global state coordination |
| Swift 6 | reference_build | primary/documentation/reference_build | 97 | Swift 6 specific features |
| RealityKit | VisionOS_RealityKit | primary/documentation/VisionOS_RealityKit | 80 | 3D rendering framework |
| mesh caching | CSG_MeshCaching_System | primary/documentation/CSG_MeshCaching_System | 91 | Mesh performance optimization |
| BFB agent | dec_prompts | primary/all_others/dec_prompts | 96 | Behavioral Feature Building agents |

## Moderate Confidence Triggers (81-70%)

| Trigger | Best Resource | Alternative | Relevance | Note |
|---------|---------------|-------------|-----------|------|
| TDD | bfb_bwain | Assembly_Testing, FeatureDev_Workflow | 77 | Test-driven development approach |
| SwiftUI pattern | DraftUpProject | reference_build, Observable_StateManagement | 70 | DraftUp-specific UI patterns only |
| change detection | DirtyFlag_Optimization | DraftUpMvpSummary | 92 | Related to dirty flag optimization |
| component joining | Assembly_Workflow | FeatureTree_Architecture | 85 | Assembly-specific pattern |
| state transitions | EntityLifecycle_Management | bfb_bwain | 95 | Entity state management |
| concurrent access | AsyncRaceConditions | MainActor_Concurrency | 78 | UUID store concurrent patterns |
| performance optimization | CSG_MeshCaching_System | DirtyFlag_Optimization | 90 | Mesh-specific optimization |
| rendering pipeline | IBL_Rendering | CSG_MeshCaching_System, reference_build | 84 | Visual rendering system |
| property observation | Observable_StateManagement | reference_build | 83 | @Observable integration |
| workflow phases | FeatureDev_Workflow | dec_prompts, jan_prompts, bfb_bwain | 75 | Feature development phases |

## Cross-Reference Clusters

These trigger combinations indicate strong inter-resource connections:

### Cluster 1: Parametric & Expression Systems
```
[parametric design] → ParametricPrimitives_Design → ExpressionParser → ConstraintSystem_Design
                                               ↓
                                    DraftUpProject (example)
```
**Triggers**: parametric design, expression parser, constraint system
**Best Path**: ParametricPrimitives_Design → ExpressionParser for parsing → ConstraintSystem_Design for solving

### Cluster 2: Entity & Component Systems
```
[ECS] → DraftUpMvpSummary → EntityLifecycle_Management → FeatureTree_Architecture
                  ↓              ↓                             ↓
           TripleID_System  bfb_bwain                  Assembly_Workflow
```
**Triggers**: ECS, entity lifecycle, feature tree, assembly
**Best Path**: DraftUpMvpSummary → EntityLifecycle_Management → FeatureTree_Architecture

### Cluster 3: Rendering & Visualization
```
[CSG mesh] → CSG_MeshCaching_System → IBL_Rendering → CameraSimulation
                                         ↓
                                  VisionOS_RealityKit
                                         ↓
                                   reference_build
```
**Triggers**: CSG mesh, IBL, camera simulation, VisionOS, RealityKit
**Best Path**: CSG_MeshCaching_System → IBL_Rendering → reference_build (for examples)

### Cluster 4: Concurrency & State
```
[MainActor] → MainActor_Concurrency → AsyncRaceConditions → UUID store
                    ↓                                          ↓
           GlobalActor_Patterns                        DraftUpProject
                    ↓
                bfb_bwain
```
**Triggers**: MainActor, race condition, UUID store, async
**Best Path**: MainActor_Concurrency → AsyncRaceConditions → DraftUpProject

### Cluster 5: Development Workflow
```
[feature-dev] → FeatureDev_Workflow → dec_prompts / jan_prompts → bfb_bwain
                                           ↓
                                   Assembly_Testing
                                           ↓
                                    acknowledgment protocol
```
**Triggers**: feature-dev, TDD, assembly test, acknowledgment protocol
**Best Path**: FeatureDev_Workflow → dec_prompts/jan_prompts → Assembly_Testing

## Confidence Breakdown by Topic

### Architecture (Avg Confidence: 94%)
- ECS: 100%
- TripleID: 88%
- Entity Lifecycle: 95%
- Feature Tree: 89%
- Dirty Flag: 92%

### Rendering (Avg Confidence: 86%)
- CSG Mesh: 90%
- IBL: 84%
- Camera Simulation: 81%
- VisionOS: 80%

### Parametric Design (Avg Confidence: 85%)
- Parametric Design: 87%
- Expression Parser: 76%
- Constraint System: 73%

### Data & State (Avg Confidence: 84%)
- UUID Store: 88%
- SwiftData: 82%
- Observable: 83%

### Concurrency (Avg Confidence: 80%)
- MainActor: 79%
- Race Condition: 78%
- GlobalActor: 75%

### Development (Avg Confidence: 77%)
- Feature Development: 77%
- Assembly Testing: 74%
- TDD: 77%

## Trigger-to-Resource Mapping (Alphabetical)

| Trigger | Primary | Secondary | Tertiary |
|---------|---------|-----------|----------|
| acknowledgment protocol | initial_project_prompts | FeatureDev_Workflow | - |
| assembly test | Assembly_Testing | bfb_bwain, jan_prompts | - |
| assembly workflow | Assembly_Workflow | Assembly_Testing, dec_prompts | FeatureTree_Architecture |
| async race | AsyncRaceConditions | MainActor_Concurrency, bfb_bwain | UUID store |
| BFB agent | dec_prompts | bfb_bwain | - |
| bwain | Bwain_Architecture | dec_prompts, jan_prompts | - |
| camera simulation | CameraSimulation | reference_build, IBL_Rendering | - |
| change detection | DirtyFlag_Optimization | DraftUpMvpSummary | - |
| component joining | Assembly_Workflow | FeatureTree_Architecture | - |
| concurrent access | AsyncRaceConditions | MainActor_Concurrency | - |
| constraint system | ConstraintSystem_Design | ParametricPrimitives_Design | ExpressionParser |
| CSG mesh | CSG_MeshCaching_System | DraftUpMvpSummary, IBL_Rendering | - |
| dirty flag | DirtyFlag_Optimization | DraftUpMvpSummary | - |
| ECS | DraftUpMvpSummary | FeatureTree_Architecture, EntityLifecycle_Management | - |
| entity lifecycle | EntityLifecycle_Management | bfb_bwain, dec_prompts | - |
| expression parser | ExpressionParser | ParametricPrimitives_Design, DraftUpProject | - |
| feature-dev | FeatureDev_Workflow | dec_prompts, jan_prompts, bfb_bwain | - |
| feature tree | FeatureTree_Architecture | dec_prompts, FeatureDev_Workflow | Assembly_Workflow |
| global actor | GlobalActor_Patterns | MainActor_Concurrency | bfb_bwain |
| IBL | IBL_Rendering | reference_build, VisionOS_RealityKit | CSG_MeshCaching_System |
| MainActor | MainActor_Concurrency | bfb_bwain, jan_prompts | GlobalActor_Patterns |
| mesh caching | CSG_MeshCaching_System | DraftUpMvpSummary | IBL_Rendering |
| Observable | Observable_StateManagement | reference_build, DraftUpProject | - |
| parametric design | ParametricPrimitives_Design | ExpressionParser, DraftUpProject, ConstraintSystem_Design | - |
| performance optimization | CSG_MeshCaching_System | DirtyFlag_Optimization | IBL_Rendering |
| property observation | Observable_StateManagement | reference_build | - |
| rabbet groove | Assembly_Workflow | dec_prompts | - |
| race condition | AsyncRaceConditions | bfb_bwain, MainActor_Concurrency | - |
| RealityKit | VisionOS_RealityKit | reference_build, IBL_Rendering | - |
| rendering pipeline | IBL_Rendering | CSG_MeshCaching_System, reference_build | - |
| state transitions | EntityLifecycle_Management | bfb_bwain | FeatureTree_Architecture |
| Swift 6 | reference_build | jan_prompts | - |
| SwiftData | SwiftData_Integration | DraftUpProject | - |
| SwiftUI pattern | DraftUpProject | reference_build, Observable_StateManagement | - |
| TDD | bfb_bwain | Assembly_Testing, FeatureDev_Workflow | - |
| triple-ID | TripleID_System | DraftUpMvpSummary | - |
| UUID store | DraftUpProject | bfb_bwain, AsyncRaceConditions | - |
| VisionOS | VisionOS_RealityKit | reference_build, IBL_Rendering | - |
| workflow phases | FeatureDev_Workflow | dec_prompts, jan_prompts, bfb_bwain | - |

## Rapid Access Patterns

### By Development Phase
- **Planning**: FeatureDev_Workflow → FeatureTree_Architecture
- **Design**: ParametricPrimitives_Design → ConstraintSystem_Design
- **Implementation**: DraftUpProject (examples) → specific pattern documentation
- **Testing**: Assembly_Testing → bfb_bwain (TDD)
- **Optimization**: CSG_MeshCaching_System → DirtyFlag_Optimization

### By Problem Type
- **Architecture Issues**: DraftUpMvpSummary → EntityLifecycle_Management
- **Performance Issues**: CSG_MeshCaching_System → DirtyFlag_Optimization
- **Concurrency Issues**: AsyncRaceConditions → MainActor_Concurrency
- **UI/State Issues**: Observable_StateManagement → reference_build
- **Rendering Issues**: IBL_Rendering → VisionOS_RealityKit
- **Assembly Issues**: Assembly_Workflow → Assembly_Testing

### By Technology Stack
- **SwiftUI**: Observable_StateManagement → reference_build → DraftUpProject
- **SwiftData**: SwiftData_Integration → DraftUpProject
- **RealityKit/VisionOS**: VisionOS_RealityKit → reference_build → IBL_Rendering
- **Parametric**: ParametricPrimitives_Design → ExpressionParser → DraftUpProject
- **Async/Actors**: MainActor_Concurrency → AsyncRaceConditions → bfb_bwain
