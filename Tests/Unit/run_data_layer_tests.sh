#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

OUT="/tmp/flow_data_layer_tests"

COMMON_SOURCES=(
  Flow/Core/Logging/FlowLogger.swift
  Flow/Domain/Models/TransportMode.swift
  Flow/Domain/Models/SpatialLevel.swift
  Flow/Domain/Models/FlowRecord.swift
  Flow/Domain/Models/LocationNode.swift
  Flow/Domain/Models/TimeBucket.swift
  Flow/Domain/Models/FlowDataset.swift
  Flow/Data/Sources/FlowDataSource.swift
  Flow/Data/Sources/LocalJSONDataSource.swift
  Flow/Data/Repositories/FlowRepository.swift
  Flow/Data/Repositories/LocalFlowRepository.swift
)

TEST_SOURCES=(
  Flow/Tests/Unit/Data/DataLayerTests.swift
  Flow/Tests/Unit/Data/TestMain.swift
)

xcrun swiftc \
  "${COMMON_SOURCES[@]}" \
  "${TEST_SOURCES[@]}" \
  -o "$OUT"

"$OUT"
