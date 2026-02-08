# KBite Purpose: draftup_project

## Why This KBite Exists

The draftup_project KBite consolidates comprehensive knowledge from the DraftUp MVP build into a persistent, indexed reference system. It enables the ForgeUp build to leverage architectural decisions, feature implementations, design patterns, and technical learnings from DraftUp without requiring manual context recovery. This KBite serves as the authoritative source for DraftUp's hybrid ECS patterns, CSG mesh optimization, parametric design, and assembly workflows.

## Scope

### In Scope
- **DraftUp MVP Architecture** - Hybrid ECS design, entity-component patterns, dirty flag optimization
- **Data Management** - Triple-ID system, UUID stores, SwiftData integration, state persistence
- **Rendering Systems** - CSG mesh caching, IBL (Image-Based Lighting), camera simulation, VisionOS/RealityKit integration
- **Parametric Design** - Expression parser, parametric primitives, feature trees, constraint systems
- **Feature Development Patterns** - Feature development workflow, TDD practices, entity lifecycle management
- **Assembly Systems** - Component assembly, rabbet/groove operations, feature combinations
- **Async & Concurrency** - Race condition handling, MainActor/Actor hybrid patterns, UUID async stores
- **UI/UX Implementation** - SwiftUI patterns, Observable integration, interactive design workflows
- **Development Practices** - BFB agents, bwains (bot brains), acknowledgment protocols, skeptical documentation
- **Testing Strategies** - Assembly tests, feature tests, entity lifecycle tests, TDD workflow

### Out of Scope
- Non-DraftUp projects or general iOS development
- Claude Code internals (covered by claude_customization kbite)
- Unrelated SwiftUI patterns (only DraftUp-specific patterns included)
- General parametric CAD theory (only DraftUp implementation details included)

## Target Use Cases

1. **ForgeUp Architecture Review** - Understanding DraftUp's design decisions to make informed architectural choices for ForgeUp
2. **Feature Port/Migration** - Replicating DraftUp features in ForgeUp with proper adaptation
3. **Pattern Reference** - Quick lookup of proven patterns (ECS, parametric design, async handling)
4. **Technical Debt Analysis** - Understanding what worked and what didn't in DraftUp
5. **New Feature Development** - Using DraftUp examples as templates for ForgeUp features
6. **Onboarding New Team Members** - Comprehensive reference for understanding the DraftUp ecosystem
7. **Cross-Build Learning** - Preventing duplicate work and leveraging prior art from DraftUp

## Related KBites

| KBite | Relationship |
|-------|--------------|
| `claude_customization` | Uses GMCC framework for development workflow; KBite system itself |
| *(Future)* `swift_concurrency` | Complementary reference for async/await patterns beyond DraftUp specifics |
| *(Future)* `realitykit_reference` | Complementary reference for RealityKit/VisionOS patterns beyond DraftUp |

## Success Criteria

- [x] Contains primary documentation from DraftUpMvpSummary
- [x] Contains example_project reference showing parametric design patterns
- [x] Contains dec_prompts and jan_prompts capturing feature development workflow
- [x] Contains reference_build documentation for Observable/VisionOS/IBL patterns
- [x] Contains bfb_bwain for TDD, async, and entity lifecycle patterns
- [x] Trigger words accurately identify when this kbite provides value (70%+ confidence)
- [x] Cross-references connect related knowledge domains efficiently
- [x] Complete coverage of all architectural patterns mentioned in chewed resources
- [x] Supports both rapid lookup and deep-dive research use cases
