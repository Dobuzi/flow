#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

OUT="/tmp/flow_time_series_tests"

SOURCES=(
  Flow/Domain/Models/TransportMode.swift
  Flow/Domain/Models/SpatialLevel.swift
  Flow/Domain/Models/FlowRecord.swift
  Flow/Domain/Models/FlowDataset.swift
  Flow/Domain/Models/TimeBucket.swift
  Flow/Domain/Engines/TimeSeriesEngine.swift
  Flow/Tests/Unit/Domain/TimeSeriesEngineTests.swift
  Flow/Tests/Unit/Domain/TimeSeriesTestMain.swift
)

xcrun swiftc "${SOURCES[@]}" -o "$OUT"
"$OUT"
