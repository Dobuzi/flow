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

enum DatasetRefreshOutcome: String, Codable, Hashable {
    case success
    case skipped
    case failed
}

struct DatasetLiveMetadata: Codable, Hashable {
    let supportsLiveRefresh: Bool
    let latestKnownDatasetVersion: String?
    let latestKnownSnapshotID: String?
    let lastRefreshAttemptAt: String?
    let lastSuccessfulRefreshAt: String?
    let lastRefreshFailedAt: String?
    let lastRefreshTrigger: DatasetRefreshTrigger?
    let lastRefreshOutcome: DatasetRefreshOutcome?
    let lastRefreshFailureReason: String?
    let latestCandidateSnapshotID: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
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
        case lastRefreshFailedAt = "last_refresh_failed_at"
        case lastRefreshTrigger = "last_refresh_trigger"
        case lastRefreshOutcome = "last_refresh_outcome"
        case lastRefreshFailureReason = "last_refresh_failure_reason"
        case latestCandidateSnapshotID = "latest_candidate_snapshot_id"
        case latestCandidateCompatibility = "latest_candidate_compatibility"
        case latestCandidateEligibleForActivation = "latest_candidate_eligible_for_activation"
        case activeSnapshotID = "active_snapshot_id"
        case lastKnownGoodSnapshotID = "last_known_good_snapshot_id"
        case readiness
        case syncState = "sync_state"
    }

    init(
        supportsLiveRefresh: Bool,
        latestKnownDatasetVersion: String?,
        latestKnownSnapshotID: String?,
        lastRefreshAttemptAt: String?,
        lastSuccessfulRefreshAt: String?,
        lastRefreshFailedAt: String? = nil,
        lastRefreshTrigger: DatasetRefreshTrigger? = nil,
        lastRefreshOutcome: DatasetRefreshOutcome? = nil,
        lastRefreshFailureReason: String? = nil,
        latestCandidateSnapshotID: String? = nil,
        latestCandidateCompatibility: IngestionCompatibilityClassification? = nil,
        latestCandidateEligibleForActivation: Bool? = nil,
        activeSnapshotID: String?,
        lastKnownGoodSnapshotID: String?,
        readiness: DatasetRefreshReadiness,
        syncState: DatasetSyncState
    ) {
        self.supportsLiveRefresh = supportsLiveRefresh
        self.latestKnownDatasetVersion = latestKnownDatasetVersion
        self.latestKnownSnapshotID = latestKnownSnapshotID
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastRefreshFailedAt = lastRefreshFailedAt
        self.lastRefreshTrigger = lastRefreshTrigger
        self.lastRefreshOutcome = lastRefreshOutcome
        self.lastRefreshFailureReason = lastRefreshFailureReason
        self.latestCandidateSnapshotID = latestCandidateSnapshotID
        self.latestCandidateCompatibility = latestCandidateCompatibility
        self.latestCandidateEligibleForActivation = latestCandidateEligibleForActivation
        self.activeSnapshotID = activeSnapshotID
        self.lastKnownGoodSnapshotID = lastKnownGoodSnapshotID
        self.readiness = readiness
        self.syncState = syncState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsLiveRefresh = try container.decode(Bool.self, forKey: .supportsLiveRefresh)
        latestKnownDatasetVersion = try container.decodeIfPresent(String.self, forKey: .latestKnownDatasetVersion)
        latestKnownSnapshotID = try container.decodeIfPresent(String.self, forKey: .latestKnownSnapshotID)
        lastRefreshAttemptAt = try container.decodeIfPresent(String.self, forKey: .lastRefreshAttemptAt)
        lastSuccessfulRefreshAt = try container.decodeIfPresent(String.self, forKey: .lastSuccessfulRefreshAt)
        lastRefreshFailedAt = try container.decodeIfPresent(String.self, forKey: .lastRefreshFailedAt)
        lastRefreshTrigger = try container.decodeIfPresent(DatasetRefreshTrigger.self, forKey: .lastRefreshTrigger)
        lastRefreshOutcome = try container.decodeIfPresent(DatasetRefreshOutcome.self, forKey: .lastRefreshOutcome)
        lastRefreshFailureReason = try container.decodeIfPresent(String.self, forKey: .lastRefreshFailureReason)
        latestCandidateSnapshotID = try container.decodeIfPresent(String.self, forKey: .latestCandidateSnapshotID)
        latestCandidateCompatibility = try container.decodeIfPresent(IngestionCompatibilityClassification.self, forKey: .latestCandidateCompatibility)
        latestCandidateEligibleForActivation = try container.decodeIfPresent(Bool.self, forKey: .latestCandidateEligibleForActivation)
        activeSnapshotID = try container.decodeIfPresent(String.self, forKey: .activeSnapshotID)
        lastKnownGoodSnapshotID = try container.decodeIfPresent(String.self, forKey: .lastKnownGoodSnapshotID)
        readiness = try container.decode(DatasetRefreshReadiness.self, forKey: .readiness)
        syncState = try container.decode(DatasetSyncState.self, forKey: .syncState)
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
