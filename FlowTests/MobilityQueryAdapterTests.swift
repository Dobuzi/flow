import Testing
@testable import Flow

private struct StubActivatedSnapshotResolver: ActivatedSnapshotResolving {
    let resolution: ActivatedSnapshotResolution

    func resolve(for source: FlowDatasetSource) async -> ActivatedSnapshotResolution {
        resolution
    }
}

struct MobilityQueryAdapterTests {
    @Test
    func returnsSingleSourceQueryResult() async throws {
        var query = MobilityQuery.default
        query = MobilityQuery(
            sources: [.bundledSample],
            selectedModes: Set(TransportMode.allCases),
            spatialLevel: query.spatialLevel,
            timeContext: query.timeContext,
            aggregation: query.aggregation
        )

        let adapter = DefaultMobilityQueryAdapter()
        let result = try await adapter.execute(query)

        #expect(result.sources == Set([FlowDatasetSource.bundledSample]))
        #expect(result.datasetIDs.count == 1)
        #expect(!result.nodes.isEmpty)
        #expect(!result.flows.isEmpty)
        #expect(result.compatibilityNotes == ["compatible"])
    }

    @Test
    func appliesModeFilteringOnQueryResult() async throws {
        let query = MobilityQuery(
            sources: [.bundledSample],
            selectedModes: [.road],
            spatialLevel: .national,
            timeContext: MobilityTimeContext(year: 2025, month: 1, hour: 12, granularity: .hourOfDay),
            aggregation: .default
        )

        let adapter = DefaultMobilityQueryAdapter()
        let result = try await adapter.execute(query)

        #expect(!result.flows.isEmpty)
        #expect(result.flows.allSatisfy { $0.transportMode == .road })
    }

    @Test
    func koreaNationalQueryAppliesTimeModeAndSpatialShaping() async throws {
        let query = MobilityQuery(
            sources: [.koreaNational],
            selectedModes: [.road],
            spatialLevel: .national,
            timeContext: MobilityTimeContext(year: 2025, month: 1, hour: 8, granularity: .hourOfDay),
            aggregation: .default
        )

        let adapter = DefaultMobilityQueryAdapter()
        let result = try await adapter.execute(query)

        #expect(!result.flows.isEmpty)
        #expect(result.flows.allSatisfy { $0.transportMode == .road })
        #expect(result.flows.allSatisfy { $0.timeBucketID == "H:2025-01|08" })
        #expect(result.flows.allSatisfy { $0.metadata?.regionType == SpatialLevel.province.rawValue })
    }

    @Test
    func koreaNationalQueryFallsBackToMonthBucketWhenHourMissing() async throws {
        let query = MobilityQuery(
            sources: [.koreaNational],
            selectedModes: [.rail],
            spatialLevel: .national,
            timeContext: MobilityTimeContext(year: 2025, month: 1, hour: 7, granularity: .hourOfDay),
            aggregation: .default
        )

        let adapter = DefaultMobilityQueryAdapter()
        let result = try await adapter.execute(query)

        #expect(!result.flows.isEmpty)
        #expect(result.flows.allSatisfy { $0.transportMode == .rail })
        #expect(result.flows.allSatisfy { $0.timeBucketID == "M:2025-01" })
    }

    @Test
    func includesActivationResolutionNotesForLiveSources() async throws {
        let resolution = ActivatedSnapshotResolution(
            source: .seoulCapitalSnapshot,
            isLiveCapable: true,
            activatedSnapshotID: "seoul-2026.03",
            activatedDatasetVersion: "2026.03",
            compatibilityClassification: .compatible,
            isUsingActivatedSnapshot: true,
            fallbackReason: nil
        )

        let query = MobilityQuery(
            sources: [.seoulCapitalSnapshot],
            selectedModes: Set(TransportMode.allCases),
            spatialLevel: .city,
            timeContext: MobilityTimeContext(year: 2025, month: 1, hour: 8, granularity: .hourOfDay),
            aggregation: .default
        )

        let adapter = DefaultMobilityQueryAdapter(
            flowRepositoryBuilder: { source, _ in
                MobilityRepositoryFactory.flowRepository(for: source)
            },
            locationRepositoryBuilder: { source, _ in
                MobilityRepositoryFactory.locationRepository(for: source)
            },
            activatedSnapshotResolver: StubActivatedSnapshotResolver(resolution: resolution)
        )

        let result = try await adapter.execute(query)

        #expect(result.compatibilityNotes.contains("activation_snapshot_id:seoul-2026.03"))
        #expect(result.compatibilityNotes.contains("activation_dataset_version:2026.03"))
        #expect(result.compatibilityNotes.contains("runtime_dataset_version:2025.01.snapshot1"))
        #expect(result.compatibilityNotes.contains("activation_runtime_mismatch_fallback_static"))
    }
}
