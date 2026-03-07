# Korea Mobility Architecture Plan

## 1. Architecture Overview
Flow should evolve from a single-snapshot app into a nationwide mobility platform by extending the current `DTO -> Mapper -> DataSource -> Repository` pipeline, not replacing it.

Design principles:
- Keep current domain models and ViewModel pipelines backward compatible.
- Add provider-specific modules under `Data/*` and aggregation/query services under `Domain/*`.
- Keep `MapDashboardViewModel` and `InsightsViewModel` consuming repository/query abstractions, not provider-specific code.

## 2. Current System Evaluation
Already in place:
- Multi-source selection via `FlowDatasetSource` and `AppState.selectedDatasetSource`.
- Provider-specific ingestion path:
  - `LocalJSONDataSource`, `SeoulCapitalMobilityDataSource`
  - `SeoulCapitalMobilityMapper`
  - source-specific repositories + `MobilityRepositoryFactory`
- Canonical domain model compatibility:
  - `FlowRecord`, `LocationNode`, `FlowDataset`, `TransportMode`
- Existing operational pipelines:
  - map rendering + filtering + time selection + pre-aggregation + cache
  - insights aggregation scoped by current state
- Validation baseline:
  - manifest schema checks (`schemaVersion`)
  - ingestion tests and rendering tests

Gaps for nationwide platform:
- No dataset catalog/registry to describe many providers and versions.
- No composite repository for merging multiple datasets in one query.
- No explicit conflict-resolution/precedence rules across overlapping datasets.
- No generalized spatial/temporal aggregation engines across heterogeneous precision.
- No snapshot index/store lifecycle for multiple external versions.
- No API refresh/sync orchestration or schema drift monitor.

## 3. Target Mobility Platform Architecture
Target model: **Catalog-driven multi-provider mobility platform**

Layers:
- Provider Ingestion Layer: source-specific DTO, mapper, validation, snapshot loader.
- Catalog & Snapshot Layer: dataset descriptors, compatibility, installed snapshots, active source sets.
- Composite Query Layer: query one or many datasets with merge + aggregation strategies.
- Aggregation Layer: spatial, temporal, ranking, and dedup/conflict resolution.
- Consumption Layer: existing map/insights features with minimal interface changes.

Data flow:
1. Provider snapshot/API payload -> DTO parse
2. Mapper -> canonical records
3. Validation + quality metadata enrichment
4. Snapshot store persist + catalog registration
5. Composite repository query
6. Aggregation engines produce map/insights-ready records

## 4. New Components to Implement

### 4.1 Domain Models
1. `Flow/Domain/Models/MobilityDatasetDescriptor.swift`
- Purpose: catalog-level metadata per dataset source/version.
- Fields: `datasetID`, `providerID`, `version`, `coverage`, `modes`, `spatialPrecision`, `temporalPrecision`, `qualityScore`.

2. `Flow/Domain/Models/MobilityQuery.swift`
- Purpose: unified query contract for map/insights.
- Fields: `spatialLevel`, `timeRange`, `modes`, `datasetSelection`, `aggregationPolicy`, `minVolume`.

3. `Flow/Domain/Models/DatasetQualityProfile.swift`
- Purpose: quality metadata attached to dataset or record batch.
- Fields: `reliability`, `schemaVersion`, `spatialPrecision`, `temporalPrecision`, `sourceTag`.

4. `Flow/Domain/Models/MergePolicy.swift`
- Purpose: deterministic merge behavior.
- Cases: `preferHigherReliability`, `preferHigherResolution`, `providerPriority([String])`, `weightedBlend`.

### 4.2 Domain Services / Engines
1. `Flow/Domain/Engines/SpatialAggregationEngine.swift`
- Responsibilities: aggregate OD flows by spatial level and region mapping table.

2. `Flow/Domain/Engines/TemporalAggregationEngine.swift`
- Responsibilities: normalize and roll up hourly/daily/monthly buckets.

3. `Flow/Domain/Engines/FlowMergeEngine.swift`
- Responsibilities: merge overlapping flows across datasets using `MergePolicy`.

4. `Flow/Domain/Engines/TopFlowRankingEngine.swift`
- Responsibilities: consistent ranking for insights and map prioritization.

5. `Flow/Domain/UseCases/QueryMobilityFlowsUseCase.swift`
- Responsibilities: orchestrate query -> fetch -> merge -> aggregate path.

### 4.3 Data Sources
1. Nationwide baseline:
- `Flow/Data/Sources/NationalBaselineMobilityDataSource.swift`
- Example providers: KTDB national OD baseline.

2. Modal specialist snapshots:
- `RailMobilityDataSource.swift`
- `AirMobilityDataSource.swift`
- `MaritimeMobilityDataSource.swift`

3. API source adapters (future):
- `Flow/Data/Sources/API/SeoulMobilityAPIDataSource.swift`
- `Flow/Data/Sources/API/NationalMobilityAPIDataSource.swift`

### 4.4 Repositories
1. `Flow/Data/Repositories/MobilityCatalogRepository.swift`
- Read available datasets, versions, quality profiles.

2. `Flow/Data/Repositories/CompositeMobilityRepository.swift`
- Query multiple repositories and return unified flow/node sets.

3. `Flow/Data/Repositories/ProviderRepositoryFactory.swift`
- Extend current `MobilityRepositoryFactory` for provider-specific repository lookup.

### 4.5 Validation Layer
1. `Flow/Data/Validation/DatasetSchemaValidator.swift`
2. `Flow/Data/Validation/CompatibilityValidator.swift`
3. `Flow/Data/Validation/SchemaDriftDetector.swift`

Responsibilities:
- validate incoming payloads against expected schema versions
- enforce backward-compatible field requirements
- emit drift warnings and fallback decisions

### 4.6 Snapshot & Cache Components
1. `Flow/Data/Snapshot/MobilitySnapshotStore.swift`
- Persist multiple dataset snapshots (versioned).

2. `Flow/Data/Snapshot/SnapshotManifestIndex.swift`
- Maintain installed snapshot registry and active pointers.

3. `Flow/Data/Snapshot/SnapshotIntegrityChecker.swift`
- Check checksum, schema compatibility, required files.

### 4.7 Dataset Catalog System
1. `Flow/Resources/DatasetCatalog/dataset_catalog.json`
2. `Flow/Data/DTOs/DatasetCatalogDTO.swift`
3. `Flow/Data/Mappers/DatasetCatalogMapper.swift`

Catalog should track:
- dataset identity and provider
- version and update date
- available modes/time/spatial coverage
- reliability and precision metadata
- compatibility with app schema version

## 5. Recommended Repository Structure
```text
Flow/
  Domain/
    Models/
      MobilityDatasetDescriptor.swift
      MobilityQuery.swift
      DatasetQualityProfile.swift
      MergePolicy.swift
    Engines/
      SpatialAggregationEngine.swift
      TemporalAggregationEngine.swift
      FlowMergeEngine.swift
      TopFlowRankingEngine.swift
    UseCases/
      QueryMobilityFlowsUseCase.swift
  Data/
    Sources/
      NationalBaselineMobilityDataSource.swift
      RailMobilityDataSource.swift
      AirMobilityDataSource.swift
      MaritimeMobilityDataSource.swift
      API/
        SeoulMobilityAPIDataSource.swift
        NationalMobilityAPIDataSource.swift
    Repositories/
      MobilityCatalogRepository.swift
      CompositeMobilityRepository.swift
      ProviderRepositoryFactory.swift
    Validation/
      DatasetSchemaValidator.swift
      CompatibilityValidator.swift
      SchemaDriftDetector.swift
    Snapshot/
      MobilitySnapshotStore.swift
      SnapshotManifestIndex.swift
      SnapshotIntegrityChecker.swift
    DTOs/
      DatasetCatalogDTO.swift
    Mappers/
      DatasetCatalogMapper.swift
  Resources/
    DatasetCatalog/
      dataset_catalog.json
```

## 6. Aggregation Strategy
- Input normalization:
  - all providers mapped to canonical `FlowRecord` + `LocationNode`
  - time bucket normalized to canonical keys
- Query-time pipeline:
  1. provider fetch by `MobilityQuery.datasetSelection`
  2. merge records using `FlowMergeEngine` and `MergePolicy`
  3. temporal aggregation (hour/day/month rollup)
  4. spatial aggregation (nation/province/city/hub)
  5. ranking for map cap and insights top-N
- Conflict rules:
  - default: prefer higher reliability, then finer precision, then provider priority
  - preserve provenance in metadata (`dataSourceTag`, `confidenceScore`)

## 7. Dataset Versioning Strategy
- Continue per-dataset manifest model, add catalog index above manifests.
- Version dimensions:
  - `datasetVersion` (provider data version)
  - `schemaVersion` (Flow compatibility contract)
  - `snapshotVersion` (stored package identity/checksum)
- Compatibility gates:
  - hard fail on unsupported major schema
  - soft warn for additive optional fields
  - block activation for required-field regressions
- Keep current sample + Seoul snapshots as first catalog entries for backward compatibility.

## 8. API Ingestion Strategy
- Stage 1: keep snapshot-first runtime; add API fetch service that materializes validated snapshots locally.
- Stage 2: periodic refresh orchestration:
  - `DatasetRefreshScheduler`
  - `DatasetSyncService`
  - safe swap of active snapshot only after integrity + compatibility pass
- Stage 3: schema drift readiness:
  - compare API payload schema fingerprints vs expected
  - fallback to last known good snapshot on drift
  - log/operator-visible status in Settings

## 9. Development Roadmap
### Phase 1 — Architecture Extensions
- Add catalog/query/merge domain models.
- Add `CompositeMobilityRepository` interface and stub integration.
- Keep existing source switching path functional.

### Phase 2 — Nationwide Dataset Ingestion
- Implement `NationalBaselineMobilityDataSource` + repository.
- Add dataset catalog with sample, Seoul, national baseline entries.
- Add ingestion and compatibility tests.

### Phase 3 — Composite Repository
- Implement provider fan-in query and merge engine.
- Add provider precedence and reliability-based merge policy.
- Wire map and insights to query use case (not direct single repository).

### Phase 4 — Aggregation Engines
- Add spatial and temporal aggregation engines.
- Integrate with pre-aggregation and cache keys.
- Add performance and correctness tests for aggregation behavior.

### Phase 5 — API Ingestion Readiness
- Implement API adapters + snapshot materialization path.
- Add schema drift detector and fallback.
- Add refresh status visibility in Settings.

## 10. Risks and Mitigations
1. Dataset size explosion
- Risk: nationwide + modal overlays exceed memory/render budgets.
- Mitigation: pre-aggregation, viewport culling, capped segment rendering, snapshot chunking.

2. Map rendering performance degradation
- Risk: composite queries increase segment count and update frequency.
- Mitigation: keep existing diff overlay path, cache merged query slices, enforce caps by spatial level.

3. Schema drift across providers
- Risk: upstream fields change and break ingestion.
- Mitigation: schema validator + drift detector + last-known-good snapshot fallback.

4. Cross-dataset conflicts
- Risk: duplicate/overlapping flows produce inconsistent analytics.
- Mitigation: explicit merge policies, deterministic tie-break rules, provenance metadata retention.

5. Temporal/spatial precision mismatch
- Risk: mixing hourly and daily datasets causes misleading comparisons.
- Mitigation: precision metadata model and aggregation rules that require explicit rollup policy.
