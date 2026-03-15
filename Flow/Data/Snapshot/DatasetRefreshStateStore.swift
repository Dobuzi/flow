import Foundation

struct DatasetRefreshState: Codable, Hashable {
    let source: FlowDatasetSource
    let lastRefreshAttemptAt: String?
    let lastRefreshSucceededAt: String?
    let lastRefreshFailedAt: String?
    let lastRefreshTrigger: DatasetRefreshTrigger?
    let lastRefreshOutcome: DatasetRefreshOutcome?
    let latestCandidateSnapshotID: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
    let lastRefreshFailureReason: String?
}

protocol DatasetRefreshStateStoring {
    func record(_ result: DatasetRefreshResult) async
    func state(for source: FlowDatasetSource) async -> DatasetRefreshState?
}

actor InMemoryDatasetRefreshStateStore: DatasetRefreshStateStoring {
    private var storage = DatasetRefreshStateStorage()

    func record(_ result: DatasetRefreshResult) async {
        storage.record(result)
    }

    func state(for source: FlowDatasetSource) async -> DatasetRefreshState? {
        storage.state(for: source)
    }
}

actor PersistentDatasetRefreshStateStore: DatasetRefreshStateStoring {
    private let fileURL: URL
    private var storage: DatasetRefreshStateStorage

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: .default)
        let loadResult = Self.loadStorage(from: self.fileURL)
        self.storage = loadResult.storage
        if loadResult.shouldRewrite {
            Self.persistStorage(loadResult.storage, to: self.fileURL)
        }
    }

    func record(_ result: DatasetRefreshResult) async {
        storage.record(result)
        persist()
    }

    func state(for source: FlowDatasetSource) async -> DatasetRefreshState? {
        storage.state(for: source)
    }

    private func persist() {
        Self.persistStorage(storage, to: fileURL)
    }

    nonisolated private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Flow", isDirectory: true)
            .appendingPathComponent("DatasetRefreshState", isDirectory: true)
            .appendingPathComponent("refresh_state.json", isDirectory: false)
    }

    nonisolated private static func loadStorage(from fileURL: URL) -> DatasetRefreshStateLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .init(storage: DatasetRefreshStateStorage(), shouldRewrite: false)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? JSONDecoder.refreshStateStoreDecoder.decode(
                DatasetRefreshStatePersistenceEnvelope.self,
                from: data
            ) {
                let storage = DatasetRefreshStateStorage(states: envelope.states)
                return .init(
                    storage: storage,
                    shouldRewrite: envelope.formatVersion != DatasetRefreshStatePersistenceEnvelope.currentFormatVersion
                )
            }

            if let legacyStates = try? JSONDecoder.refreshStateStoreDecoder.decode(
                [DatasetRefreshState].self,
                from: data
            ) {
                return .init(
                    storage: DatasetRefreshStateStorage(states: legacyStates),
                    shouldRewrite: true
                )
            }

            let recovered = recoverStorage(from: data)
            if recovered.recoveredEntryCount > 0 {
                backupCorruptedFile(at: fileURL)
                FlowLogger.log(
                    level: .warning,
                    message: "Recovered valid refresh state subset from malformed persisted file.",
                    metadata: [
                        "path": fileURL.path,
                        "recovered_entries": String(recovered.recoveredEntryCount)
                    ]
                )
                return .init(storage: recovered.storage, shouldRewrite: true)
            }

            backupCorruptedFile(at: fileURL)
            FlowLogger.log(
                level: .error,
                message: "Persisted refresh state file was unreadable. Starting with empty refresh state.",
                metadata: [
                    "path": fileURL.path
                ]
            )
            return .init(storage: DatasetRefreshStateStorage(), shouldRewrite: true)
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to load persisted refresh state store. Starting with empty state.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
            return .init(storage: DatasetRefreshStateStorage(), shouldRewrite: false)
        }
    }

    nonisolated private static func persistStorage(_ storage: DatasetRefreshStateStorage, to fileURL: URL) {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let envelope = DatasetRefreshStatePersistenceEnvelope(
                formatVersion: DatasetRefreshStatePersistenceEnvelope.currentFormatVersion,
                states: storage.persistedStates()
            )
            let data = try JSONEncoder.refreshStateStoreEncoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to persist refresh state store.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func recoverStorage(from data: Data) -> DatasetRefreshStateRecoveryResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(storage: DatasetRefreshStateStorage(), recoveredEntryCount: 0)
        }

        if let states = root["states"] as? [Any] {
            return recoveredStorage(fromStateObjects: states)
        }

        return .init(storage: DatasetRefreshStateStorage(), recoveredEntryCount: 0)
    }

    nonisolated private static func recoveredStorage(fromStateObjects objects: [Any]) -> DatasetRefreshStateRecoveryResult {
        let recoveredStates: [DatasetRefreshState] = objects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? JSONDecoder.refreshStateStoreDecoder.decode(DatasetRefreshState.self, from: data)
        }

        guard !recoveredStates.isEmpty else {
            return .init(storage: DatasetRefreshStateStorage(), recoveredEntryCount: 0)
        }

        return .init(
            storage: DatasetRefreshStateStorage(states: recoveredStates),
            recoveredEntryCount: recoveredStates.count
        )
    }

    nonisolated private static func backupCorruptedFile(at fileURL: URL) {
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupted.\(safeBackupTimestamp()).json")

        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
            }
        } catch {
            FlowLogger.log(
                level: .warning,
                message: "Failed to back up corrupted refresh state file.",
                metadata: [
                    "path": fileURL.path,
                    "backup_path": backupURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func safeBackupTimestamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: now)
    }
}

private struct DatasetRefreshStateStorage: Hashable {
    private var states: [FlowDatasetSource: DatasetRefreshState] = [:]

    init(states: [DatasetRefreshState] = []) {
        self.states = Dictionary(
            uniqueKeysWithValues: states.map { ($0.source, $0) }
        )
    }

    mutating func record(_ result: DatasetRefreshResult) {
        let existing = states[result.source]
        let outcome: DatasetRefreshOutcome = switch result.status {
        case .succeeded: .success
        case .skipped: .skipped
        case .failed: .failed
        }

        let failureAt = result.status == .failed ? result.finishedAt : existing?.lastRefreshFailedAt
        let failureReason: String?
        if result.status == .failed {
            failureReason = summarize(result.error)
        } else if result.status == .succeeded {
            failureReason = nil
        } else {
            failureReason = summarize(result.error) ?? existing?.lastRefreshFailureReason
        }

        let candidateSnapshotID = result.storedSnapshotID ?? existing?.latestCandidateSnapshotID
        let candidateCompatibility = result.compatibilityClassification ?? existing?.latestCandidateCompatibility
        let candidateEligible = result.eligibleForActivation ?? existing?.latestCandidateEligibleForActivation

        states[result.source] = DatasetRefreshState(
            source: result.source,
            lastRefreshAttemptAt: result.startedAt,
            lastRefreshSucceededAt: result.status == .succeeded ? result.finishedAt : existing?.lastRefreshSucceededAt,
            lastRefreshFailedAt: failureAt,
            lastRefreshTrigger: result.trigger,
            lastRefreshOutcome: outcome,
            latestCandidateSnapshotID: candidateSnapshotID,
            latestCandidateCompatibility: candidateCompatibility,
            latestCandidateEligibleForActivation: candidateEligible,
            lastRefreshFailureReason: failureReason
        )
    }

    func state(for source: FlowDatasetSource) -> DatasetRefreshState? {
        states[source]
    }

    func persistedStates() -> [DatasetRefreshState] {
        states.values.sorted { $0.source.rawValue < $1.source.rawValue }
    }

    private func summarize(_ error: DatasetRefreshError?) -> String? {
        guard let error else { return nil }

        switch error {
        case .catalogUnavailable:
            return "catalog_unavailable"
        case .schedulerFailure:
            return "scheduler_failure"
        case .sourceNotLiveCapable:
            return "source_not_live_capable"
        case .adapterNotConfigured:
            return "adapter_not_configured"
        case .refreshInProgress:
            return "refresh_in_progress"
        case .periodicNotDue:
            return "periodic_not_due"
        case .ingestionFailed(let ingestionError):
            return "ingestion_failed_\(ingestionError.code)"
        }
    }
}

private struct DatasetRefreshStatePersistenceEnvelope: Codable, Hashable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let states: [DatasetRefreshState]
}

private struct DatasetRefreshStateLoadResult {
    let storage: DatasetRefreshStateStorage
    let shouldRewrite: Bool
}

private struct DatasetRefreshStateRecoveryResult {
    let storage: DatasetRefreshStateStorage
    let recoveredEntryCount: Int
}

private extension JSONEncoder {
    static let refreshStateStoreEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let refreshStateStoreDecoder = JSONDecoder()
}

private extension IngestionPipelineError {
    var code: String {
        switch self {
        case .adapterFailure:
            return "adapter_failure"
        case .payloadValidationFailed:
            return "payload_validation_failed"
        case .materializationFailed:
            return "materialization_failed"
        case .materializationRejected:
            return "materialization_rejected"
        case .contractValidationFailed:
            return "contract_validation_failed"
        case .integrityFailed:
            return "integrity_failed"
        case .schemaValidationFailed:
            return "schema_validation_failed"
        case .compatibilityFailed:
            return "compatibility_failed"
        }
    }
}
