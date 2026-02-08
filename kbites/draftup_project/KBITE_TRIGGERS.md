# KBite Triggers: draftup_project

When any of these concepts appear in a prompt or project context, GMB should check this kbite for relevant knowledge.

## Trigger Words

| Trigger | Confidence | Context | Resource |
|---------|------------|---------|----------|
| ECS | 98 | Hybrid Entity-Component System architecture patterns | DraftUpMvpSummary |
| entity lifecycle | 95 | Entity creation, updates, deletion, state transitions | bfb_bwain, dec_prompts |
| dirty flag | 95 | Optimization pattern for change detection | DraftUpMvpSummary |
| CSG mesh | 95 | Constructive Solid Geometry caching and rendering | DraftUpMvpSummary |
| triple-ID | 94 | UUID, componentID, entityID identification system | DraftUpMvpSummary |
| UUID store | 94 | Async storage pattern for entity identification | bfb_bwain, DraftUpProject |
| parametric design | 94 | Expression parser and parametric primitives | DraftUpProject |
| feature tree | 93 | Hierarchical feature composition and dependency | dec_prompts, DraftUpProject |
| assembly workflow | 93 | Component assembly, rabbet/groove operations | dec_prompts, jan_prompts |
| IBL | 92 | Image-Based Lighting rendering system | reference_build |
| Observable | 92 | SwiftUI state management pattern | reference_build, DraftUpProject |
| SwiftData | 91 | Persistent data storage and models | DraftUpProject |
| camera simulation | 91 | Simulated camera for rendering and UI | reference_build |
| VisionOS | 91 | Vision OS platform integration and RealityKit | reference_build |
| MainActor | 90 | Main thread synchronization in async context | bfb_bwain, jan_prompts |
| race condition | 88 | Async concurrency problems and solutions | bfb_bwain |
| TDD | 87 | Test-driven development workflow for DraftUp | bfb_bwain, dec_prompts |
| bwain | 87 | Bot brain pattern for agent reasoning | dec_prompts, jan_prompts |
| feature-dev | 87 | Feature development workflow and pattern | dec_prompts, jan_prompts |
| assembly test | 86 | Testing assembly operations and combinations | dec_prompts |
| expression parser | 85 | Parsing and evaluating parametric expressions | DraftUpProject |
| constraint system | 85 | Constraint-based design and solving | DraftUpProject |
| rabbet groove | 84 | Specific assembly pattern for component joining | dec_prompts |
| acknowledgment protocol | 82 | Communication and confirmation pattern | initial_project_prompts |
| SwiftUI pattern | 80 | DraftUp-specific UI implementation approaches | DraftUpProject, reference_build |
| mesh caching | 79 | CSG mesh performance optimization | DraftUpMvpSummary |
| BFB agent | 78 | Agent architecture (Behavioral Feature Building) | dec_prompts, bfb_bwain |
| GM-CDE workflow | 77 | Feature development within Green Mountain environment | jan_prompts |
| skeptical documentation | 76 | Documentation review and validation protocol | initial_project_prompts |
| async race | 75 | Async concurrency edge cases in UUID stores | bfb_bwain |

## Confidence Scoring

Confidence levels indicate the likelihood that this kbite should be consulted when the trigger appears:

- **98-95%**: Almost certain match - always consult when triggered
- **94-85%**: High confidence - consult unless context clearly diverges
- **84-75%**: Moderate-high confidence - consult if context is DraftUp-related
- **74-70%**: Moderate confidence - consult alongside other sources
- **Below 70%**: Low confidence - only consult if other context confirms relevance

## Anti-Triggers

Words that might seem related but should NOT activate this kbite (or should activate with low priority):

| Word | Reason |
|------|--------|
| SwiftUI | Too generic - matches all SwiftUI development (only trigger for DraftUp-specific patterns) |
| async/await | Too broad - Swift async patterns beyond DraftUp scope (only trigger for entity lifecycle or UUID store contexts) |
| iOS | Too generic - general iOS development, not DraftUp-specific |
| animation | General SwiftUI animation, not DraftUp parametric patterns |
| networking | General app development pattern, not DraftUp-specific |
| database | General data persistence, not DraftUp SwiftData patterns |
| API | General API usage, not DraftUp MVP-specific |
| performance | Generic optimization, trigger only with mesh/CSG/cache context |
| architecture | Too broad - trigger only with ECS or feature-tree context |
| testing | Generic testing patterns, trigger only with assembly-test or TDD context |

## Contextual Trigger Combinations

High-confidence combinations that should always trigger the kbite:

| Combination | Confidence | Rationale |
|-------------|------------|-----------|
| "entity" + "component" + "system" | 99 | ECS architecture core |
| "parametric" + "expression" + "design" | 98 | Parametric design system |
| "UUID" + "async" + "storage" | 97 | UUID store pattern |
| "CSG" + "mesh" + "cache" | 96 | Mesh rendering system |
| "assembly" + "rabbet" or "groove" | 95 | Specific assembly pattern |
| "feature" + "tree" + "hierarchy" | 94 | Feature tree structure |
| "MainActor" + "Actor" + "hybrid" | 93 | Concurrency pattern |
| "dirty" + "flag" + "optimization" | 92 | Change detection pattern |
| "IBL" + "VisionOS" or "RealityKit" | 91 | Rendering system context |
| "Observable" + "SwiftUI" + "state" | 88 | State management pattern |

## Trigger Extension Rules

These rules allow broader contextual matching:

1. **Any architectural pattern discussion** + DraftUp project context → Check this kbite
2. **Any async/concurrency issue** + DraftUp entity/component context → Check this kbite
3. **Any UI implementation** + "parametric" or "expression" → Check this kbite
4. **Any rendering or visual** + "CSG" or "mesh" or "IBL" → Check this kbite
5. **Any assembly or component joining** + DraftUp context → Check this kbite
6. **Feature development workflow** + any phase → Check this kbite
