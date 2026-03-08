import Foundation

enum DatasetRefreshReadiness: String, Codable, Hashable {
    case staticOnly = "static_only"
    case ready
    case pendingValidation = "pending_validation"
    case blocked
}

enum DatasetSyncState: String, Codable, Hashable {
    case idle
    case ready
    case degraded
    case failed
}

struct DatasetLiveMetadata: Codable, Hashable {
    let supportsLiveRefresh: Bool
    let latestKnownDatasetVersion: String?
    let latestKnownSnapshotID: String?
    let lastRefreshAttemptAt: String?
    let lastSuccessfulRefreshAt: String?
    let activeSnapshotID: String?
    let lastKnownGoodSnapshotID: String?
    let readiness: DatasetRefreshReadiness
    let syncState: DatasetSyncState

    enum CodingKeys: String, CodingKey {
        case supportsLiveRefresh = "supports_live_refresh"
        case latestKnownDatasetVersion = "latest_known_dataset_version"
        case latestKnownSnapshotID = "latest_known_snapshot_id"
        case lastRefreshAttemptAt = "last_refresh_attempt_at"
        case lastSuccessfulRefreshAt = "last_successful_refresh_at"
        case activeSnapshotID = "active_snapshot_id"
        case lastKnownGoodSnapshotID = "last_known_good_snapshot_id"
        case readiness
        case syncState = "sync_state"
    }
}

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
    let liveMetadata: DatasetLiveMetadata?

    func withLiveMetadata(_ liveMetadata: DatasetLiveMetadata?) -> MobilityDatasetDescriptor {
        MobilityDatasetDescriptor(
            id: id,
            datasetID: datasetID,
            source: source,
            providerID: providerID,
            displayName: displayName,
            version: version,
            schemaVersion: schemaVersion,
            updatedAt: updatedAt,
            availableModes: availableModes,
            supportedSpatialLevels: supportedSpatialLevels,
            supportedGranularities: supportedGranularities,
            reliability: reliability,
            spatialPrecision: spatialPrecision,
            temporalPrecision: temporalPrecision,
            qualityScore: qualityScore,
            liveMetadata: liveMetadata
        )
    }
}
