import Foundation

protocol SnapshotActivationStateStoring {
    func state(for source: FlowDatasetSource) async -> SnapshotActivationState?
    func setState(_ state: SnapshotActivationState) async
}

actor InMemorySnapshotActivationStateStore: SnapshotActivationStateStoring {
    private var storage = SnapshotActivationStateStorage()

    func state(for source: FlowDatasetSource) async -> SnapshotActivationState? {
        storage.state(for: source)
    }

    func setState(_ state: SnapshotActivationState) async {
        storage.setState(state)
    }
}

actor PersistentSnapshotActivationStateStore: SnapshotActivationStateStoring {
    private let fileURL: URL
    private var storage: SnapshotActivationStateStorage
    nonisolated let restorationDisposition: PersistentStoreRestoreDisposition

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: .default)
        let loadResult = Self.loadStorage(from: self.fileURL)
        self.storage = loadResult.storage
        self.restorationDisposition = loadResult.disposition
        if loadResult.shouldRewrite {
            Self.persistStorage(loadResult.storage, to: self.fileURL)
        }
    }

    func state(for source: FlowDatasetSource) async -> SnapshotActivationState? {
        storage.state(for: source)
    }

    func setState(_ state: SnapshotActivationState) async {
        storage.setState(state)
        persist()
    }

    private func persist() {
        Self.persistStorage(storage, to: fileURL)
    }

    nonisolated private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Flow", isDirectory: true)
            .appendingPathComponent("SnapshotActivationState", isDirectory: true)
            .appendingPathComponent("activation_state.json", isDirectory: false)
    }

    nonisolated private static func loadStorage(from fileURL: URL) -> SnapshotActivationStateLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .init(
                storage: SnapshotActivationStateStorage(),
                shouldRewrite: false,
                disposition: .empty
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? JSONDecoder.activationStateStoreDecoder.decode(
                SnapshotActivationStatePersistenceEnvelope.self,
                from: data
            ) {
                let storage = SnapshotActivationStateStorage(states: envelope.states)
                return .init(
                    storage: storage,
                    shouldRewrite: envelope.formatVersion != SnapshotActivationStatePersistenceEnvelope.currentFormatVersion,
                    disposition: envelope.formatVersion == SnapshotActivationStatePersistenceEnvelope.currentFormatVersion ? .current : .migrated
                )
            }

            if let legacyStates = try? JSONDecoder.activationStateStoreDecoder.decode(
                [SnapshotActivationState].self,
                from: data
            ) {
                return .init(
                    storage: SnapshotActivationStateStorage(states: legacyStates),
                    shouldRewrite: true,
                    disposition: .migrated
                )
            }

            let recovered = recoverStorage(from: data)
            if recovered.recoveredEntryCount > 0 {
                backupCorruptedFile(at: fileURL)
                FlowLogger.log(
                    level: .warning,
                    message: "Recovered valid activation state subset from malformed persisted file.",
                    metadata: [
                        "path": fileURL.path,
                        "recovered_entries": String(recovered.recoveredEntryCount)
                    ]
                )
                return .init(
                    storage: recovered.storage,
                    shouldRewrite: true,
                    disposition: .recoveredPartial
                )
            }

            backupCorruptedFile(at: fileURL)
            FlowLogger.log(
                level: .error,
                message: "Persisted activation state file was unreadable. Starting with empty activation state.",
                metadata: [
                    "path": fileURL.path
                ]
            )
            return .init(
                storage: SnapshotActivationStateStorage(),
                shouldRewrite: true,
                disposition: .resetCorrupted
            )
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to load persisted activation state store. Starting with empty state.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
            return .init(
                storage: SnapshotActivationStateStorage(),
                shouldRewrite: false,
                disposition: .resetCorrupted
            )
        }
    }

    nonisolated private static func persistStorage(_ storage: SnapshotActivationStateStorage, to fileURL: URL) {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let envelope = SnapshotActivationStatePersistenceEnvelope(
                formatVersion: SnapshotActivationStatePersistenceEnvelope.currentFormatVersion,
                states: storage.persistedStates()
            )
            let data = try JSONEncoder.activationStateStoreEncoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to persist activation state store.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func recoverStorage(from data: Data) -> SnapshotActivationStateRecoveryResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(storage: SnapshotActivationStateStorage(), recoveredEntryCount: 0)
        }

        if let states = root["states"] as? [Any] {
            return recoveredStorage(fromStateObjects: states)
        }

        return .init(storage: SnapshotActivationStateStorage(), recoveredEntryCount: 0)
    }

    nonisolated private static func recoveredStorage(fromStateObjects objects: [Any]) -> SnapshotActivationStateRecoveryResult {
        let recoveredStates: [SnapshotActivationState] = objects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? JSONDecoder.activationStateStoreDecoder.decode(SnapshotActivationState.self, from: data)
        }

        guard !recoveredStates.isEmpty else {
            return .init(storage: SnapshotActivationStateStorage(), recoveredEntryCount: 0)
        }

        return .init(
            storage: SnapshotActivationStateStorage(states: recoveredStates),
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
                message: "Failed to back up corrupted activation state file.",
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

private struct SnapshotActivationStateStorage: Hashable {
    private var states: [FlowDatasetSource: SnapshotActivationState] = [:]

    init(states: [SnapshotActivationState] = []) {
        self.states = Dictionary(
            uniqueKeysWithValues: states.map { ($0.source, $0) }
        )
    }

    func state(for source: FlowDatasetSource) -> SnapshotActivationState? {
        states[source]
    }

    mutating func setState(_ state: SnapshotActivationState) {
        states[state.source] = state
    }

    func persistedStates() -> [SnapshotActivationState] {
        states.values.sorted { $0.source.rawValue < $1.source.rawValue }
    }
}

private struct SnapshotActivationStatePersistenceEnvelope: Codable, Hashable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let states: [SnapshotActivationState]
}

private struct SnapshotActivationStateLoadResult {
    let storage: SnapshotActivationStateStorage
    let shouldRewrite: Bool
    let disposition: PersistentStoreRestoreDisposition
}

private struct SnapshotActivationStateRecoveryResult {
    let storage: SnapshotActivationStateStorage
    let recoveredEntryCount: Int
}

private extension JSONEncoder {
    static let activationStateStoreEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let activationStateStoreDecoder = JSONDecoder()
}
