import Testing
@testable import Flow

struct MobilityQueryResultTests {
    @Test
    func wrapsSingleSourceRepositoryOutput() {
        let query = MobilityQuery.default
        let dataset = FlowDataset(
            datasetID: "sample-dataset",
            version: "1.0.0",
            source: "sample",
            createdAt: "2026-03-07T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2025-01",
            recordsCount: 1,
            schemaVersion: "1.0.0"
        )

        let nodes = [
            LocationNode(id: "n1", nameKo: "A", nameEn: nil, lat: 37.5, lon: 127.0, regionCode: "11", regionType: "city", importanceRank: nil),
            LocationNode(id: "n2", nameKo: "B", nameEn: nil, lat: 37.6, lon: 127.1, regionCode: "11", regionType: "city", importanceRank: nil)
        ]

        let flows = [
            FlowRecord(
                id: "f1",
                originNodeID: "n1",
                destinationNodeID: "n2",
                transportMode: .road,
                timeBucketID: "H:2025-01|12",
                volume: 100,
                unitType: .passengers,
                metadata: .init(corridorName: nil, regionType: nil, isPassengerFlow: true, isFreightFlow: false, confidenceScore: nil, dataSourceTag: nil)
            )
        ]

        let result = MobilityQueryResult.singleSource(
            query: query,
            dataset: dataset,
            source: .bundledSample,
            nodes: nodes,
            flows: flows,
            compatibilityNotes: ["compatible"]
        )

        #expect(result.datasetIDs == ["sample-dataset"])
        #expect(result.sources == Set([FlowDatasetSource.bundledSample]))
        #expect(result.nodes.count == 2)
        #expect(result.flows.count == 1)
        #expect(result.compatibilityNotes == ["compatible"])
    }
}
