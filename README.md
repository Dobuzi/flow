# Flow

South Korea mobility flow visualization app built with **Swift + SwiftUI + MapKit**.

Flow visualizes origin-destination mobility for four transport modes:
- Road
- Rail
- Air
- Maritime

It supports time-based exploration (year/month/hour), mode filtering, map-based flow inspection, and insights summaries.

## Source of Truth
- Architecture: [Design.md](/Users/jw/Dev/codex/flow/Design.md)
- Roadmap: [ImplementationPlan.md](/Users/jw/Dev/codex/flow/ImplementationPlan.md)
- Task tracking: [Tasks.md](/Users/jw/Dev/codex/flow/Tasks.md)

## Current Status
All tasks in `Tasks.md` are marked complete, including:
- App skeleton and tab navigation
- Data ingest/validation/repository layer
- Map rendering + selection + detail card
- Time controls + mode filtering
- Insights and settings surfaces
- Cache/pre-aggregation/performance instrumentation
- Integration/unit/UI test pass and final QA baseline

## Tech Stack
- iOS Native (SwiftUI)
- Apple MapKit
- MVVM + unidirectional state flow (`AppState` / `AppStore`)
- Local sample dataset (`Resources/SampleData`)

## Project Structure

```text
/Users/jw/Dev/codex/flow
├── Flow.xcodeproj
├── Flow
│   ├── App
│   ├── Core
│   ├── Data
│   ├── Domain
│   ├── Features
│   ├── Visualization
│   ├── Resources
│   └── Assets.xcassets
├── FlowTests
├── FlowUITests
└── Tests
```

## Run (Xcode)
1. Open [Flow.xcodeproj](/Users/jw/Dev/codex/flow/Flow.xcodeproj)
2. Select scheme: `Flow`
3. Choose an iPhone simulator
4. Run

## Run (CLI)

Build:
```bash
xcodebuild -scheme Flow \
  -project /Users/jw/Dev/codex/flow/Flow.xcodeproj \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/flow-derived \
  build
```

Test (unit + integration + UI tests in Xcode test targets):
```bash
xcodebuild -scheme Flow \
  -project /Users/jw/Dev/codex/flow/Flow.xcodeproj \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/flow-derived \
  -only-testing:FlowTests \
  -only-testing:FlowUITests \
  test
```

Optional lightweight script-based unit tests:
```bash
/Users/jw/Dev/codex/flow/Tests/Unit/run_data_layer_tests.sh
/Users/jw/Dev/codex/flow/Tests/Unit/run_filtering_tests.sh
/Users/jw/Dev/codex/flow/Tests/Unit/run_time_series_tests.sh
```

## Sample Data
- [dataset_manifest.json](/Users/jw/Dev/codex/flow/Flow/Resources/SampleData/dataset_manifest.json)
- [nodes.json](/Users/jw/Dev/codex/flow/Flow/Resources/SampleData/nodes.json)
- [flows.jsonl](/Users/jw/Dev/codex/flow/Flow/Resources/SampleData/flows.jsonl)

## Notes
- App currently uses bundled local sample data.
- Keep architectural changes aligned with `Design.md`.
- If architecture changes are needed, update `Design.md` first, then implement.
