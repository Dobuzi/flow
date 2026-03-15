import Foundation

struct OperatorTimelineEntry: Identifiable, Hashable {
    let id: String
    let sourceTitle: String
    let eventType: SnapshotActivationEventType
    let commandAction: SnapshotActivationCommand.Action
    let resultStatus: SnapshotActivationEventStatus
    let title: String
    let timestamp: String
    let snapshotID: String?
    let status: String
    let detail: String?
}

struct OperatorHistoryEntry: Identifiable, Hashable {
    let id: String
    let commandID: String
    let source: FlowDatasetSource
    let sourceTitle: String
    let eventType: SnapshotActivationEventType
    let commandAction: SnapshotActivationCommand.Action
    let resultStatus: SnapshotActivationEventStatus
    let title: String
    let timestamp: String
    let snapshotID: String?
    let status: String
    let detail: String?
}

enum OperatorHistoryPresentation {
    static func timelineEntry(from event: SnapshotActivationHistoryEvent) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: event.eventID,
            sourceTitle: event.metadata.source.title,
            eventType: event.type,
            commandAction: event.metadata.commandAction,
            resultStatus: event.result.status,
            title: humanizedEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: resolvedSnapshotID(from: event),
            status: humanizedEventStatus(event.result.status),
            detail: event.result.message ?? humanizedReasonCode(event.result.reasonCode)
        )
    }

    static func historyEntry(from event: SnapshotActivationHistoryEvent) -> OperatorHistoryEntry {
        OperatorHistoryEntry(
            id: event.eventID,
            commandID: event.metadata.commandID,
            source: event.metadata.source,
            sourceTitle: event.metadata.source.title,
            eventType: event.type,
            commandAction: event.metadata.commandAction,
            resultStatus: event.result.status,
            title: humanizedEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: resolvedSnapshotID(from: event),
            status: humanizedEventStatus(event.result.status),
            detail: event.result.message ?? humanizedReasonCode(event.result.reasonCode)
        )
    }

    static func humanizedEventTitle(_ type: SnapshotActivationEventType) -> String {
        type.rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }

    static func humanizedEventStatus(_ status: SnapshotActivationEventStatus) -> String {
        switch status {
        case .requested:
            return "Requested"
        case .succeeded:
            return "Succeeded"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
        case .noOp:
            return "No-op"
        }
    }

    static func humanizedReasonCode(_ reasonCode: String?) -> String? {
        guard let reasonCode, !reasonCode.isEmpty else { return nil }
        return reasonCode.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func resolvedSnapshotID(from event: SnapshotActivationHistoryEvent) -> String? {
        event.metadata.snapshotID
            ?? event.metadata.guardDecision?.candidateSnapshotID
            ?? event.metadata.guardDecision?.rollbackTargetSnapshotID
            ?? event.metadata.execution?.resultingActiveSnapshotID
    }
}
