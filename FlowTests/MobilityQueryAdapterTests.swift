import Testing
@testable import Flow

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
}
