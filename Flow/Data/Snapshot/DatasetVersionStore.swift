import Foundation

struct StoredSnapshotVersion: Hashable {
    let snapshotID: String
    let source: FlowDatasetSource
    let datasetVersion: String
    let generatedAt: String
    let schemaVersion: String
    let timeCoverage: String
    let spatialCoverage: SpatialLevel
    let recordsCount: Int
    let activationEligibility: SnapshotActivationEligibility
    let compatibilityClassification: IngestionCompatibilityClassification
    let compatibilityReasons: [String]
    let isIngestionCandidate: Bool
    let indexedAt: String
    let contract: MaterializedSnapshotContract

    static func from(
        contract: MaterializedSnapshotContract,
        compatibilityClassification: IngestionCompatibilityClassification,
        isIngestionCandidate: Bool,
        indexedAt: String
    ) -> StoredSnapshotVersion {
        StoredSnapshotVersion(
            snapshotID: contract.snapshotID,
            source: contract.source,
            datasetVersion: contract.datasetVersion,
            generatedAt: contract.generatedAt,
            schemaVersion: contract.schemaVersion,
            timeCoverage: contract.timeCoverage,
            spatialCoverage: contract.spatialCoverage,
            recordsCount: contract.recordsCount,
            activationEligibility: contract.activationEligibility,
            compatibilityClassification: compatibilityClassification,
            compatibilityReasons: contract.compatibility.compatibilityReasons + contract.activationEligibility.reasons,
            isIngestionCandidate: isIngestionCandidate,
            indexedAt: indexedAt,
            contract: contract
        )
    }
}

struct DatasetManifestIndex: Hashable {
    let entries: [StoredSnapshotVersion]

    func versions(for source: FlowDatasetSource) -> [StoredSnapshotVersion] {
        sorted(entries.filter { $0.source == source })
    }

    func latest(for source: FlowDatasetSource) -> StoredSnapshotVersion? {
        versions(for: source).first
    }

    func snapshot(snapshotID: String) -> StoredSnapshotVersion? {
        entries.first { $0.snapshotID == snapshotID }
    }

    func snapshot(source: FlowDatasetSource, datasetVersion: String) -> StoredSnapshotVersion? {
        entries.first { $0.source == source && $0.datasetVersion == datasetVersion }
    }

    func ingestionCandidates(for source: FlowDatasetSource) -> [StoredSnapshotVersion] {
        versions(for: source).filter(\.isIngestionCandidate)
    }

    private func sorted(_ items: [StoredSnapshotVersion]) -> [StoredSnapshotVersion] {
        items.sorted { lhs, rhs in
            let leftDate = parseDate(lhs.generatedAt)
            let rightDate = parseDate(rhs.generatedAt)
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            if lhs.datasetVersion != rhs.datasetVersion {
                return lhs.datasetVersion > rhs.datasetVersion
            }
            return lhs.snapshotID > rhs.snapshotID
        }
    }

    private func parseDate(_ value: String) -> Date {
        if let date = Self.iso8601WithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = Self.iso8601.date(from: value) {
            return date
        }
        return .distantPast
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

protocol DatasetVersionStoring {
    func upsert(
        contract: MaterializedSnapshotContract,
        compatibilityClassification: IngestionCompatibilityClassification,
        isIngestionCandidate: Bool,
        indexedAt: String
    ) async

    func index() async -> DatasetManifestIndex
    func versions(for source: FlowDatasetSource) async -> [StoredSnapshotVersion]
    func latest(for source: FlowDatasetSource) async -> StoredSnapshotVersion?
    func snapshot(snapshotID: String) async -> StoredSnapshotVersion?
    func snapshot(source: FlowDatasetSource, datasetVersion: String) async -> StoredSnapshotVersion?
}

actor InMemoryDatasetVersionStore: DatasetVersionStoring {
    private var entriesBySnapshotID: [String: StoredSnapshotVersion] = [:]

    func upsert(
        contract: MaterializedSnapshotContract,
        compatibilityClassification: IngestionCompatibilityClassification,
        isIngestionCandidate: Bool = true,
        indexedAt: String = ISO8601DateFormatter().string(from: Date())
    ) async {
        let entry = StoredSnapshotVersion.from(
            contract: contract,
            compatibilityClassification: compatibilityClassification,
            isIngestionCandidate: isIngestionCandidate,
            indexedAt: indexedAt
        )
        entriesBySnapshotID[entry.snapshotID] = entry
    }

    func index() async -> DatasetManifestIndex {
        DatasetManifestIndex(entries: Array(entriesBySnapshotID.values))
    }

    func versions(for source: FlowDatasetSource) async -> [StoredSnapshotVersion] {
        await index().versions(for: source)
    }

    func latest(for source: FlowDatasetSource) async -> StoredSnapshotVersion? {
        await index().latest(for: source)
    }

    func snapshot(snapshotID: String) async -> StoredSnapshotVersion? {
        entriesBySnapshotID[snapshotID]
    }

    func snapshot(source: FlowDatasetSource, datasetVersion: String) async -> StoredSnapshotVersion? {
        await index().snapshot(source: source, datasetVersion: datasetVersion)
    }
}
