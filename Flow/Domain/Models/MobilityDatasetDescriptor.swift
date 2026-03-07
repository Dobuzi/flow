import Foundation

struct MobilityDatasetDescriptor: Codable, Hashable, Identifiable {
    enum Reliability: String, Codable, Hashable {
        case high
        case medium
        case low
        case unknown
    }

    enum SpatialPrecision: String, Codable, Hashable {
        case national
        case province
        case city
        case district
        case unknown
    }

    enum TemporalPrecision: String, Codable, Hashable {
        case year
        case month
        case day
        case hour
        case unknown
    }

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
    let reliability: Reliability
    let spatialPrecision: SpatialPrecision
    let temporalPrecision: TemporalPrecision
    let qualityScore: Double?
}
