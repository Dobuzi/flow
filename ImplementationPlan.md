# Flow iOS Implementation Plan

This plan treats [`Design.md`](/Users/jw/Dev/codex/flow/Design.md) as the canonical architecture source and keeps all implementation decisions aligned with it.

## 1. Architecture Validation (Design.md Review)

`Design.md` is strong at product and high-level architecture, but these implementation-critical details should be clarified before coding starts in earnest:

1. Data source contract and units
- Define exact volume semantics (`passengers/day`, `tons/hour`, mixed or separate datasets).
- Define required vs optional metadata fields in `FlowRecord.metadata`.

2. Time bucket normalization
- Confirm canonical granularity set (`year`, `month`, `hourRange`) and timezone handling policy.
- Define valid hour range representation (`0-23`, half-open intervals, local vs UTC).

3. Spatial level definitions
- Define exact mapping of `spatialLevel` values and region code standards (national/province/city/hub).
- Define aggregation keys for zoom transitions.

4. Visualization thresholds
- Define line-width scaling function, opacity scaling, and minimum visibility threshold.
- Define deterministic color tokens for transport modes and accessibility contrast requirements.

5. Performance budgets
- Set target budgets (example: map interaction <16ms/frame, filter response <200ms for common queries).
- Define max in-memory dataset size and cache eviction policy.

6. Selection behavior
- Clarify tap priority when overlapping flows exist.
- Define selection persistence behavior when filters/time change.

## 2. Architecture Notes for Implementation

- Keep **MVVM + unidirectional data flow** exactly as specified.
- Centralize shared state in `AppState` and expose derived state via view models.
- Keep map rendering concerns isolated in a dedicated `FlowMapRenderer` module.
- Implement filtering and time slicing as separate domain services (`FilteringEngine`, `TimeSeriesEngine`) with pure, testable APIs.
- Use pre-aggregated data pathways early to avoid rework when dataset scale increases.

## 3. Development Roadmap

## Phase A: Foundation
1. Create Xcode project scaffold (SwiftUI App lifecycle, tabs, placeholder screens).
2. Establish module/folder structure and shared conventions.
3. Implement base `AppState` + state actions/events.
4. Add logging, error surface patterns, and feature flags for visualization experiments.

Verification:
- App launches with tab structure and empty map shell.
- State changes propagate through view models.

## Phase B: Data and Domain Core
1. Implement core models: `FlowRecord`, `LocationNode`, `TransportMode`, `TimeBucket`, `FlowDataset`.
2. Define repository protocols and initial local JSON-backed repository.
3. Build `FilteringEngine` (mode + geographic + threshold filtering).
4. Build `TimeSeriesEngine` (bucket selection, playback stepping, interpolation policy if needed).
5. Add unit tests for data parsing, filtering correctness, and time stepping.

Verification:
- Deterministic filtering/time outputs for fixture datasets.
- Test coverage for edge cases (empty buckets, missing metadata, multi-mode select).

## Phase C: Map Rendering
1. Build `MapContainerView` + MapKit bridge abstraction.
2. Implement `FlowMapRenderer` that transforms domain records into `RenderableFlowSegment`.
3. Add static flow lines with style mapping by mode and volume.
4. Add zoom-aware LOD switching and viewport-based rendering subset.
5. Add selection handling and basic `FlowDetailCard`.

Verification:
- Correct rendering across national/regional/city zoom levels.
- Selection opens correct flow detail for tapped segment.

## Phase D: Time and Mode Interaction UX
1. Implement `TimeControlSheet` (year/month/hour + playback).
2. Wire time control events to `AppState` and map updates.
3. Implement `ModeFilterSheet` multi-select toggles + reset behavior.
4. Add legend and visual consistency checks.

Verification:
- Map updates correctly on time and mode changes.
- Playback produces stable, throttled updates without UI stutter.

## Phase E: Insights and Settings
1. Implement `InsightsView` with top corridors, mode share, and time distribution.
2. Implement `SettingsView` dataset/version selector and cache controls.
3. Add persisted user preferences (visual style, last-used filters/time scope).

Verification:
- Insights reflect current filter/time scope exactly.
- Settings changes persist and rehydrate correctly.

## Phase F: Performance and Hardening
1. Add pre-aggregation indexes (`timeBucket x mode x spatialLevel`).
2. Implement in-memory + disk caching with eviction policy.
3. Add incremental/diff-based map overlay updates.
4. Profile and optimize animation + filtering pipeline.
5. Add instrumentation and regression tests for large fixtures.

Verification:
- Meets agreed response/frame budgets on target devices.
- No major regressions under high-record-count datasets.

## 4. Milestone Breakdown

## Milestone 1: Project Skeleton
Scope:
- SwiftUI app shell, tabs, placeholder screens, `AppState` scaffold.
Exit criteria:
- Navigation skeleton works; state container is wired.

## Milestone 2: Data Layer
Scope:
- Core models, repository protocols, local dataset loading, fixtures.
Exit criteria:
- Dataset loads and basic query APIs pass tests.

## Milestone 3: Map Rendering
Scope:
- MapKit integration, flow line rendering, LOD basics, selection.
Exit criteria:
- Rendered flows visible and selectable at multiple zoom levels.

## Milestone 4: Time Filtering
Scope:
- Time controls + `TimeSeriesEngine` integration + playback loop.
Exit criteria:
- Time changes and playback update map deterministically.

## Milestone 5: Transport Filtering
Scope:
- Multi-mode filtering + legend + reset/select-all actions.
Exit criteria:
- Mode filters correctly alter rendered set and analytics scope.

## Milestone 6: UI/UX Polishing and Performance
Scope:
- Insights/settings completion, animation polish, caching, profiling.
Exit criteria:
- Smooth interaction on realistic dataset size and UX parity with design.

## 5. Proposed Repository Structure

```text
Flow/
  App/
    FlowApp.swift
    RootTabView.swift
    AppState/
      AppState.swift
      AppAction.swift
      AppStore.swift
  Core/
    Constants/
    Extensions/
    Utilities/
    Logging/
  Domain/
    Models/
      FlowRecord.swift
      LocationNode.swift
      TransportMode.swift
      TimeBucket.swift
      FlowDataset.swift
      RenderableFlowSegment.swift
    Engines/
      FilteringEngine.swift
      TimeSeriesEngine.swift
    UseCases/
      BuildRenderableFlowsUseCase.swift
      ComputeInsightsUseCase.swift
  Data/
    Repositories/
      FlowRepository.swift
      LocationRepository.swift
    Sources/
      LocalJSONDataSource.swift
      CacheDataSource.swift
    DTOs/
    Mappers/
  Visualization/
    Map/
      MapContainerView.swift
      FlowMapRenderer.swift
      OverlayFactory.swift
      LODPolicy.swift
    Styling/
      ModeColorPalette.swift
      FlowScalePolicy.swift
  Features/
    MapDashboard/
      MapDashboardView.swift
      MapDashboardViewModel.swift
      Components/
        FlowLegendView.swift
        QuickControlBar.swift
        FlowDetailCard.swift
    TimeControls/
      TimeControlSheet.swift
      TimeControlViewModel.swift
    ModeFilter/
      ModeFilterSheet.swift
      ModeFilterViewModel.swift
    Insights/
      InsightsView.swift
      InsightsViewModel.swift
      Components/
    Settings/
      SettingsView.swift
      SettingsViewModel.swift
  Resources/
    SampleData/
    Assets.xcassets
    Localizable.strings
  Tests/
    Unit/
      Domain/
      Data/
      ViewModels/
    Integration/
      MapRendering/
      FilteringAndTime/
```

## 6. Exact Implementation Sequence

1. Scaffold app and folder/module layout.
2. Implement `AppState` and root navigation shell.
3. Implement domain models and JSON decoding.
4. Implement repository interfaces and local data source.
5. Implement `FilteringEngine` and tests.
6. Implement `TimeSeriesEngine` and playback stepping tests.
7. Implement MapKit container and renderer pipeline (static first).
8. Implement zoom-aware LOD + viewport filtering.
9. Implement flow selection and detail card.
10. Implement Time Control panel and wire to state.
11. Implement Transport Mode Filter panel and legend.
12. Implement Insights panel calculations + charts.
13. Implement Settings/Data Catalog behaviors.
14. Add caching, diff updates, and performance profiling.
15. Final UX polish, accessibility pass, and regression tests.

## 7. Risk Areas and Mitigations

| Risk Area | Why It Is Hard | Mitigation |
|---|---|---|
| Large dataset rendering | Too many overlays can degrade frame rate | LOD + viewport culling + pre-aggregation + overlay diffing |
| Animated flow lines on MapKit | Native MapKit overlay animation is limited | Keep animation layer decoupled; start with lightweight dash/particle strategy; throttle updates |
| Real-time filter responsiveness | Frequent recompute from sliders/playback | Background compute + debouncing + cached query slices |
| Zoom transition consistency | Aggregation changes can cause visual jumps | Deterministic aggregation thresholds and transition smoothing |
| Multi-source data quality | Missing metadata/time gaps can break UX | Validation pipeline + fallback defaults + strict schema checks |

## 8. Definition of Done (Planning Stage)

- `ImplementationPlan.md` accepted as build roadmap.
- Clarification items from Section 1 resolved (in `Design.md` addendum or explicit decision log) before heavy implementation milestones.
- Team agrees on milestone exit criteria and performance budgets.

## 9. Real-Data Integration Update (2026-03-07)

### 9.1 Clarification Status
The ambiguity items in Section 1 are now resolved for first production-style external ingestion through `Design.md` Section 12 addendum:
- dataset source contract and snapshot packaging
- mode normalization policy to app categories
- canonical hourly bucket format and timezone policy
- source-switching behavior in app state
- compatibility requirements across map/filter/time/insights

### 9.2 Completed Scope
- Added Seoul/Capital snapshot provider path (`DTO -> Mapper -> DataSource -> Repository`).
- Added source-agnostic repository factory and runtime source switching (`bundledSample` vs `seoulCapitalSnapshot`).
- Wired Map and Insights reload behavior on source changes.
- Added tests for mode mapping, snapshot loading, and source-switch load path.

### 9.3 Next Roadmap Item
Add a new milestone after current hardening work:
- **Milestone 7: Live External Refresh**
  - API client and sync orchestration for Seoul source
  - schema drift detection and fallback policy
  - snapshot refresh workflow and integrity checks
