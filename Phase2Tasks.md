# Flow Phase 2 Tasks (Nationwide Baseline Vertical Slice)

## 1. Overview
Phase 2 introduces the **first real `koreaNational` ingestion path** for Flow using a nationwide baseline snapshot.

This phase is a safe, incremental vertical slice: it enables real national baseline data to load, normalize, query, and render with guardrails. It is **not** the final multi-provider composite platform.

## 2. Phase 2 Objectives
- Replace `koreaNational` placeholder with a real nationwide baseline snapshot path.
- Register nationwide baseline dataset metadata in catalog/manifest.
- Implement DTO -> Mapper -> DataSource -> Repository pipeline for national baseline.
- Add baseline spatial aggregation for map-safe rendering (province/city-safe level).
- Ensure nationwide source works with existing query, filtering, time controls, map rendering, and insights.
- Preserve full compatibility with `bundledSample` and `seoulCapitalSnapshot` paths.
- Add ingestion/compatibility/regression tests for stable rollout.

## 3. In-Scope Work
- Nationwide baseline resource folder and file contract (manifest/nodes/flows).
- Catalog activation for `koreaNational` with real descriptor metadata.
- National DTO schema definitions and mapper normalization to canonical models.
- `NationalBaselineMobilityDataSource` real snapshot loader implementation.
- `NationalBaselineMobilityFlowRepository` / `NationalBaselineMobilityLocationRepository` production path activation.
- Baseline aggregation strategy for national map safety (province/city by zoom guardrail).
- Query adapter compatibility for national source.
- Rendering subset/threshold policy for national-scale flows.
- Insights compatibility for nationwide source.
- Regression tests across source switching and rendering behavior.

## 4. Out of Scope
- Live API sync / scheduled refresh / remote polling.
- Full composite multi-source merge engine.
- Specialist modal datasets (rail-only, air-only, maritime-only) ingestion.
- Realtime/high-frequency streaming ingestion.
- Major UI redesign or information architecture change.
- Full-scale nationwide performance optimization beyond safe baseline caps.

## 5. Milestone-to-Task Mapping

### Milestone A — National Dataset Resource Foundation
- P2-001, P2-002, P2-003

### Milestone B — National Ingestion Path
- P2-004, P2-005, P2-006, P2-007

### Milestone C — Aggregation and Query Integration
- P2-008, P2-009, P2-010

### Milestone D — Map-Safe Rendering and Insights Compatibility
- P2-011, P2-012, P2-013

### Milestone E — Validation, Regression, and Readiness
- P2-014, P2-015

## 6. Task Breakdown

## P2-001 — Define nationwide baseline snapshot resource contract
- Priority: P0
- Dependency: None
- Complexity: Small
- Description: Define and document `Resources/KoreaNationalData` file contract for manifest, nodes, and flows snapshot used by `koreaNational`.
- Deliverable: Resource contract spec + placeholder folder scaffolding.
- Definition of Done: Expected filenames, required fields, and encoding (`json`/`jsonl`, UTF-8) are explicit and versioned.

## P2-002 — Register real koreaNational descriptor in dataset catalog
- Priority: P0
- Dependency: P2-001
- Complexity: Small
- Description: Replace placeholder descriptor metadata with real national baseline descriptor in bundled catalog while preserving source IDs.
- Deliverable: Updated `dataset_catalog.json` entry for `koreaNational`.
- Definition of Done: Catalog resolves `koreaNational` as active real dataset metadata (provider/version/coverage/precision).

## P2-003 — Add nationwide manifest compatibility profile
- Priority: P1
- Dependency: P2-001
- Complexity: Medium
- Description: Extend schema/compatibility primitives with a national-baseline profile (required fields + accepted schema versions).
- Deliverable: Validator/checker policy extension for national manifest.
- Definition of Done: National manifest passes compatibility check; invalid manifest fails with structured reason.

## P2-004 — Add national baseline DTO definitions
- Priority: P0
- Dependency: P2-001
- Complexity: Medium
- Description: Define DTOs for national manifest, node, and flow payloads aligned to snapshot schema.
- Deliverable: DTO files under `Data/DTOs` for national source.
- Definition of Done: DTO decoding succeeds for fixture snapshot and enforces required fields.

## P2-005 — Implement national baseline mapper normalization
- Priority: P0
- Dependency: P2-004
- Complexity: Medium
- Description: Map national DTOs into canonical domain models (`FlowDataset`, `LocationNode`, `FlowRecord`) with consistent time bucket and mode normalization.
- Deliverable: National mapper module in `Data/Mappers`.
- Definition of Done: Mapper outputs canonical records compatible with existing filtering/time/render pipelines.

## P2-006 — Implement real NationalBaselineMobilityDataSource snapshot loader
- Priority: P0
- Dependency: P2-004, P2-005, P2-003
- Complexity: Medium
- Description: Replace placeholder throws with real local snapshot loading, decoding, mapping, and schema validation path.
- Deliverable: Working national baseline data source implementation.
- Definition of Done: Data source returns manifest/nodes/flows from bundled national snapshot without runtime crash.

## P2-007 — Activate national repositories in factory with safe fallback
- Priority: P0
- Dependency: P2-006
- Complexity: Small
- Description: Keep factory wiring to national repositories but add controlled fallback/error semantics when national snapshot is missing/corrupt.
- Deliverable: Hardened repository activation behavior.
- Definition of Done: Selecting `koreaNational` never crashes; returns data or controlled non-fatal error.

## P2-008 — Add baseline spatial aggregation policy for national source
- Priority: P0
- Dependency: P2-006
- Complexity: Large
- Description: Add first aggregation path suitable for national-scale rendering (province-level at low zoom, city-level at higher zoom where available).
- Deliverable: Spatial aggregation engine/policy extension for national source.
- Definition of Done: National flows are aggregated deterministically by spatial level and usable by existing renderer.

## P2-009 — Add national query path integration using existing query primitives
- Priority: P0
- Dependency: P2-007, P2-008
- Complexity: Medium
- Description: Ensure `MobilityQuery` + adapter path can execute against national source and return aggregated/filtered result.
- Deliverable: Query adapter enhancements for national baseline behavior.
- Definition of Done: Query execution for `koreaNational` returns valid `MobilityQueryResult` with compatibility notes.

## P2-010 — Add national-specific cache key dimensions and pre-aggregation hooks
- Priority: P1
- Dependency: P2-008
- Complexity: Medium
- Description: Extend cache/pre-aggregation seams so national aggregated slices are reused safely across time/mode/spatial combinations.
- Deliverable: National-aware cache/pre-aggregation integration updates.
- Definition of Done: Repeated national queries avoid full recomputation for identical selection states.

## P2-011 — Implement map rendering guardrails for national-scale flow counts
- Priority: P0
- Dependency: P2-008, P2-009
- Complexity: Medium
- Description: Add national rendering cap/subset strategy by zoom and volume ranking to avoid overlay overload.
- Deliverable: Renderer policy update for national source.
- Definition of Done: National map remains interactive and stable at launch/zoom transitions with visible representative flows.

## P2-012 — Ensure nationwide insights compatibility
- Priority: P1
- Dependency: P2-009
- Complexity: Medium
- Description: Validate and adjust insights calculations so national dataset produces meaningful summaries without source-specific branching leaks.
- Deliverable: Insights compatibility updates for national source.
- Definition of Done: Insights tab displays non-placeholder, coherent summaries for `koreaNational`.

## P2-013 — Add source-switching UX safety for national load states
- Priority: P1
- Dependency: P2-007, P2-011
- Complexity: Small
- Description: Ensure source switching between sample/Seoul/national preserves app stability and clear error messaging when national data path degrades.
- Deliverable: Source-switch resilience updates.
- Definition of Done: Switching across all three sources produces deterministic load behavior and recoverable errors.

## P2-014 — Add nationwide ingestion and rendering regression tests
- Priority: P0
- Dependency: P2-011, P2-012
- Complexity: Medium
- Description: Add test suite for national manifest decode, mapper normalization, repository load, query output, renderer-safe subset, and source-switch regression.
- Deliverable: Passing automated Phase 2 regression tests.
- Definition of Done: National tests pass alongside existing sample/Seoul tests with no regressions.

## P2-015 — Phase 2 status sync and rollout checklist
- Priority: P0
- Dependency: P2-014
- Complexity: Small
- Description: Synchronize `Tasks.md` status mapping for Phase 2 tasks and add rollout checklist for enabling national source by default/non-default.
- Deliverable: Updated task tracking and release readiness notes.
- Definition of Done: Phase 2 tasks are traceable, tested, and deployment toggles are documented.

## 7. Execution Order
1. P2-001
2. P2-002
3. P2-004
4. P2-005
5. P2-003
6. P2-006
7. P2-007
8. P2-008
9. P2-009
10. P2-011
11. P2-012
12. P2-013
13. P2-010
14. P2-014
15. P2-015

## 8. Parallelization Opportunities
- Track A (resource/catalog): P2-001 and P2-002 can proceed while DTO work starts.
- Track B (ingestion core): P2-004 and early P2-003 profile drafting can proceed in parallel.
- Track C (post-ingestion): P2-008 and P2-013 can partially progress in parallel after P2-007.
- Track D (consumer integration): P2-012 can start while P2-011 rendering guardrails are finalized.
- Track E (hardening): P2-010 cache hook work can run parallel with P2-012 once aggregation behavior is stable.

## 9. Risk Flags
- **Dataset size risk**: National snapshot may exceed current memory/render assumptions.
- **Schema mismatch risk**: National payload fields/time buckets may drift from existing canonical expectations.
- **Metadata completeness risk**: Region/type metadata may be partial for some nodes/flows.
- **Rendering overload risk**: Low-zoom map can become unusable with dense OD lines.
- **Aggregation correctness risk**: Province/city roll-up errors can distort insights and map trust.
- **Source-switch regression risk**: Activating national path may accidentally break sample/Seoul behavior.

Mitigations:
- Enforce strict manifest/required-field validation before activation.
- Apply conservative rendering caps and zoom-level aggregation defaults.
- Keep fallback path non-fatal and explicit.
- Add fixture-driven regression tests across all three sources before enabling defaults.

## 10. Recommended First Implementation Slice
Start with the smallest real nationwide vertical slice:
1. P2-001 — Snapshot resource contract.
2. P2-002 — Catalog registration for real `koreaNational` descriptor.
3. P2-004 — National DTO definitions.
4. P2-005 — National mapper normalization.
5. P2-006 — Real national data source loader.

This slice delivers a real ingestible national source path quickly, while keeping rendering/aggregation hardening as the next safe increment.

---

- Total tasks: 15
- P0 tasks: P2-001, P2-002, P2-004, P2-005, P2-006, P2-007, P2-008, P2-009, P2-011, P2-014, P2-015
- Recommended starting task: P2-001 — Define nationwide baseline snapshot resource contract
