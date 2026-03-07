## 1. Product Overview
**Flow** is an iOS-native mobility intelligence app that visualizes how people and goods move across South Korea by **road, rail, air, and maritime** networks.  
It combines an interactive map with time controls and mode filters so users can explore national-to-city movement patterns, compare corridors, and detect peaks or anomalies.

**Core user value**
- Understand mobility structure at a glance (where flow concentrates)
- Compare transport modes over time
- Support planning, research, and communication with visual evidence

---

## 2. User Personas and Use Cases

| Persona | Goals | Typical Use Cases |
|---|---|---|
| Transportation Analyst (Government/Agency) | Evaluate network demand and bottlenecks | Compare rail vs road flow in peak month; inspect corridor volumes by time of day |
| Urban/Regional Researcher | Study spatial-temporal mobility trends | Analyze seasonal movement patterns between metro and non-metro regions |
| Logistics Planner | Track goods movement corridors | Identify high-volume maritime-road handoff regions |
| Public/Media User | Understand national movement patterns | Explore “how Korea moves” by mode and year for storytelling |

---

## 3. Feature Breakdown

1. **Interactive Flow Map**
- OD (origin-destination) flow lines
- Zoom-aware rendering (national, regional, city)
- Heat/intensity overlays for high-volume zones

2. **Time Exploration**
- Year selector
- Month selector
- Time-of-day slider
- Playback animation through selected time buckets

3. **Transport Mode Filtering**
- Multi-select toggles: Road/Rail/Air/Maritime
- Combined mode analysis
- Always-visible legend with color and line style mapping

4. **Flow Detail Inspection**
- Tap a line/node to view route volume, mode, and time profile
- Corridor metadata (if available): corridor name, region type, confidence/source

5. **Insights Panel**
- Top corridors
- Volume distribution by mode
- Delta vs previous period (e.g., month-over-month)

---

## 4. App Screen Architecture

### A. Main Map Dashboard (Primary)
Contains:
- Full-screen Apple MapKit map
- Flow overlays (lines, animations, intensity)
- Bottom compact controls (time + mode summary)
- Legend chip and quick “reset filters”

### B. Time Control Panel (Bottom Sheet)
Contains:
- Year picker
- Month picker
- Time-of-day range/slider
- Playback controls (play/pause/speed/loop)

### C. Transport Mode Filter Panel (Bottom Sheet)
Contains:
- Four mode toggles with icons/colors
- Multi-select chips
- “Select all” / “Clear all”

### D. Flow Detail View (Sheet/Side Card)
Contains:
- Origin/destination names
- Volume, mode, selected time bucket
- Mini sparkline for time trend
- Metadata block (corridor, region type, source)

### E. Insights / Analytics Panel (Tab or Full Sheet)
Contains:
- Top N corridors
- Mode share chart
- Time distribution summary
- Optional comparison with baseline period

### F. Settings & Data Catalog
Contains:
- Dataset selection/version
- Visualization preferences (line thickness, animation intensity)
- Caching/storage controls

---

## 5. Navigation Flow

1. App launches to **Main Map Dashboard**.
2. User opens **Time Control Panel** to set temporal context.
3. User opens **Transport Mode Filter Panel** to refine modes.
4. Map updates live; user taps route/node to open **Flow Detail View**.
5. User opens **Insights Panel** for aggregate analytics of current filter/time scope.
6. Settings accessible from dashboard toolbar.

**Pattern**
- Primary navigation: `TabView` (Map, Insights, Settings)
- Contextual panels: draggable bottom sheets
- Detail interactions: modal sheet/card from map selection

---

## 6. System Architecture

### High-Level Layers

| Layer | Responsibility |
|---|---|
| UI Layer (SwiftUI) | Screens, controls, presentation state |
| ViewModel Layer | UI state orchestration, user intents, async loading |
| Domain Layer | Filtering logic, time slicing, aggregations |
| Data Layer | Local persistence, remote fetch, caching, dataset versioning |
| Map Rendering Layer | Convert flow domain objects into MapKit overlays/annotations |
| Filtering Engine | Apply mode, geography, and threshold filters |
| Time-Series Engine | Time bucketing, interpolation, playback stepping |

### Suggested architectural style
- **MVVM + Unidirectional Data Flow**
- `AppState` (selected time, selected modes, selected region, playback state)
- ViewModels subscribe to state changes and request derived datasets
- Rendering layer consumes derived, map-ready geometries

### Key modules
- `FlowUI` (views/components)
- `FlowDomain` (entities/use cases)
- `FlowData` (repositories/storage)
- `FlowMapRenderer` (overlay builders + style rules)

---

## 7. SwiftUI View Hierarchy

```text
FlowApp
└── RootTabView
    ├── MapDashboardView
    │   ├── MapContainerView (MapKit bridge)
    │   ├── FlowLegendView
    │   ├── QuickControlBar
    │   ├── TimeControlSheet
    │   ├── ModeFilterSheet
    │   └── FlowDetailCard (conditional)
    ├── InsightsView
    │   ├── SummaryHeader
    │   ├── TopCorridorsList
    │   ├── ModeShareChart
    │   └── TimeDistributionChart
    └── SettingsView
        ├── DatasetSettingsSection
        ├── VisualStyleSection
        └── CacheManagementSection
```

---

## 8. Data Model Design

### Core Entities

| Entity | Purpose | Example Fields |
|---|---|---|
| `FlowRecord` | One OD flow measurement in a time bucket | `id`, `originNodeID`, `destinationNodeID`, `transportMode`, `timeBucketID`, `volume`, `unitType`, `metadata` |
| `LocationNode` | Geographic node used as origin/destination | `id`, `nameKo`, `nameEn`, `lat`, `lon`, `regionCode`, `regionType` (nation/province/city/hub), `importanceRank` |
| `TransportMode` | Mobility mode taxonomy | enum: `road`, `rail`, `air`, `maritime` |
| `TimeBucket` | Standardized temporal key | `id`, `year`, `month`, `hourRange`, `granularity` |
| `FlowDataset` | Versioned collection and metadata | `datasetID`, `version`, `source`, `createdAt`, `spatialLevel`, `timeCoverage`, `recordsCount` |

### Optional metadata examples
- `corridorName`
- `isPassengerFlow` / `isFreightFlow`
- `confidenceScore`
- `dataSourceTag`

### Derived model (for rendering)
- `RenderableFlowSegment`: geometry polyline, normalized intensity, style token, animation phase seed

---

## 9. Map Visualization Strategy

1. **Flow Lines**
- Curved great-circle-like or bezier arcs for OD direction
- Width = scaled volume
- Color = transport mode
- Opacity/intensity = relative volume in current filter scope

2. **Direction & Motion**
- Animated particles or traveling dashes along line
- Playback syncs with time bucket changes

3. **Zoom-Aware Representation**
- National zoom: aggregated inter-region corridors only
- Regional zoom: more granular OD links
- City zoom: hub-to-hub and local concentration

4. **Heat/Intensity Layer**
- Node-based density heat map for origin/destination hotspots
- Toggle between line-centric and hotspot-centric view

5. **Legend and Perceptual Consistency**
- Stable color mapping per mode
- Visible scale reference for line width/volume bins

---

## 10. Performance Strategy

1. **Pre-Aggregation**
- Store precomputed aggregates by `timeBucket x mode x spatialLevel`
- Reduce runtime computation for common queries

2. **Spatial Indexing**
- Grid/quad-based partitioning for quick viewport filtering
- Render only visible + high-priority flows

3. **Level-of-Detail (LOD)**
- Switch datasets/geometry detail by zoom level
- Collapse minor flows into aggregated bundles at low zoom

4. **Async Pipeline**
- Background filtering and aggregation
- Main-thread-only final overlay updates

5. **Incremental Rendering**
- Diff-based overlay updates instead of full redraw
- Throttle rapid slider/playback updates

6. **Caching**
- Memory cache for recent filter states
- Disk cache for dataset chunks/versioned snapshots

---

## 11. Future Expansion

1. **Real-Time Mobility Data**
- Add streaming ingestion layer (WebSocket/HTTP polling)
- Separate `LiveFlowRecord` path merged with historical baseline
- UI mode for “Live + Historical comparison”

2. **International Expansion**
- Generalize region schema from KR-specific codes to global geo IDs
- Pluggable basemap/data source adapters by country
- Multi-language labels and unit localization

3. **Predictive Mobility Analytics**
- Add prediction service interface (`ForecastRepository`)
- Models for short-term volume forecasting by corridor/time bucket
- Visualize forecast confidence intervals as secondary overlays

---

## 12. Real-Data Provider Addendum (Seoul Capital Snapshot v1)

This addendum removes ambiguity for external dataset onboarding while preserving the existing nationwide architecture.

### 12.1 Provider Contract
- External providers must normalize into existing domain entities (`FlowDataset`, `LocationNode`, `FlowRecord`) before UI/view models consume data.
- Provider-specific parsing is isolated in `Data/DTOs`, `Data/Mappers`, and `Data/Sources`.
- Repositories exposed to features remain provider-agnostic (`FlowRepository`, `LocationRepository`).

### 12.2 First Real Source
- Source: Seoul/Capital-region mobility snapshot for 수도권 생활이동 OD data.
- Initial integration mode: bundled snapshot files (production-style ingestion path, no direct API dependency in app runtime yet).
- Snapshot resource contract:
  - `seoul_capital_manifest.json`
  - `seoul_capital_nodes.json`
  - `seoul_capital_flows.jsonl`

### 12.3 Transport Mode Normalization Rules

| External Mode Keywords | Internal Mode |
|---|---|
| `rail`, `train`, `subway`, `철도`, `기차`, `지하철` | `rail` |
| `air`, `항공` | `air` |
| `maritime`, `ship`, `ferry`, `선박`, `해운`, `여객선` | `maritime` |
| `vehicle`, `bus`, `express bus`, `metropolitan bus`, `local bus`, `walking`, `other`, unknown | `road` (fallback) |

Notes:
- This fallback policy is intentional for v1 to keep rendering/filter compatibility.
- Maritime may be absent in this dataset; zero-record mode states must remain valid.

### 12.4 Time Bucket Normalization
- External daily/hourly fields are normalized to canonical app buckets:
  - hourly: `H:YYYY-MM|HH`
- App timezone for bucket interpretation is local (`Asia/Seoul`) unless an explicit dataset timezone field is added later.

### 12.5 Source Switching
- App state includes selected dataset source (`bundledSample`, `seoulCapitalSnapshot`).
- Map and Insights must reload when source changes.
- Settings must expose source selection without changing feature-level architecture.

### 12.6 Validation and Compatibility Requirements
- Schema version validation is mandatory before ingestion.
- Invalid flow rules from data layer still apply (missing nodes, negative volume, self-loop OD drops).
- Existing features must work unchanged across both sources:
  - map overlays
  - time controls
  - mode filters
  - insights summaries

### 12.7 Change Control
- New providers must be added via the same DTO -> Mapper -> DataSource -> Repository path.
- Any deviation from this path requires a Design.md update before implementation.

## Suggested Non-Functional Defaults
- Architecture baseline: MVVM + repository + map renderer abstraction
- Data contract first: stable schemas for `FlowRecord` and `TimeBucket`
- Visual priority: clarity at national scale, fidelity at local scale

---

## 12. Implementation Addendum (Canonical Decisions)

This addendum is implementation-binding and resolves all previously ambiguous areas.

### 12.1 Data Source Contract and Units

#### Dataset packaging
- A dataset version is shipped or downloaded as:
  - `nodes.json` (`LocationNode[]`)
  - `flows.jsonl` (newline-delimited `FlowRecord`)
  - `dataset_manifest.json` (`FlowDataset` + schema/version metadata)
- `schemaVersion` is required in `dataset_manifest.json`.
- Initial supported schema version: `1.0.0`.

#### Volume semantics
- `FlowRecord.volume` is always a non-negative numeric value.
- `FlowRecord.unitType` is required and must be one of:
  - `passengers`
  - `tons`
  - `vehicles`
- Mixing units in a single visual layer is not allowed.
- If current filter scope contains mixed `unitType`, the app must:
  1. Split internally by unit type.
  2. Default-render the dominant unit type by record count.
  3. Show a unit warning badge in legend (`Mixed units: showing <unitType>`).

#### Required and optional `FlowRecord` fields
- Required:
  - `id: String`
  - `originNodeID: String`
  - `destinationNodeID: String`
  - `transportMode: TransportMode`
  - `timeBucketID: String`
  - `volume: Double`
  - `unitType: String`
- Optional:
  - `metadata.corridorName: String`
  - `metadata.regionType: String`
  - `metadata.isPassengerFlow: Bool`
  - `metadata.isFreightFlow: Bool`
  - `metadata.confidenceScore: Double` (`0.0...1.0`)
  - `metadata.dataSourceTag: String`

#### Validation rules
- Drop records where:
  - `originNodeID == destinationNodeID`
  - referenced node IDs do not exist
  - `volume < 0`
- Keep records with missing optional metadata.

### 12.2 Time Bucket Normalization

#### Canonical timezone
- All persisted dataset timestamps and bucket definitions use `Asia/Seoul` (KST, UTC+09:00).
- UI never converts to UTC for user display.

#### Canonical granularity
- Supported granularities:
  - `year`
  - `month`
  - `hour_of_day`
- `TimeBucket.id` format:
  - Year: `Y:2025`
  - Month: `M:2025-08`
  - Hour: `H:2025-08|14`

#### Hour representation
- Hour is integer `0...23`.
- Bucket interval is half-open: `[hour:00, hour+1:00)`.
- Playback step unit for intra-day animation is 1 hour.

#### Missing buckets
- Missing time buckets are treated as `volume = 0` (no interpolation in v1).

### 12.3 Spatial Level Definitions

#### Canonical `spatialLevel` values
- `national`
- `province` (si/do scale)
- `city` (si/gun/gu scale)
- `hub` (station/airport/port/major terminal scale)

#### Region code policy
- `LocationNode.regionCode` is required and must map to one of:
  - administrative code for `province`/`city`
  - stable hub code for `hub`
  - `KR` for national aggregate

#### Zoom-to-level mapping (MapKit zoom approximation by visible latitude delta)
- `national`: latitudeDelta `>= 2.5`
- `province`: `>= 0.8` and `< 2.5`
- `city`: `>= 0.15` and `< 0.8`
- `hub`: `< 0.15`

#### Aggregation keys by level
- `national`: `(originProvince, destinationProvince, mode, timeBucket, unitType)`
- `province`: `(originCity, destinationCity, mode, timeBucket, unitType)`
- `city`: `(originNode, destinationNode, mode, timeBucket, unitType)`
- `hub`: raw node-to-node records

### 12.4 Visualization Thresholds and Styling

#### Transport mode style tokens
- Road: `#2563EB` (blue), solid line
- Rail: `#DC2626` (red), dashed line
- Air: `#0891B2` (cyan), dotted-dash line
- Maritime: `#0F766E` (teal), long-dash line

#### Width and opacity scaling
- Compute percentile ranks on current filtered set (`p10`, `p50`, `p90`).
- Line width:
  - `<= p10`: `1.0`
  - `p10...p50`: linear `1.0 -> 2.5`
  - `p50...p90`: linear `2.5 -> 5.0`
  - `> p90`: `6.0`
- Opacity:
  - min `0.20`, max `0.90`, linear by normalized volume.

#### Visibility threshold
- Do not render segments where normalized volume `< 0.03`.
- Always retain top 150 segments by absolute volume even if below threshold.

#### Accessibility
- Legend must always display mode color and line pattern together (color is not sole cue).
- Minimum contrast ratio target for legend text: `4.5:1`.

### 12.5 Performance Budgets and Limits

#### Interaction budgets (target on iPhone 15-class device)
- Pan/zoom frame budget: `<= 16.7ms` average (60fps target).
- Filter apply latency (mode/time change to visible update): `<= 200ms` p95.
- Time playback tick update latency: `<= 120ms` p95.
- Initial dataset load from local cache (100k flow records): `<= 2.0s`.

#### Rendering limits
- Max concurrently rendered line segments by level:
  - national: `1,200`
  - province: `2,000`
  - city/hub: `3,000`
- Above limit, renderer must keep highest-volume segments and defer remainder.

#### Caching policy
- In-memory cache budget: `120 MB` hard cap.
- Disk cache budget: `500 MB` soft cap, LRU eviction.
- Cache key dimensions:
  - `datasetVersion`
  - `spatialLevel`
  - `timeBucketID`
  - `modeSet`
  - `unitType`

### 12.6 Selection and Interaction Behavior

#### Hit testing and overlap resolution
- Tap selects nearest rendered segment within `24pt` hit radius.
- If multiple segments match:
  1. Highest `volume` wins.
  2. If tied, shortest screen distance to tap wins.
  3. If still tied, deterministic lexical order by `id`.

#### Selection persistence
- Selection persists across map pan/zoom if selected segment remains in rendered set.
- Selection clears automatically when:
  - segment no longer exists after filter/time change
  - user taps empty map area
  - user presses explicit clear action in detail card

#### Detail card behavior
- Detail card opens on selection and updates live during playback if selected segment remains valid.
- If selection becomes invalid during playback, card dismisses with no error.

### 12.7 Versioning and Change Control

- This section (`12. Implementation Addendum`) is the canonical implementation contract for v1.
- Any future architectural change that affects data contract, thresholds, or behavior must update this section first, then implementation.
