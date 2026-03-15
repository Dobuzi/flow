import Foundation

enum SnapshotActivationHistorySortOrder: String, Hashable {
    case newestFirst
    case oldestFirst
}

struct SnapshotActivationHistoryTimeRange: Hashable {
    let from: Date?
    let to: Date?

    init(from: Date? = nil, to: Date? = nil) {
        self.from = from
        self.to = to
    }
}

struct SnapshotActivationHistoryQuery: Hashable {
    let source: FlowDatasetSource?
    let commandID: String?
    let snapshotID: String?
    let commandAction: SnapshotActivationCommand.Action?
    let eventType: SnapshotActivationEventType?
    let resultStatus: SnapshotActivationEventStatus?
    let timeRange: SnapshotActivationHistoryTimeRange?
    let offset: Int
    let limit: Int?
    let sortOrder: SnapshotActivationHistorySortOrder

    init(
        source: FlowDatasetSource? = nil,
        commandID: String? = nil,
        snapshotID: String? = nil,
        commandAction: SnapshotActivationCommand.Action? = nil,
        eventType: SnapshotActivationEventType? = nil,
        resultStatus: SnapshotActivationEventStatus? = nil,
        timeRange: SnapshotActivationHistoryTimeRange? = nil,
        offset: Int = 0,
        limit: Int? = nil,
        sortOrder: SnapshotActivationHistorySortOrder = .newestFirst
    ) {
        self.source = source
        self.commandID = commandID
        self.snapshotID = snapshotID
        self.commandAction = commandAction
        self.eventType = eventType
        self.resultStatus = resultStatus
        self.timeRange = timeRange
        self.offset = max(0, offset)
        self.limit = limit
        self.sortOrder = sortOrder
    }
}

protocol SnapshotActivationHistoryStoring {
    func append(_ event: SnapshotActivationHistoryEvent) async
    func events() async -> [SnapshotActivationHistoryEvent]
    func events(for source: FlowDatasetSource) async -> [SnapshotActivationHistoryEvent]
    func events(commandID: String) async -> [SnapshotActivationHistoryEvent]
    func events(snapshotID: String) async -> [SnapshotActivationHistoryEvent]
    func events(type: SnapshotActivationEventType) async -> [SnapshotActivationHistoryEvent]
    func latestEvent(for source: FlowDatasetSource) async -> SnapshotActivationHistoryEvent?
    func query(_ query: SnapshotActivationHistoryQuery) async -> [SnapshotActivationHistoryEvent]
}

actor InMemorySnapshotActivationHistoryStore: SnapshotActivationHistoryStoring {
    private var storage = SnapshotActivationHistoryStorage()

    func append(_ event: SnapshotActivationHistoryEvent) async {
        storage.append(event)
    }

    func events() async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents()
    }

    func events(for source: FlowDatasetSource) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(source: source)
    }

    func events(commandID: String) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(commandID: commandID)
    }

    func events(snapshotID: String) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(snapshotID: snapshotID)
    }

    func events(type: SnapshotActivationEventType) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(eventType: type)
    }

    func latestEvent(for source: FlowDatasetSource) async -> SnapshotActivationHistoryEvent? {
        storage.filteredEvents(source: source, limit: 1).first
    }

    func query(_ query: SnapshotActivationHistoryQuery) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(
            source: query.source,
            commandID: query.commandID,
            snapshotID: query.snapshotID,
            commandAction: query.commandAction,
            eventType: query.eventType,
            resultStatus: query.resultStatus,
            timeRange: query.timeRange,
            offset: query.offset,
            limit: query.limit,
            sortOrder: query.sortOrder
        )
    }
}

actor PersistentSnapshotActivationHistoryStore: SnapshotActivationHistoryStoring {
    private let fileURL: URL
    private var storage: SnapshotActivationHistoryStorage
    nonisolated let restorationDisposition: PersistentStoreRestoreDisposition

    init(
        fileURL: URL? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: .default)
        let loadResult = Self.loadStorage(from: self.fileURL)
        self.storage = loadResult.storage
        self.restorationDisposition = loadResult.disposition
        if loadResult.shouldRewrite {
            Self.persistStorage(loadResult.storage, to: self.fileURL)
        }
    }

    func append(_ event: SnapshotActivationHistoryEvent) async {
        storage.append(event)
        persist()
    }

    func events() async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents()
    }

    func events(for source: FlowDatasetSource) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(source: source)
    }

    func events(commandID: String) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(commandID: commandID)
    }

    func events(snapshotID: String) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(snapshotID: snapshotID)
    }

    func events(type: SnapshotActivationEventType) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(eventType: type)
    }

    func latestEvent(for source: FlowDatasetSource) async -> SnapshotActivationHistoryEvent? {
        storage.filteredEvents(source: source, limit: 1).first
    }

    func query(_ query: SnapshotActivationHistoryQuery) async -> [SnapshotActivationHistoryEvent] {
        storage.filteredEvents(
            source: query.source,
            commandID: query.commandID,
            snapshotID: query.snapshotID,
            commandAction: query.commandAction,
            eventType: query.eventType,
            resultStatus: query.resultStatus,
            timeRange: query.timeRange,
            offset: query.offset,
            limit: query.limit,
            sortOrder: query.sortOrder
        )
    }

    private func persist() {
        Self.persistStorage(storage, to: fileURL)
    }

    nonisolated private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Flow", isDirectory: true)
            .appendingPathComponent("SnapshotActivationHistory", isDirectory: true)
            .appendingPathComponent("activation_history.json", isDirectory: false)
    }

    nonisolated private static func loadStorage(from fileURL: URL) -> SnapshotActivationHistoryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .init(
                storage: SnapshotActivationHistoryStorage(),
                shouldRewrite: false,
                disposition: .empty
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? JSONDecoder.historyStoreDecoder.decode(
                SnapshotActivationHistoryPersistenceEnvelope.self,
                from: data
            ) {
                let isCurrentVersion = envelope.formatVersion == SnapshotActivationHistoryPersistenceEnvelope.currentFormatVersion
                let storage = SnapshotActivationHistoryStorage(
                    storedEvents: envelope.events,
                    sequenceCounter: envelope.sequenceCounter
                )
                return .init(
                    storage: storage,
                    shouldRewrite: !isCurrentVersion,
                    disposition: isCurrentVersion ? .current : .migrated
                )
            }

            if let legacyStorage = try? JSONDecoder.historyStoreDecoder.decode(
                SnapshotActivationHistoryStorage.self,
                from: data
            ) {
                return .init(
                    storage: legacyStorage,
                    shouldRewrite: true,
                    disposition: .migrated
                )
            }

            let recovered = recoverStorage(from: data)
            if recovered.recoveredEntryCount > 0 {
                backupCorruptedFile(at: fileURL)
                FlowLogger.log(
                    level: .warning,
                    message: "Recovered valid activation history subset from malformed persisted file.",
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
                message: "Persisted activation history file was unreadable. Starting with empty history.",
                metadata: [
                    "path": fileURL.path
                ]
            )
            return .init(
                storage: SnapshotActivationHistoryStorage(),
                shouldRewrite: true,
                disposition: .resetCorrupted
            )
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to load persisted activation history store. Starting with empty history.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
            return .init(
                storage: SnapshotActivationHistoryStorage(),
                shouldRewrite: false,
                disposition: .resetCorrupted
            )
        }
    }

    nonisolated private static func persistStorage(_ storage: SnapshotActivationHistoryStorage, to fileURL: URL) {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let envelope = SnapshotActivationHistoryPersistenceEnvelope(
                formatVersion: SnapshotActivationHistoryPersistenceEnvelope.currentFormatVersion,
                sequenceCounter: storage.sequenceCounter,
                events: storage.persistedEvents()
            )
            let data = try JSONEncoder.historyStoreEncoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to persist activation history store.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func recoverStorage(from data: Data) -> SnapshotActivationHistoryRecoveryResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(storage: SnapshotActivationHistoryStorage(), recoveredEntryCount: 0)
        }

        if let events = root["events"] as? [Any] {
            return recoveredStorage(fromEventObjects: events)
        }

        if let eventsByID = root["eventsByID"] as? [String: Any] {
            return recoveredStorage(fromEventObjects: Array(eventsByID.values))
        }

        return .init(storage: SnapshotActivationHistoryStorage(), recoveredEntryCount: 0)
    }

    nonisolated private static func recoveredStorage(fromEventObjects objects: [Any]) -> SnapshotActivationHistoryRecoveryResult {
        let recoveredEvents: [SnapshotActivationHistoryStorage.StoredEvent] = objects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? JSONDecoder.historyStoreDecoder.decode(
                SnapshotActivationHistoryStorage.StoredEvent.self,
                from: data
            )
        }

        guard !recoveredEvents.isEmpty else {
            return .init(storage: SnapshotActivationHistoryStorage(), recoveredEntryCount: 0)
        }

        let maxSequence = recoveredEvents.map(\.sequence).max() ?? recoveredEvents.count
        let storage = SnapshotActivationHistoryStorage(
            storedEvents: recoveredEvents,
            sequenceCounter: maxSequence
        )
        return .init(storage: storage, recoveredEntryCount: recoveredEvents.count)
    }

    nonisolated private static func backupCorruptedFile(at fileURL: URL) {
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupted.\(safeBackupTimestamp()).json")

        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
        } catch {
            FlowLogger.log(
                level: .warning,
                message: "Failed to back up corrupted activation history file.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func safeBackupTimestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}

private struct SnapshotActivationHistoryStorage: Codable {
    struct StoredEvent: Codable {
        let event: SnapshotActivationHistoryEvent
        let sequence: Int
    }

    private var eventsByID: [String: StoredEvent] = [:]
    fileprivate var sequenceCounter: Int = 0

    nonisolated init() {}

    nonisolated init(storedEvents: [StoredEvent], sequenceCounter: Int) {
        self.sequenceCounter = sequenceCounter
        for storedEvent in storedEvents.sorted(by: { $0.sequence < $1.sequence }) {
            eventsByID[storedEvent.event.eventID] = storedEvent
        }
    }

    nonisolated mutating func append(_ event: SnapshotActivationHistoryEvent) {
        sequenceCounter += 1
        eventsByID[event.eventID] = StoredEvent(event: event, sequence: sequenceCounter)
    }

    nonisolated func filteredEvents(
        source: FlowDatasetSource? = nil,
        commandID: String? = nil,
        snapshotID: String? = nil,
        commandAction: SnapshotActivationCommand.Action? = nil,
        eventType: SnapshotActivationEventType? = nil,
        resultStatus: SnapshotActivationEventStatus? = nil,
        timeRange: SnapshotActivationHistoryTimeRange? = nil,
        offset: Int = 0,
        limit: Int? = nil,
        sortOrder: SnapshotActivationHistorySortOrder = .newestFirst
    ) -> [SnapshotActivationHistoryEvent] {
        var entries = Array(eventsByID.values)

        if let source {
            entries = entries.filter { $0.event.metadata.source == source }
        }
        if let commandID {
            entries = entries.filter { $0.event.metadata.commandID == commandID }
        }
        if let snapshotID {
            entries = entries.filter { $0.event.metadata.snapshotID == snapshotID }
        }
        if let commandAction {
            entries = entries.filter { $0.event.metadata.commandAction == commandAction }
        }
        if let eventType {
            entries = entries.filter { $0.event.type == eventType }
        }
        if let resultStatus {
            entries = entries.filter { $0.event.result.status == resultStatus }
        }
        if let timeRange {
            entries = entries.filter {
                let eventDate = parseDate($0.event.timestamp)
                if let from = timeRange.from, eventDate < from {
                    return false
                }
                if let to = timeRange.to, eventDate > to {
                    return false
                }
                return true
            }
        }

        entries.sort { lhs, rhs in
            let leftDate = parseDate(lhs.event.timestamp)
            let rightDate = parseDate(rhs.event.timestamp)

            if leftDate != rightDate {
                return sortOrder == .newestFirst ? leftDate > rightDate : leftDate < rightDate
            }

            if lhs.sequence != rhs.sequence {
                return sortOrder == .newestFirst ? lhs.sequence > rhs.sequence : lhs.sequence < rhs.sequence
            }

            return sortOrder == .newestFirst
                ? lhs.event.eventID > rhs.event.eventID
                : lhs.event.eventID < rhs.event.eventID
        }

        let mapped = entries.map(\.event)
        let clampedOffset = max(0, offset)
        let offsetSlice = clampedOffset < mapped.count ? Array(mapped.dropFirst(clampedOffset)) : []
        if let limit, limit >= 0 {
            return Array(offsetSlice.prefix(limit))
        }
        return offsetSlice
    }

    nonisolated func persistedEvents() -> [StoredEvent] {
        Array(eventsByID.values).sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence {
                return lhs.sequence < rhs.sequence
            }
            return lhs.event.eventID < rhs.event.eventID
        }
    }

    nonisolated private func parseDate(_ value: String) -> Date {
        if let date = Self.iso8601WithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = Self.iso8601.date(from: value) {
            return date
        }
        return .distantPast
    }

    nonisolated(unsafe) private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct SnapshotActivationHistoryPersistenceEnvelope: Codable {
    static let currentFormatVersion = 2

    let formatVersion: Int
    let sequenceCounter: Int
    let events: [SnapshotActivationHistoryStorage.StoredEvent]
}

private struct SnapshotActivationHistoryLoadResult {
    let storage: SnapshotActivationHistoryStorage
    let shouldRewrite: Bool
    let disposition: PersistentStoreRestoreDisposition
}

private struct SnapshotActivationHistoryRecoveryResult {
    let storage: SnapshotActivationHistoryStorage
    let recoveredEntryCount: Int
}

private extension JSONEncoder {
    nonisolated static var historyStoreEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var historyStoreDecoder: JSONDecoder {
        JSONDecoder()
    }
}
