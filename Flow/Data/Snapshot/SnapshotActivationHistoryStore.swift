import Foundation

enum SnapshotActivationHistorySortOrder: String, Hashable {
    case newestFirst
    case oldestFirst
}

struct SnapshotActivationHistoryQuery: Hashable {
    let source: FlowDatasetSource?
    let commandID: String?
    let snapshotID: String?
    let eventType: SnapshotActivationEventType?
    let limit: Int?
    let sortOrder: SnapshotActivationHistorySortOrder

    init(
        source: FlowDatasetSource? = nil,
        commandID: String? = nil,
        snapshotID: String? = nil,
        eventType: SnapshotActivationEventType? = nil,
        limit: Int? = nil,
        sortOrder: SnapshotActivationHistorySortOrder = .newestFirst
    ) {
        self.source = source
        self.commandID = commandID
        self.snapshotID = snapshotID
        self.eventType = eventType
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
    private struct StoredEvent {
        let event: SnapshotActivationHistoryEvent
        let sequence: Int
    }

    private var eventsByID: [String: StoredEvent] = [:]
    private var sequenceCounter: Int = 0

    func append(_ event: SnapshotActivationHistoryEvent) async {
        sequenceCounter += 1
        eventsByID[event.eventID] = StoredEvent(event: event, sequence: sequenceCounter)
    }

    func events() async -> [SnapshotActivationHistoryEvent] {
        applyFilters()
    }

    func events(for source: FlowDatasetSource) async -> [SnapshotActivationHistoryEvent] {
        applyFilters(source: source)
    }

    func events(commandID: String) async -> [SnapshotActivationHistoryEvent] {
        applyFilters(commandID: commandID)
    }

    func events(snapshotID: String) async -> [SnapshotActivationHistoryEvent] {
        applyFilters(snapshotID: snapshotID)
    }

    func events(type: SnapshotActivationEventType) async -> [SnapshotActivationHistoryEvent] {
        applyFilters(eventType: type)
    }

    func latestEvent(for source: FlowDatasetSource) async -> SnapshotActivationHistoryEvent? {
        applyFilters(source: source, limit: 1).first
    }

    func query(_ query: SnapshotActivationHistoryQuery) async -> [SnapshotActivationHistoryEvent] {
        applyFilters(
            source: query.source,
            commandID: query.commandID,
            snapshotID: query.snapshotID,
            eventType: query.eventType,
            limit: query.limit,
            sortOrder: query.sortOrder
        )
    }

    private func applyFilters(
        source: FlowDatasetSource? = nil,
        commandID: String? = nil,
        snapshotID: String? = nil,
        eventType: SnapshotActivationEventType? = nil,
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
        if let eventType {
            entries = entries.filter { $0.event.type == eventType }
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
        if let limit, limit >= 0 {
            return Array(mapped.prefix(limit))
        }
        return mapped
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
