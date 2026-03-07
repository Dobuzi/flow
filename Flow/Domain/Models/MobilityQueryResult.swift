import Foundation

struct MobilityQueryResult: Hashable {
    let query: MobilityQuery
    let datasetIDs: [String]
    let sources: Set<FlowDatasetSource>
    let nodes: [LocationNode]
    let flows: [FlowRecord]
    let generatedAt: Date
    let compatibilityNotes: [String]

    static func singleSource(
        query: MobilityQuery,
        dataset: FlowDataset,
        source: FlowDatasetSource,
        nodes: [LocationNode],
        flows: [FlowRecord],
        compatibilityNotes: [String] = [],
        generatedAt: Date = Date()
    ) -> MobilityQueryResult {
        MobilityQueryResult(
            query: query,
            datasetIDs: [dataset.datasetID],
            sources: [source],
            nodes: nodes,
            flows: flows,
            generatedAt: generatedAt,
            compatibilityNotes: compatibilityNotes
        )
    }
}
