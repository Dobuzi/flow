import Foundation

struct MobilityDatasetCatalog: Codable, Hashable {
    let version: String
    let defaultSource: FlowDatasetSource
    let datasets: [MobilityDatasetDescriptor]

    func descriptor(for source: FlowDatasetSource) -> MobilityDatasetDescriptor? {
        datasets.first(where: { $0.source == source })
    }
}
