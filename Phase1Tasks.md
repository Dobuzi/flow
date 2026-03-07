# Flow Phase 1 Tasks (Nationwide Platform Foundation)

## 1. Overview
Phase 1 establishes the architectural groundwork for expanding Flow into a nationwide mobility data platform.

This phase is intentionally foundation-focused. It does **not** attempt full nationwide ingestion or composite analytics rollout yet.  
Goal: extend the current architecture safely while keeping sample + SeoulCapital paths fully working.

## 2. Phase 1 Objectives
- Make active dataset source more visible in the UI.
- Introduce a dataset catalog foundation (descriptor + catalog repository + bundled catalog resource).
- Add compatibility/validation skeletons for future provider growth.
- Introduce query foundation models (`MobilityQuery`, `MobilityQueryResult`) without replacing current pipelines.
- Extend dataset source enum/state for national placeholder support.
- Add national placeholder data-source/repository contracts for future KTDB integration.
- Keep all additions backward compatible with existing repositories and view models.

## 3. In-Scope Work
- Active dataset source badge/label in visible UI surfaces.
- `FlowDatasetSource` extension for `koreaNational` placeholder.
- Dataset descriptor/catalog domain model foundations.
- Bundled dataset catalog resource + local loader.
- Schema validator and compatibility checker skeletons.
- Required-field policy skeleton.
- `MobilityQuery` and `MobilityQueryResult` foundation models.
- Placeholder contracts/types for national baseline data source and repository.
- Snapshot/version metadata model groundwork.
- Unit tests for new architectural primitives.

## 4. Out of Scope
- Full KTDB (or other nationwide) ingestion implementation.
- Full composite repository merge logic and conflict-resolution engine behavior.
- Remote API sync/refresh orchestration.
- Large-scale map rendering redesign/performance overhaul.
- Broad refactor of existing working app flows.
- Replacing current `MapDashboardViewModel`/`InsightsViewModel` data pipeline.

## 5. Milestone-to-Task Mapping

### Milestone A — Source Visibility + Enum Compatibility
- P1-001, P1-002, P1-003

### Milestone B — Dataset Catalog Foundation
- P1-004, P1-005, P1-006, P1-007

### Milestone C — Validation/Compatibility Skeleton
- P1-008, P1-009, P1-010

### Milestone D — Query Foundation + National Placeholder Contracts
- P1-011, P1-012, P1-013, P1-014

### Milestone E — Phase 1 Validation and Documentation Sync
- P1-015

## 6. Task Breakdown

## P1-001 — Add active dataset source badge in Map and Insights
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Surface currently selected dataset source as a compact badge/label in Map and Insights screens for operator visibility.
- Deliverable: Reusable source badge UI component and screen integration.
- Definition of Done: User can always identify active source (`sample`, `seoulCapital`, future `koreaNational`) from primary screens.
- Notes: Added reusable `DatasetSourceBadge` component and integrated it into MapDashboard and Insights views using `AppStore.state.selectedDatasetSource`.

## P1-002 — Expand `FlowDatasetSource` for `koreaNational` placeholder
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Add a new enum case for national baseline placeholder and display title, preserving existing enum raw values compatibility.
- Deliverable: Updated source enum with non-breaking labels.
- Definition of Done: App compiles and source picker can represent new case without breaking existing selections.
- Notes: Added `koreaNational` enum case with stable raw value (`korea_national`) and placeholder title.

## P1-003 — Add safe state/store handling for new dataset source
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: P1-002
- Complexity: Small
- Description: Ensure `AppState`/`AppStore` persistence and defaulting logic handle the new source safely (including fallback on unknown/legacy values).
- Deliverable: Store migration-safe source selection behavior.
- Definition of Done: Persisted source restore works; invalid stored source falls back deterministically.
- Notes: Added persisted-value normalization/alias parsing and explicit fallback to bundled sample on unknown values with warning logs.

## P1-004 — Introduce `MobilityDatasetDescriptor` model
- Status: Completed (2026-03-07)
- Priority: P0
- Dependency: None
- Complexity: Medium
- Description: Add canonical descriptor model for dataset catalog entries (provider/version/coverage/precision/quality).
- Deliverable: New domain model file with Codable/Hashable support.
- Definition of Done: Descriptor supports sample and SeoulCapital entries without altering existing `FlowDataset`.
- Notes: Added canonical descriptor with provider/version/schema/coverage/precision/reliability fields and source linkage via `FlowDatasetSource`.

## P1-005 — Introduce dataset catalog container model
- Priority: P0
- Dependency: P1-004
- Complexity: Small
- Description: Add catalog container model representing available datasets and active/default recommendations.
- Deliverable: `MobilityDatasetCatalog` (or equivalent) domain model.
- Definition of Done: Model can represent multiple sources and descriptor metadata for UI/repository consumption.
- Status: Completed (2026-03-07)
- Notes: Added `MobilityDatasetCatalog` with `version/defaultSource/datasets` and source lookup helper for repository/UI consumers.

## P1-006 — Add bundled dataset catalog resource + DTO/mapper
- Priority: P0
- Dependency: P1-004, P1-005
- Complexity: Medium
- Description: Add `Resources/DatasetCatalog/dataset_catalog.json` and parsing layer (`DTO` + `Mapper`) for local catalog bootstrap.
- Deliverable: Bundled catalog file and typed mapper pipeline.
- Definition of Done: Catalog loads successfully and contains current sample + SeoulCapital + koreaNational placeholder entries.
- Status: Completed (2026-03-07)
- Notes: Added bundled catalog snapshot, `MobilityDatasetCatalogDTO`, mapper to domain catalog/descriptor models, and integration test validating all three dataset entries.

## P1-007 — Implement `MobilityCatalogRepository` local read path
- Priority: P0
- Dependency: P1-006
- Complexity: Medium
- Description: Add repository contract and local implementation for retrieving dataset catalog data.
- Deliverable: Catalog repository interface and local-backed concrete implementation.
- Definition of Done: Settings or internal callers can fetch catalog entries through repository abstraction.
- Status: Completed (2026-03-07)
- Notes: Added catalog repository/data source contracts, local bundled implementation, factory accessor, and integration test validating repository fetch path.

## P1-008 — Add `DatasetSchemaValidator` skeleton
- Priority: P1
- Dependency: None
- Complexity: Medium
- Description: Introduce validator skeleton API for dataset schema compatibility checks (initially delegates/bridges to current schema checks).
- Deliverable: Validator type, result model, and integration seam.
- Definition of Done: Existing sample and Seoul dataset manifests pass through validator path without behavior regression.
- Status: Completed (2026-03-07)
- Notes: Added `DatasetSchemaValidator`/result/protocol primitives and routed sample+Seoul manifest schema checks through validator seam without changing behavior.

## P1-009 — Add `DatasetCompatibilityChecker` skeleton
- Priority: P1
- Dependency: P1-008
- Complexity: Medium
- Description: Add compatibility checker abstraction for required fields, version ranges, and source activation eligibility.
- Deliverable: Checker API and baseline implementation returning structured compatibility result.
- Definition of Done: Checker can evaluate current datasets and report `compatible` status with reason fields.
- Status: Completed (2026-03-07)
- Notes: Added compatibility result/protocol/checker skeleton with reason fields (`schema_version_unsupported`, `required_fields_missing`) and tests covering sample+Seoul compatibility.

## P1-010 — Add `RequiredFieldPolicy` foundation
- Priority: P1
- Dependency: P1-009
- Complexity: Small
- Description: Define a required-field policy type used by compatibility checks for future provider-specific rules.
- Deliverable: Policy model + default policy for current schema.
- Definition of Done: Compatibility checker consumes policy object rather than hardcoded field checks.
- Status: Completed (2026-03-07)
- Notes: Added `RequiredFieldPolicy` with schema-v1 defaults and updated compatibility checker to consume policy-driven required fields.

## P1-011 — Introduce `MobilityQuery` model foundation
- Priority: P0
- Dependency: None
- Complexity: Medium
- Description: Add unified query model capturing source selection, mode filter, spatial level, time range, and aggregation intent.
- Deliverable: Query model with sensible defaults aligned to current AppState fields.
- Definition of Done: Query can be constructed from current app state without changing existing screen behavior.
- Status: Completed (2026-03-07)
- Notes: Added `MobilityQuery` + time/aggregation primitives in Domain and `AppState.toMobilityQuery()` adapter preserving existing state semantics.

## P1-012 — Introduce `MobilityQueryResult` model foundation
- Priority: P0
- Dependency: P1-011
- Complexity: Small
- Description: Add result container model for queried flows/nodes plus metadata (source set, timing, compatibility notes).
- Deliverable: Query result model type.
- Definition of Done: Model can wrap existing single-source repository outputs and metadata.
- Status: Completed (2026-03-07)
- Notes: Added `MobilityQueryResult` with single-source convenience constructor and tests validating wrapping of current repository-shaped outputs.

## P1-013 — Add `MobilityQuerying` protocol and adapter skeleton
- Priority: P1
- Dependency: P1-011, P1-012, P1-007
- Complexity: Medium
- Description: Create protocol for future composite query orchestration and a v1 adapter that maps one selected source to current repositories.
- Deliverable: Query protocol + default adapter implementation.
- Definition of Done: Adapter returns `MobilityQueryResult` using existing repository factory path with no feature regressions.
- Status: Completed (2026-03-07)
- Notes: Added `MobilityQuerying` + `DefaultMobilityQueryAdapter` that resolves single-source queries through existing repositories and outputs `MobilityQueryResult`.

## P1-014 — Add national placeholder source/repository contracts
- Priority: P0
- Dependency: P1-002, P1-007
- Complexity: Medium
- Description: Add placeholder `NationalBaselineMobilityDataSource` and repository contracts/types; wire factory branch to a safe placeholder behavior.
- Deliverable: Compile-safe national placeholder path with explicit “not configured” handling.
- Definition of Done: Selecting `koreaNational` does not crash; app surfaces controlled non-fatal state until real dataset is integrated.
- Status: Completed (2026-03-07)
- Notes: Added national placeholder data source/repositories and factory routing so `koreaNational` returns controlled non-fatal error state instead of fallbacking silently.

## P1-015 — Add Phase 1 architecture primitive tests and docs sync
- Priority: P0
- Dependency: P1-003, P1-007, P1-010, P1-013, P1-014
- Complexity: Medium
- Description: Add tests for source enum/store compatibility, catalog load, compatibility checker baseline, query model/adapter, and national placeholder behavior. Update `Tasks.md` status mapping for Phase 1 task IDs.
- Deliverable: Passing test set and updated task tracking references.
- Definition of Done: Phase 1 primitives are covered by tests and documented for implementation sequencing.
- Status: Completed (2026-03-07)
- Notes: Added/ran Phase 1 primitive test set (source persistence, catalog load/repository, schema+compatibility validation, query/query-result/query-adapter, national placeholder path) and synchronized `Tasks.md` T-036~T-050 statuses.

## 7. Execution Order
1. P1-002
2. P1-003
3. P1-001
4. P1-004
5. P1-005
6. P1-006
7. P1-007
8. P1-008
9. P1-009
10. P1-010
11. P1-011
12. P1-012
13. P1-013
14. P1-014
15. P1-015

## 8. Parallelization Opportunities
- Track A (UI/source visibility): P1-001 can run in parallel with P1-004/P1-005 once P1-002 exists.
- Track B (catalog foundation): P1-004/P1-005 can run in parallel with early validation skeleton (P1-008).
- Track C (query foundation): P1-011/P1-012 can start while P1-007 is being finalized.
- Track D (validation): P1-009/P1-010 can proceed after P1-008 without waiting for P1-013.

## 9. Risk Flags
- P1-003: persisted enum changes can break old saved settings if fallback handling is incomplete.
- P1-006: catalog resource/DTO drift risk if schema is not versioned from day one.
- P1-009/P1-010: checker may become dead code if not integrated at repository activation boundaries.
- P1-014: placeholder source path can accidentally trigger runtime crashes if factory/default handling is partial.
- P1-013: premature abstraction risk; keep adapter thin and mapped directly to current repository flow.

## 10. Recommended First Implementation Slice
Start with a small vertical slice that improves user value and sets stable extension points:
1. P1-002 — Expand `FlowDatasetSource` for `koreaNational`.
2. P1-003 — Store/state compatibility handling.
3. P1-001 — Active source badge in Map/Insights.
4. P1-014 — Safe national placeholder path.

This slice immediately provides visible multi-source readiness while keeping existing sample + Seoul behavior stable.

---

- Total tasks: 15
- P0 tasks: P1-001, P1-002, P1-003, P1-004, P1-005, P1-006, P1-007, P1-011, P1-012, P1-014, P1-015
- Recommended starting task: P1-002 — Expand `FlowDatasetSource` for `koreaNational` placeholder
