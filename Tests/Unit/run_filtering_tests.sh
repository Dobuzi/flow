#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

OUT="/tmp/flow_filtering_tests"

SOURCES=(
  Flow/Domain/Models/TransportMode.swift
  Flow/Domain/Models/FlowRecord.swift
  Flow/Domain/Models/LocationNode.swift
  Flow/Domain/Engines/FilteringEngine.swift
  Flow/Tests/Unit/Domain/FilteringEngineTests.swift
  Flow/Tests/Unit/Domain/FilteringTestMain.swift
)

xcrun swiftc "${SOURCES[@]}" -o "$OUT"
"$OUT"
