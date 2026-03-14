# Flow iOS Development Tasks

## 1. Overview
This document converts the approved architecture and roadmap into an execution-ready task backlog for the Flow iOS app.

All implementation must remain aligned with:
- [Design.md](/Users/jw/Dev/codex/flow/Design.md)
- [ImplementationPlan.md](/Users/jw/Dev/codex/flow/ImplementationPlan.md)

If architecture-impacting changes are needed, update `Design.md` first (per Section 12.7), then implement.

## 2. Development Principles
- Follow MVVM + unidirectional data flow with `AppState` as the shared source of UI state.
- Keep domain logic (`FilteringEngine`, `TimeSeriesEngine`) pure and independently testable.
- Keep map rendering logic isolated in `FlowMapRenderer` and map bridge components.
- Deliver incrementally with testable slices; avoid large unverified merges.
- Prefer small, composable tasks with clear dependencies and measurable DoD.
- Defer heavy optimization until performance-risk tasks are reached, except where design mandates hard budgets.
- Maintain strict schema and validation behavior from `Design.md` Section 12.

## 3. Milestone-to-Task Mapping

## Milestone 1: Project Skeleton

## Task T-001 — Initialize Xcode app shell and root tabs
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Create SwiftUI app entry, `RootTabView`, and placeholder tabs for Map, Insights, Settings.
- Deliverable: Launchable iOS app with tab navigation shell.
- Definition of Done: App launches on simulator, all three tabs are reachable, no runtime crashes.

## Task T-002 — Create repository folder structure and target groups
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-001
- Complexity: Small
- Description: Establish project directories/groups consistent with ImplementationPlan structure (`App`, `Core`, `Domain`, `Data`, `Visualization`, `Features`, `Resources`, `Tests`).
- Deliverable: Organized project tree and target membership configuration.
- Definition of Done: All top-level modules exist and compile with empty stubs.

## Task T-003 — Implement AppState, AppAction, and AppStore scaffolding
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-001
- Complexity: Medium
- Description: Implement state container for selected time bucket, mode set, map region/spatial level, playback state, and selection state.
- Deliverable: `AppState` scaffolding wired to root views.
- Definition of Done: State updates propagate to subscribed view models via deterministic action flow.

## Task T-004 — Add baseline logging and error surface strategy
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-003
- Complexity: Small
- Description: Add lightweight logging utilities and error reporting contract for data-load/filter/render failures.
- Deliverable: Logging helper and consistent non-fatal error presentation pattern.
- Definition of Done: Core layers can emit structured logs and UI can display a non-blocking error state.
- Notes: Added structured logger levels/metadata in `FlowLogger`, standardized `FlowNonFatalError` contract by scope, and introduced shared `NonBlockingErrorBanner` used across Map/Insights/Settings for non-fatal UI error surfacing.

## Milestone 2: Data Layer

## Task T-005 — Implement core domain models and enums
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-002
- Complexity: Medium
- Description: Implement `FlowRecord`, `LocationNode`, `TransportMode`, `TimeBucket`, `FlowDataset`, and `RenderableFlowSegment` per Design Section 8 and 12.
- Deliverable: Strongly typed model layer with Codable support where applicable.
- Definition of Done: Models compile and match required/optional field constraints from `Design.md`.

## Task T-006 — Implement dataset manifest and schema version validation
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-005
- Complexity: Medium
- Description: Validate `dataset_manifest.json` and enforce `schemaVersion == 1.0.0` for initial support.
- Deliverable: Manifest parser + validation errors for unsupported schema.
- Definition of Done: Invalid schema versions fail fast with explicit error output.

## Task T-007 — Implement local JSON/JSONL data source loaders
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-006
- Complexity: Medium
- Description: Add loaders for `nodes.json` and `flows.jsonl`, including streaming-friendly parsing for large files.
- Deliverable: `LocalJSONDataSource` returning typed model collections.
- Definition of Done: Sample dataset loads correctly from `Resources/SampleData`.

## Task T-008 — Implement FlowRecord validation pipeline
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-007
- Complexity: Medium
- Description: Apply record drop rules (`origin==destination`, missing nodes, negative volume) and keep optional metadata nullable.
- Deliverable: Validation stage integrated into ingest pipeline with dropped-record metrics.
- Definition of Done: Invalid records are excluded exactly per Design Section 12.1.

## Task T-009 — Implement repository protocols and concrete repositories
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-007
- Complexity: Medium
- Description: Create `FlowRepository` and `LocationRepository` contracts and local implementations.
- Deliverable: Repository APIs used by domain/use case layers.
- Definition of Done: ViewModels can request dataset, nodes, and scoped records through repositories only.

## Task T-010 — Add data-layer unit tests and fixtures
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-008, T-009
- Complexity: Medium
- Description: Add test fixtures for valid/invalid data and verify parser + validation behavior.
- Deliverable: Unit test suite for data source and repository layer.
- Definition of Done: All critical ingestion/validation tests pass in CI/local.
- Notes: Added executable unit-test runner with mock fixtures to validate schema version checks and repository validation/drop rules (`Flow/Tests/Unit/run_data_layer_tests.sh`).

## Milestone 3: Map Rendering

## Task T-011 — Build MapKit bridge container view
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-003
- Complexity: Medium
- Description: Create `MapContainerView` bridging SwiftUI with MapKit and exposing region/zoom callbacks.
- Deliverable: Map component with state bindings for camera changes.
- Definition of Done: Camera changes update store state and map renders base layer reliably.

## Task T-012 — Implement spatial level and zoom mapping policy
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-011
- Complexity: Small
- Description: Encode latitudeDelta thresholds for `national/province/city/hub` transitions per Design Section 12.3.
- Deliverable: `LODPolicy` utility returning active spatial level from current map view.
- Definition of Done: Unit tests pass for boundary conditions of each zoom bucket.

## Task T-013 — Implement FlowMapRenderer static overlay pipeline
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-005, T-009, T-011
- Complexity: Large
- Description: Convert filtered records to `RenderableFlowSegment` and draw static OD overlays with mode-specific style tokens.
- Deliverable: First end-to-end flow line rendering on map.
- Definition of Done: Flow lines render with correct color/line pattern and no rendering errors.
- Notes: Added `FlowMapRenderer`, `FlowPolyline`, MapKit overlay sync/rendering path, and MapDashboard wiring from repositories -> renderable segments -> map overlays.

## Task T-014 — Implement volume scaling and visibility thresholds
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-013
- Complexity: Medium
- Description: Apply percentile-based width/opacity scaling (`p10/p50/p90`) and visibility threshold rules, preserving top-150 override.
- Deliverable: `FlowScalePolicy` integrated into renderer.
- Definition of Done: Render outputs match all scaling and threshold rules in Design Section 12.4.
- Notes: Added `FlowScalePolicy` with percentile interpolation, opacity mapping, normalized-intensity threshold (`<0.03`) plus top-150 override, and wired renderer to use per-segment width/opacity.

## Task T-015 — Implement overlay hit-testing and selection resolution
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-013, T-003
- Complexity: Large
- Description: Add 24pt hit radius selection and overlap resolution priority (`volume`, distance, `id`) with selection persistence/clear rules.
- Deliverable: Reliable tap-to-select behavior with `FlowDetailCard` trigger state.
- Definition of Done: Interaction test cases pass for overlap and invalidation scenarios.
- Notes: Added map tap hit-testing against rendered polylines, deterministic tie-break order (`volume desc`, `distance asc`, `id asc`), invalid-selection clearing on segment set updates, and basic `FlowDetailCard` trigger/clear wiring via `AppStore.selectedFlowID`.

## Task T-016 — Add map rendering integration tests
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-014, T-015
- Complexity: Medium
- Description: Validate map render contract (segment limits, style mapping, threshold behavior, selection behavior).
- Deliverable: Integration test suite for map rendering and interaction.
- Definition of Done: Tests verify renderer output consistency for fixed fixtures.
- Notes: Added `FlowTests/MapRenderingIntegrationTests.swift` (Swift Testing) covering threshold + top-150 override, spatial-level segment caps with top-volume retention, and selection detail invalidation after mode filtering; verified via `xcodebuild ... -only-testing:FlowTests test` on simulator.

## Milestone 4: Time Filtering

## Task T-017 — Implement TimeSeriesEngine for bucket selection and stepping
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-005, T-009
- Complexity: Medium
- Description: Implement canonical time bucket parsing (`Y`, `M`, `H`) and hour-step playback logic with missing-bucket zero behavior.
- Deliverable: Pure `TimeSeriesEngine` with deterministic APIs.
- Definition of Done: Engine tests pass for year/month/hour selection and playback stepping.
- Notes: Added pure `TimeSeriesEngine` with canonical bucket parsing/formatting, 1-hour playback stepping (`23 -> 00`), bucket filtering, and zero-filled volume aggregation; added executable unit tests via `run_time_series_tests.sh`.

## Task T-018 — Build TimeControlSheet UI and ViewModel
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-003, T-017
- Complexity: Medium
- Description: Implement year selector, month selector, hour slider, and playback controls.
- Deliverable: Time controls fully wired to `AppState`.
- Definition of Done: User input changes selected time and playback state in store.
- Notes: Added `TimeControlSheet` + `TimeControlViewModel` under `Features/TimeControls` and wired a map-screen sheet trigger that dispatches `setYear/setMonth/setHour/setPlayback` actions directly to `AppStore`.

## Task T-019 — Wire time changes into map refresh pipeline
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-018, T-013
- Complexity: Medium
- Description: Connect time state updates to filtered query + render cycle with throttling for playback.
- Deliverable: Live map updates on time interactions.
- Definition of Done: Map reflects selected bucket and playback advances without inconsistent state.
- Notes: `MapDashboardViewModel` now stores loaded flow/node data and applies throttled (`120ms`) time-scoped rendering via `TimeSeriesEngine`; `MapDashboardView` syncs on year/month/hour state changes and runs a playback loop task that advances hour while playback state is `.playing`.

## Milestone 5: Transport Filtering

## Task T-020 — Implement FilteringEngine for mode/geography/threshold scope
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-005, T-009
- Complexity: Medium
- Description: Build pure filtering service with multi-mode selection and geography constraints.
- Deliverable: `FilteringEngine` reusable by map and insights features.
- Definition of Done: Unit tests confirm deterministic results for mode combinations and region scopes.
- Notes: Added pure `FilteringEngine` + `FlowFilterCriteria`, integrated into map selection pipeline, and added executable domain tests via `run_filtering_tests.sh`.

## Task T-021 — Build ModeFilterSheet UI and ViewModel
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-003, T-020
- Complexity: Medium
- Description: Implement mode toggle controls with select-all and clear-all actions.
- Deliverable: Bottom sheet for transport mode filtering.
- Definition of Done: Mode state updates in `AppState` and selection rules are preserved.
- Notes: Added `ModeFilterSheet` and `ModeFilterViewModel`; map dashboard now presents the filter sheet and dispatches `setModes` updates to `AppStore`.

## Task T-022 — Implement legend component with unit warning state
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-021, T-014
- Complexity: Small
- Description: Show mode styles and display mixed-unit badge when applicable.
- Deliverable: `FlowLegendView` with accessibility-compliant labels and visuals.
- Definition of Done: Legend reflects active mode styles and displays mixed-unit warning correctly.
- Notes: Upgraded `FlowLegendView` to include mode-specific non-color style swatches and accessibility labels; added mixed-unit warning badge (`Mixed units: showing <unitType>`) sourced from `MapDashboardViewModel` scoped-flow unit analysis.

## Task T-023 — Integrate mode filtering into render and selection lifecycle
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-021, T-013, T-015
- Complexity: Medium
- Description: Ensure mode filter changes rerender overlays and clear invalid selection according to rules.
- Deliverable: Coherent mode-filtered rendering behavior.
- Definition of Done: Selection persistence/clear behavior matches Design Section 12.6 after mode changes.
- Notes: Map dashboard now re-runs selection/render pipeline on mode and spatial-level changes; invalid selected flow IDs are cleared when filtered segments no longer contain the selection.

## Milestone 6: UI/UX Polishing and Performance

## Task T-024 — Implement FlowDetailCard content and live update behavior
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-015, T-019, T-023
- Complexity: Medium
- Description: Show origin/destination, mode, volume, selected bucket, metadata, and playback-driven updates.
- Deliverable: Fully functional detail card with clear action.
- Definition of Done: Detail card opens, updates, and dismisses according to design behavior.
- Notes: Flow detail card now renders origin/destination, mode, volume + unit, active bucket, and optional metadata fields; detail state is derived from scoped flows in `MapDashboardViewModel` and updates on time/mode/spatial/selection changes.

## Task T-025 — Implement Insights use case and InsightsView
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-020, T-017, T-023
- Complexity: Large
- Description: Build top corridors, mode share, and time distribution outputs scoped by current filters/time.
- Deliverable: Insights tab with aggregate views and charts.
- Definition of Done: Insights values match repository-derived aggregates for current app state.
- Notes: Implemented `ComputeInsightsUseCase`, `InsightsViewModel`, and a non-placeholder `InsightsView` with scope summary, key metrics, mode share bars, top corridors, and time distribution; view recomputes on year/month/hour/mode changes from `AppStore` state.

## Task T-026 — Implement SettingsView and dataset/cache controls
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-009
- Complexity: Medium
- Description: Add dataset version display/selection hooks and cache management controls.
- Deliverable: Settings tab with data and visualization settings.
- Definition of Done: Settings actions persist and reload correctly.
- Notes: Replaced placeholder `SettingsView` with dataset/cache/visualization sections; added `SettingsViewModel` with persisted dataset source and preferred spatial level (`UserDefaults`), dataset manifest display, cache stats refresh, and cache clear action wired to shared `CacheDataSource`.

## Task T-027 — Implement in-memory and disk cache with limits
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-009
- Complexity: Large
- Description: Add cache layers with `120MB` memory cap, `500MB` disk soft cap, LRU eviction, and cache keys from Design Section 12.5.
- Deliverable: `CacheDataSource` integrated for query acceleration.
- Definition of Done: Cache respects size limits and returns deterministic hits by cache key dimensions.
- Notes: Added actor-based `CacheDataSource` with memory/disk budgets and LRU eviction; integrated cache lookup/store into map query path using keys composed of `datasetVersion`, `spatialLevel`, `timeBucketID`, `modeSet`, and `unitType`.

## Task T-028 — Implement pre-aggregation indexes by time/mode/spatial level
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-020, T-017, T-027
- Complexity: Large
- Description: Precompute and persist aggregate slices for renderer and insights.
- Deliverable: Indexed query path reducing repeated runtime aggregation.
- Definition of Done: Aggregated retrieval path is measurably faster than raw-scan baseline.
- Notes: Added `PreAggregationIndex` keyed by `timeBucketID x mode x spatialLevel x unitType`; map selection path now pulls pre-aggregated slices before filtering and rendering.

## Task T-029 — Implement incremental/diff overlay updates
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-013, T-027, T-028
- Complexity: Large
- Description: Update only changed overlays between state transitions; enforce per-level segment caps.
- Deliverable: Diff-based renderer update mechanism.
- Definition of Done: Overlay update cost reduced vs full redraw and segment limits are always enforced.
- Notes: `MapContainerView` now applies overlay add/remove/replace diffs by segment ID; `FlowMapRenderer` enforces level-specific segment caps (`1200/2000/3000`) before map sync.

## Task T-030 — Implement playback animation strategy and throttling
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-019, T-029
- Complexity: Large
- Description: Add lightweight animated flow indication compatible with MapKit constraints and throttled frame updates.
- Deliverable: Playback animation layer with stable runtime behavior.
- Definition of Done: Animation remains smooth and does not violate update latency targets in standard scenarios.
- Notes: Added throttled animation phase updates (120ms) while playback is active and wired MapKit polyline renderer dash-phase updates via `MapContainerView` coordinator.

## Task T-031 — Performance instrumentation and budget validation
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-027, T-028, T-029, T-030
- Complexity: Medium
- Description: Add metrics for frame time, filter latency, playback tick latency, and load times against target budgets.
- Deliverable: Performance report and instrumentation hooks.
- Definition of Done: Measured results reported against all Design Section 12.5 targets.
- Notes: Added `PerformanceMonitor` metric recording/reporting; instrumented load, filter, selection-to-render, playback tick, and overlay diff update timings; added budget status report and logging hook from map dashboard.

## Task T-032 — Final QA pass, accessibility checks, and cleanup
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-024, T-025, T-026, T-031
- Complexity: Medium
- Description: Execute regression, accessibility checks (legend non-color cues, contrast), and remove known polish defects.
- Deliverable: Release-candidate baseline build.
- Definition of Done: No critical regressions; accessibility and core flow acceptance checks pass.
- Notes: Completed end-to-end QA with simulator build/run and automated test pass (`FlowTests` + `FlowUITests` via `xcodebuild test`); verified map/insights/settings launch path stability, legend non-color cues + mixed-unit warning rendering, and no critical runtime regressions.

## Milestone 7: External Data Providers (Real Dataset)

## Task T-033 — Integrate Seoul/Capital real-data snapshot provider
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-009, T-017, T-020, T-025, T-026
- Complexity: Large
- Description: Add first production-style external provider path for 수도권 생활이동 OD dataset with DTO/mapping/data-source/repository normalization into existing domain models.
- Deliverable: Selectable real dataset source that coexists with sample data and works with map/time/mode/insights.
- Definition of Done: App can switch to Seoul snapshot data source and render/filter/analyze without architecture changes or crashes.
- Notes: Added `FlowDatasetSource`, Seoul DTO/mapper/data source/repositories, `MobilityRepositoryFactory`, bundled snapshot resources, and source-switch wiring in Settings/AppState/Map/Insights. Added integration tests for mode mapping, snapshot loading, and selected-source view model loading.

## Task T-034 — Implement live API refresh pipeline for Seoul source
- Status: Not Started
- Priority: P1
- Dependency: T-033
- Complexity: Large
- Description: Add API client + fetch orchestration for periodic snapshot refresh (without breaking bundled fallback).
- Deliverable: Background-refreshable Seoul provider with local persisted snapshot handoff.
- Definition of Done: App can refresh Seoul data from API and continue operating offline with last valid snapshot.

## Task T-035 — Add schema drift guardrails and source health checks
- Status: Not Started
- Priority: P1
- Dependency: T-034
- Complexity: Medium
- Description: Detect upstream schema/field drift and enforce safe fallback with explicit diagnostics.
- Deliverable: Schema compatibility report path and provider health status surfaced in logs/settings.
- Definition of Done: Incompatible payloads are rejected safely, app remains stable, and operator-visible diagnostics are emitted.

## Milestone 8: Nationwide Platform Foundation (Phase 1)

## Task T-036 — Add active dataset source badge to Map and Insights
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Surface currently selected dataset source with a compact, reusable badge on primary product surfaces.
- Deliverable: Dataset source badge component integrated in Map and Insights tabs.
- Definition of Done: Active source is visible without opening Settings.

## Task T-037 — Extend `FlowDatasetSource` with `koreaNational` placeholder
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Add `koreaNational` source case and user-facing label while preserving compatibility with existing source values.
- Deliverable: Updated source enum and labels.
- Definition of Done: Source picker can represent national placeholder source with no runtime regressions.

## Task T-038 — Harden source persistence fallback in `AppStore`
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-037
- Complexity: Small
- Description: Ensure persisted source restore supports new enum case and safely falls back on unknown values.
- Deliverable: Store migration-safe source restore behavior.
- Definition of Done: Invalid persisted value never crashes and defaults predictably.

## Task T-039 — Introduce `MobilityDatasetDescriptor` model
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Medium
- Description: Add canonical descriptor model for provider/version/coverage/precision/reliability metadata.
- Deliverable: Domain descriptor model with Codable support.
- Definition of Done: Current sample and Seoul entries can be represented without changing existing `FlowDataset`.

## Task T-040 — Introduce dataset catalog container model
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-039
- Complexity: Small
- Description: Add catalog-level model for list of available datasets and defaults.
- Deliverable: Domain catalog model.
- Definition of Done: Model can represent multi-source catalog including placeholder national entry.

## Task T-041 — Add bundled dataset catalog resource + DTO/mapper
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-040
- Complexity: Medium
- Description: Add local `dataset_catalog.json` and parse/mapping pipeline for bootstrap catalog loading.
- Deliverable: Resource + DTO + mapper path.
- Definition of Done: Catalog loads from bundle and includes sample + Seoul + koreaNational.

## Task T-042 — Implement `MobilityCatalogRepository` (local)
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-041
- Complexity: Medium
- Description: Add repository abstraction and local implementation for dataset catalog reads.
- Deliverable: `MobilityCatalogRepository` contract and local-backed implementation.
- Definition of Done: Features/services can fetch catalog entries through repository abstraction.

## Task T-043 — Add `DatasetSchemaValidator` skeleton
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: None
- Complexity: Medium
- Description: Introduce schema validator abstraction for dataset manifests/payload compatibility checks.
- Deliverable: Validator type + result model.
- Definition of Done: Existing sample/Seoul manifests pass through validator path.

## Task T-044 — Add `DatasetCompatibilityChecker` skeleton
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-043
- Complexity: Medium
- Description: Add compatibility checker abstraction for version/required-field activation checks.
- Deliverable: Checker API and baseline implementation.
- Definition of Done: Checker returns structured compatibility result for current datasets.

## Task T-045 — Add `RequiredFieldPolicy` foundation
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-044
- Complexity: Small
- Description: Define required-field policy object used by compatibility checks.
- Deliverable: Policy model + default policy profile.
- Definition of Done: Compatibility checker consumes policy object, not hardcoded field logic.

## Task T-046 — Introduce `MobilityQuery` model foundation
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Medium
- Description: Add unified query model with source selection, temporal scope, transport modes, spatial level, and aggregation intent.
- Deliverable: Domain query model.
- Definition of Done: Query can be built from current `AppState` values.

## Task T-047 — Introduce `MobilityQueryResult` model foundation
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-046
- Complexity: Small
- Description: Add unified query result model wrapping flows/nodes and source metadata.
- Deliverable: Domain query result model.
- Definition of Done: Existing single-source repository outputs can be represented in `MobilityQueryResult`.

## Task T-048 — Add `MobilityQuerying` protocol + adapter skeleton
- Status: Completed (2026-03-07)
- Priority: P1
- Dependency: T-042, T-047
- Complexity: Medium
- Description: Add query protocol and thin adapter that routes to existing repository factory for selected source.
- Deliverable: Query abstraction and default adapter.
- Definition of Done: Adapter returns `MobilityQueryResult` without changing existing feature behavior.

## Task T-049 — Add national baseline placeholder source/repository contracts
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-037, T-042
- Complexity: Medium
- Description: Add compile-safe national data source/repository placeholders and factory routing.
- Deliverable: Placeholder national source path with explicit non-fatal “not configured” behavior.
- Definition of Done: Selecting `koreaNational` does not crash and returns controlled fallback state.

## Task T-050 — Add Phase 1 primitive tests and status sync
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: T-038, T-042, T-045, T-048, T-049
- Complexity: Medium
- Description: Add tests for source persistence compatibility, catalog loading, compatibility checker baseline, query adapter, and national placeholder behavior.
- Deliverable: Passing Phase 1 architecture primitive tests.
- Definition of Done: Tests pass locally and task status/docs are synchronized with `Phase1Tasks.md`.

## 4. Sequencing (Execution Order)

1. T-001 → T-004 (skeleton and app state foundation)
2. T-005 → T-010 (models, ingest, validation, repositories, tests)
3. T-011 → T-016 (MapKit bridge, renderer, scaling, selection)
4. T-017 → T-019 (time engine and controls integration)
5. T-020 → T-023 (mode filtering and legend integration)
6. T-024 → T-026 (detail, insights, settings UX)
7. T-027 → T-031 (cache, pre-aggregation, diff updates, animation, perf validation)
8. T-032 (QA and cleanup)
9. T-033 → T-035 (external provider integration and live refresh hardening)
10. T-036 → T-050 (nationwide platform foundation phase 1)
11. Phase 2 (`P2-001` → `P2-015`) nationwide baseline vertical slice (completed; tracked in `Phase2Tasks.md`)
12. Phase 3 (`P3-001` → `P3-015`) live ingestion platform foundation (completed; tracked in `Phase3Tasks.md`)
13. Phase 4 (`P4-001` → `P4-018`) operator-safe activation rollout layer (completed; tracked in `Phase4Tasks.md`)
14. Phase 5 (`P5-001` → `P5-019`) operational maturity and persistent rollout infrastructure (in progress; tracked in `Phase5Tasks.md`)

Blocking dependencies:
- Renderer work requires data/repository core (T-005/T-009).
- Time and mode UI should not be finalized before engines (T-017/T-020).
- Performance hardening depends on stable rendering path (T-013 onward).

## 5. Parallelization Opportunities

- Track A (UI shell): T-001, T-002, T-003 can begin immediately.
- Track B (data ingest): T-005, T-006, T-007 can run while T-003 is underway.
- Track C (domain engines): T-017 and T-020 can proceed in parallel after T-009.
- Track D (feature UI): T-018 and T-021 can proceed in parallel once their engines exist.
- Track E (post-core features): T-024, T-025, T-026 can run in parallel after T-023.
- Track F (performance): T-027 can start before insights/settings are complete; T-028/T-029 follow.
- Track G (phase 1 foundation): T-039~T-042 (catalog) and T-043~T-045 (validation skeleton) can progress in parallel after T-037/T-038 are started.

## 6. Risk Flags

High-risk tasks (technical uncertainty or performance sensitivity):
- T-013: Static overlay pipeline scale on MapKit.
- T-015: Overlap hit-testing and deterministic selection behavior.
- T-028: Pre-aggregation strategy correctness + speed tradeoffs.
- T-029: Diff-based overlay updates under frequent state changes.
- T-030: Animated flow overlays on MapKit with acceptable performance.
- T-031: Meeting strict latency/frame budgets on realistic datasets.
- T-049: Placeholder national source handling may accidentally break source switching if factory fallback is incomplete.
- T-050: Primitive-layer tests may expose hidden coupling in current repositories/store persistence.

Risk mitigation rules:
- Ship static rendering before animation.
- Keep pure-engine test coverage high before UI wiring.
- Add fixture-driven integration tests before optimization changes.

## 6.1 Phase 2 Status Sync (2026-03-07)
- Source of truth: `Phase2Tasks.md`
- Status: `P2-001` through `P2-015` completed
- Completed capability set:
  - nationwide snapshot ingestion (`koreaNational`) with manifest/node/flow resources
  - DTO -> Mapper -> DataSource -> Repository national pipeline
  - schema validation + compatibility checks + explicit safe fallback semantics
  - national query integration and spatial aggregation
  - national render guardrails and render-limit metadata
  - nationwide insights compatibility
  - source-state UX truthfulness (`loading/ready/limited/unavailable`)
  - regression test protection across national + sample + Seoul paths

## 6.2 Phase 3 Status Sync (2026-03-10)
- Source of truth: `Phase3Tasks.md`
- Status: `P3-001` through `P3-015` completed
- Completed capability set:
  - snapshot-first ingestion platform (`ExternalDatasetAdapting` → materialization → gated validation)
  - concrete Seoul external adapter path for live-refresh ingestion proof
  - ingestion coordinator with integrity/schema/compatibility typed gates
  - dataset version store + manifest index + activation/rollback policy primitives
  - refresh scheduler (manual/periodic) with refresh-state reporting
  - activation-aware query consumption with safe fallback semantics
  - ingestion-to-activation integration coverage and cross-source live-refresh regression protection

## 6.3 Phase 4 Status Sync (2026-03-13)
- Source of truth: `Phase4Tasks.md`
- Status: `P4-001` through `P4-018` completed
- Completed capability set:
  - operator-safe activation command/result primitives and guard/validation model
  - guarded promote / demote / rollback execution semantics with confirmation hardening
  - activation history event model, in-memory store, and activation state projection
  - operator activation metadata enrichment for catalog/source state
  - minimal operator controls UI with action-specific confirmation flows and recent activity visibility
  - cross-source activation safety regression coverage and audit/history consistency regression protection

## 6.4 Phase 5 Status Sync (2026-03-14)
- Source of truth: `Phase5Tasks.md`
- Status: `P5-001` through `P5-003` and `P5-019` completed
- Completed capability set:
  - persistent activation history storage with local durability, migration, and fallback resilience
  - durable activation history browsing/filter query semantics for future operator audit surfaces
  - dataset activation timeline view integrated into operator controls with source-scoped newest-first history

## 7. Suggested Initial Sprint (Vertical Slice)

Recommended Sprint 1 tasks:
- T-001, T-002, T-003
- T-005, T-006, T-007, T-008, T-009, T-010
- T-011, T-012, T-013
- T-017, T-018, T-019
- T-020, T-021, T-023

Sprint 1 outcome target:
- A working vertical slice where user can open app, view map flows from local dataset, and change time + transport mode to update map deterministically.

## 8. Out of Scope for Initial Build (First Cycle)

- Real-time mobility ingestion (websocket/polling path).
- International geographic expansion and localization beyond KR baseline.
- Predictive mobility analytics and forecasting overlays.
- Advanced heatmap mode (line-centric map first).
- High-fidelity animation variants beyond lightweight playback indication.
- Remote backend integration beyond local packaged/mock datasets.
