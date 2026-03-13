# Korea National Baseline Snapshot Contract

Contract version: `1.0.0`
Encoding: `UTF-8`

This folder defines the bundled snapshot contract used by `FlowDatasetSource.koreaNational`.

## Required Files
1. `korea_national_manifest.json`
2. `korea_national_nodes.json`
3. `korea_national_flows.jsonl`

## File Semantics
- `korea_national_manifest.json`: dataset-level metadata and compatibility fields.
- `korea_national_nodes.json`: normalized geographic nodes for origins/destinations.
- `korea_national_flows.jsonl`: one canonical flow record per line (newline-delimited JSON).

## Manifest Required Fields (`korea_national_manifest.json`)
- `datasetId` (string)
- `version` (string)
- `source` (string, expected `korea_national`)
- `generatedAt` (ISO-8601 string)
- `coverageStart` (ISO-8601 date string)
- `coverageEnd` (ISO-8601 date string)
- `schemaVersion` (string)
- `spatialLevel` (string)

## Node Required Fields (`korea_national_nodes.json`)
Each item must include:
- `nodeId` (string)
- `nameKo` (string)
- `lat` (number)
- `lon` (number)
- `regionCode` (string)
- `regionType` (string; `national|province|city|hub`)

Optional:
- `nameEn` (string)
- `importanceRank` (integer)

## Flow Required Fields (`korea_national_flows.jsonl`)
Each line must include:
- `id` (string)
- `originNodeId` (string)
- `destinationNodeId` (string)
- `transportMode` (string; normalized to `road|rail|air|maritime`)
- `timeBucketId` (string; canonical bucket format)
- `volume` (number, non-negative)
- `unitType` (string)

Optional metadata object fields:
- `corridorName`
- `regionType`
- `isPassengerFlow`
- `isFreightFlow`
- `confidenceScore`
- `dataSourceTag`

## Time Bucket Policy
- Canonical bucket IDs must align with existing app engine formats:
  - Year: `Y:YYYY`
  - Month: `M:YYYY-MM`
  - Hour: `H:YYYY-MM|HH`
- Timezone policy: `Asia/Seoul`.

## Validation Notes
- `schemaVersion` must be accepted by current `DatasetSchemaValidator` policy.
- Missing required fields should produce compatibility failure, not crash.
- Invalid lines in JSONL should be rejected safely with diagnostics.

## Activation Rule
National source should remain safely non-fatal when required files are absent or incompatible.
