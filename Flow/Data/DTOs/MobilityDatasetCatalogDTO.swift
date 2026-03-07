import Foundation

struct MobilityDatasetCatalogDTO: Decodable {
    let version: String
    let defaultSource: FlowDatasetSource
    let datasets: [MobilityDatasetDescriptorDTO]

    enum CodingKeys: String, CodingKey {
        case version
        case defaultSource = "default_source"
        case datasets
    }
}

struct MobilityDatasetDescriptorDTO: Decodable {
    let id: String
    let datasetID: String
    let source: FlowDatasetSource
    let providerID: String
    let displayName: String
    let version: String
    let schemaVersion: String
    let updatedAt: String
    let availableModes: [TransportMode]
    let supportedSpatialLevels: [SpatialLevel]
    let supportedGranularities: [TimeBucket.Granularity]
    let reliability: MobilityDatasetDescriptor.Reliability
    let spatialPrecision: MobilityDatasetDescriptor.SpatialPrecision
    let temporalPrecision: MobilityDatasetDescriptor.TemporalPrecision
    let qualityScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case datasetID = "dataset_id"
        case source
        case providerID = "provider_id"
        case displayName = "display_name"
        case version
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case availableModes = "available_modes"
        case supportedSpatialLevels = "supported_spatial_levels"
        case supportedGranularities = "supported_granularities"
        case reliability
        case spatialPrecision = "spatial_precision"
        case temporalPrecision = "temporal_precision"
        case qualityScore = "quality_score"
    }
}
