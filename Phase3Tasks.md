# Flow Phase 3 Tasks (Live Mobility Intelligence Platform)

## 1. Overview
Phase 3 extends Flow from a static nationwide snapshot viewer to a **live mobility intelligence platform** by adding API-driven ingestion with safe snapshot materialization.

This phase keeps the existing architecture intact and extends it incrementally so runtime visualization remains snapshot-first and stable.

Core lifecycle for all external data:
`External API/Dataset -> Ingestion Pipeline -> Snapshot Materialization -> Validation -> Versioned Storage -> Snapshot Activation -> Query/Visualization`

## 2. Phase 3 Objectives
- Introduce API-based ingestion paths without making runtime map/insights depend directly on unstable APIs.
- Build a controlled snapshot refresh pipeline with validation gates.
- Add versioned dataset storage and activation policy (including last-known-good fallback).
- Expand source catalog/version metadata for operational visibility.
- Improve readiness for national-scale analytics under continuously refreshed data.
- Preserve backward compatibility with `bundledSample`, `seoulCapitalSnapshot`, and `koreaNational` snapshot paths.

## 3. In Scope
- External API adapter contracts and first concrete adapter(s).
- Ingestion orchestration service and snapshot materializer.
- Snapshot validation, compatibility checks, and drift detection hooks.
- Versioned snapshot storage/index and activation state tracking.
- Safe activation policy and rollback to last-known-good snapshot.
- Refresh scheduling triggers (manual + app-lifecycle-safe periodic checks).
- Operational metadata exposure (last refresh, active version, status).
- Regression and integration tests for ingestion-to-activation lifecycle.

## 4. Out of Scope
- True real-time stream processing (WebSocket/high-frequency push).
- ML forecasting/prediction models.
- Distributed analytics backend redesign.
- Large UI redesign beyond minimal source/refresh status surfaces.
- Rewriting Phase 1/2 architecture or replacing current repository/query flow.

## 5. Architecture Extensions
Existing baseline (preserved):
`DTO -> Mapper -> DataSource -> Repository -> Query -> Visualization`

Phase 3 additive components:
- **External API Adapter**: fetch provider payloads and map to staging DTOs.
- **Ingestion Pipeline**: orchestrate fetch -> map -> validate -> materialize.
- **Snapshot Materializer**: writes canonical manifest/nodes/flows snapshots.
- **Dataset Version Store**: tracks installed versions, active version, last-known-good.
- **Snapshot Activation Policy**: atomic activation only after validation gates pass.

Design constraints:
- Reuse existing validators/checkers and repository factory seams.
- Keep runtime reads snapshot-based.
- Keep failure semantics explicit and non-fatal.

## 6. Milestones
- **M3-1 Ingestion Framework**
- **M3-2 Snapshot Materialization Pipeline**
- **M3-3 Dataset Version Management**
- **M3-4 API Dataset Integration**
- **M3-5 Analytics Readiness and Regression Hardening**

## 7. Task Breakdown

### M3-1 Ingestion Framework

## P3-001 — Define API snapshot materialization contract
- Priority: P0
- Dependency: None
- Description: Define canonical contract for API-ingested snapshot artifacts (manifest, nodes, flows), naming/versioning/checksum fields, and required metadata.
- Short goal: Establish one immutable ingestion target format for all adapters.
- Status: Completed (2026-03-08)
- Notes: Added `MaterializedSnapshotContract` primitives (`snapshotID`, source/schema/dataset versions, coverage, record counts, required files, compatibility metadata, activation eligibility), structural contract validation rules, and a snapshot materializer protocol boundary (`SnapshotMaterializing`) for future ingestion pipeline implementations.

## P3-002 — Add external API adapter protocol and error model
- Priority: P0
- Dependency: P3-001
- Description: Introduce `MobilityAPIAdapter` protocol, typed transport/network/schema errors, and retryability metadata.
- Short goal: Standardize provider adapters without changing runtime repositories.
- Status: Completed (2026-03-08)
- Notes: Added `ExternalDatasetAdapting` boundary and normalized fetch request/result/payload models with structural validation. Added typed `ExternalDatasetAdapterError` classifications (network/auth/rate-limit/payload/schema/version/empty/partial) including retryability semantics and mapping to materialization input.

## P3-003 — Implement ingestion pipeline coordinator skeleton
- Priority: P0
- Dependency: P3-001, P3-002
- Description: Add orchestration service that executes fetch -> decode -> map -> validate -> materialize with structured result reporting.
- Short goal: Create the end-to-end pipeline shell used by all providers.
- Status: Completed (2026-03-08)
- Notes: Added `IngestionPipelineCoordinating` and `DefaultIngestionPipelineCoordinator` to orchestrate adapter fetch, payload validation, materialization input conversion, materializer invocation, materialized contract structural validation, and compatibility gating with typed result/error reporting.

### M3-2 Snapshot Materialization Pipeline

## P3-004 — Implement snapshot materializer service
- Priority: P0
- Dependency: P3-003
- Description: Materialize canonical JSON/JSONL snapshot artifacts in app storage with atomic write strategy.
- Short goal: Persist validated ingest outputs as runtime-consumable snapshots.
- Status: Completed (2026-03-08)
- Notes: Added `DefaultSnapshotMaterializer` conforming to `SnapshotMaterializing` with deterministic required-file role checks (`manifest`/`nodes`/`flows`), materialization metadata derivation (`dataset_id`, `snapshot_id`, `schema_version`, `time_coverage`, `spatial_coverage`), checksum generation fallback, contract assembly via `MaterializedSnapshotContract`, and structural rejection semantics for incomplete/inconsistent inputs.

## P3-005 — Add snapshot integrity checker (checksum + file completeness)
- Priority: P0
- Dependency: P3-004
- Description: Validate materialized snapshot completeness and checksum integrity before version registration.
- Short goal: Prevent partial/corrupt snapshot activation.
- Status: Completed (2026-03-08)
- Notes: Added `SnapshotIntegrityChecking` with `DefaultSnapshotIntegrityChecker` to verify required file-role completeness, checksum presence/match, and file metadata consistency (`byteCount`, `recordCount`) against materialized payloads. Integrated integrity gating into `DefaultIngestionPipelineCoordinator` after contract validation and before compatibility readiness with explicit `integrityFailed` error semantics.

## P3-006 — Integrate schema validation + compatibility gates into ingestion
- Priority: P0
- Dependency: P3-003, P3-005
- Description: Enforce `DatasetSchemaValidator` + `DatasetCompatibilityChecker` in pipeline gate before activation eligibility.
- Short goal: Block incompatible snapshots deterministically.
- Status: Completed (2026-03-08)
- Notes: Extended ingestion coordinator with explicit post-integrity schema and compatibility gates using `DatasetSchemaValidating` and `DatasetCompatibilityChecking`. Added typed gate outcomes (`compatible`/`partiallyCompatible`/`incompatible`) and explicit pipeline errors for schema/compatibility failures.

### M3-3 Dataset Version Management

## P3-007 — Implement dataset version store and manifest index
- Priority: P0
- Dependency: P3-004
- Description: Add version registry (`installed`, `active`, `lastKnownGood`, timestamps, source/provider tags).
- Short goal: Track multiple snapshot versions safely.
- Status: Completed (2026-03-08)
- Notes: Added `DatasetVersionStoring` with `InMemoryDatasetVersionStore`, `StoredSnapshotVersion`, and `DatasetManifestIndex` for source/version/snapshot lookups and deterministic ordering. Integrated optional ingestion success indexing in coordinator with compatibility classification and activation eligibility metadata.

## P3-008 — Implement snapshot activation policy with rollback
- Priority: P0
- Dependency: P3-006, P3-007
- Description: Add activation rules and atomic switch to new version; rollback to last-known-good on activation failure.
- Short goal: Guarantee non-disruptive upgrades.
- Status: Completed (2026-03-08)
- Notes: Added `SnapshotActivationPolicying` with `DefaultSnapshotActivationPolicy` and explicit decision/state/error models for activation and rollback (`SnapshotActivationDecision`, `SnapshotActivationState`, `SnapshotRollbackDecision`, `SnapshotActivationError`). Policy now selects activatable snapshots from `DatasetVersionStore`, preserves last-known-good state, and exposes explicit no-safe-rollback semantics without changing runtime dataset switching.

## P3-009 — Extend dataset catalog metadata for live/version state
- Priority: P1
- Dependency: P3-007
- Description: Add live metadata fields (active version, last refresh outcome/time, refresh source) while keeping existing catalog compatibility.
- Short goal: Surface operational state consistently.
- Status: Completed (2026-03-08)
- Notes: Extended catalog descriptor metadata with `DatasetLiveMetadata` and added optional live-state enrichment via `CatalogLiveMetadataEnricher` backed by `DatasetVersionStore` + `SnapshotActivationPolicy`. Static sources remain compatible (no live metadata required), while live-capable sources can now expose latest snapshot/version and readiness/sync state.

### M3-4 API Dataset Integration

## P3-010 — Implement first concrete API adapter (Seoul incremental refresh)
- Priority: P0
- Dependency: P3-002, P3-003
- Description: Add first provider adapter that fetches Seoul data and emits pipeline-ready DTO payloads.
- Short goal: Prove live ingestion path on an existing source.
- Status: Completed (2026-03-08)
- Notes: Added `SeoulCapitalExternalDatasetAdapter` with injectable `SeoulCapitalRemoteFetching` boundary and a local remote-simulation fetcher. Adapter now validates source/schema/version expectations, normalizes to `ExternalDatasetPayload` (`manifest`/`nodes`/`flows`), captures refresh metadata for incremental semantics, and maps failures to typed `ExternalDatasetAdapterError` cases.

## P3-011 — Wire refresh scheduler (manual + periodic safe trigger)
- Priority: P1
- Dependency: P3-003, P3-010
- Description: Add controlled refresh triggers (manual action + periodic check) with backoff and foreground safety constraints.
- Short goal: Make ingestion operable without background-service complexity.

## P3-012 — Add source health/status reporting for refresh outcomes
- Priority: P1
- Dependency: P3-008, P3-011
- Description: Expose refresh/activation outcomes as structured source status (`healthy`, `degraded`, `failed`, reason).
- Short goal: Keep UX truthful during live refresh lifecycle.

### M3-5 Analytics Readiness and Regression Hardening

## P3-013 — Ensure query path consumes newly activated snapshot versions
- Priority: P0
- Dependency: P3-008
- Description: Confirm repository/query paths resolve active snapshot versions without source switching regressions.
- Short goal: Keep map/insights aligned with activated data version.

## P3-014 — Add ingestion-to-activation integration tests
- Priority: P0
- Dependency: P3-006, P3-008, P3-010
- Description: Add tests for success/failure pipeline, activation gating, rollback behavior, and non-fatal semantics.
- Short goal: Lock down lifecycle correctness.

## P3-015 — Add cross-source regression suite for live-refresh era
- Priority: P0
- Dependency: P3-014
- Description: Validate no regressions across `bundledSample`, `seoulCapitalSnapshot`, and `koreaNational` with live-ingestion features enabled.
- Short goal: Preserve backward compatibility while adding live ingestion.

## 8. Execution Order
1. P3-001
2. P3-002
3. P3-003
4. P3-004
5. P3-005
6. P3-006
7. P3-007
8. P3-008
9. P3-010
10. P3-009
11. P3-011
12. P3-012
13. P3-013
14. P3-014
15. P3-015

## 9. Parallelization Opportunities
- Track A (contracts): P3-001 and early draft of P3-009 can proceed in parallel.
- Track B (pipeline core): P3-004 and P3-005 can overlap after P3-003.
- Track C (versioning): P3-007 can start while P3-006 finalizes.
- Track D (integration): P3-010 can begin once P3-002/P3-003 are stable.
- Track E (hardening): P3-012 preparation and test fixture setup for P3-014 can run in parallel after P3-008.

## 10. Risks
- **Schema drift risk**: Provider fields or semantics may change without notice.
- **API instability risk**: Timeouts/rate limits can produce partial refresh cycles.
- **Dataset growth risk**: Snapshot size may exceed current materialization/storage assumptions.
- **Activation safety risk**: Incorrect activation could expose incomplete snapshots.
- **Ingestion latency risk**: Slow pipeline may block user-triggered refresh UX.
- **Cross-source regression risk**: Live ingestion changes may unintentionally impact static sources.

Mitigations:
- Hard validation gates + explicit compatibility checks before activation.
- Atomic snapshot writes and integrity verification.
- Last-known-good rollback policy.
- Retry/backoff with clear status reporting.
- Regression suites across all supported sources.

## 11. Recommended First Implementation Slice
1. **P3-001 — Define API snapshot materialization contract**
2. **P3-002 — Add external API adapter protocol and error model**
3. **P3-003 — Implement ingestion pipeline coordinator skeleton**

This slice establishes stable interfaces first, enabling safe incremental implementation without changing runtime visualization paths.

---

- Total tasks: 15
- P0 tasks: P3-001, P3-002, P3-003, P3-004, P3-005, P3-006, P3-007, P3-008, P3-010, P3-013, P3-014, P3-015
- Recommended starting task: P3-001 — Define API snapshot materialization contract
