import Foundation

enum OperatorHistoryEntryCategory: String, Hashable {
    case activation
    case proposal

    var title: String {
        switch self {
        case .activation:
            return "Activation"
        case .proposal:
            return "Proposal"
        }
    }
}

struct OperatorTimelineEntry: Identifiable, Hashable {
    let id: String
    let category: OperatorHistoryEntryCategory
    let source: FlowDatasetSource
    let sourceTitle: String
    let eventType: String
    let commandAction: SnapshotActivationCommand.Action
    let resultStatus: SnapshotActivationEventStatus
    let title: String
    let timestamp: String
    let snapshotID: String?
    let proposalID: String?
    let linkageID: String
    let status: String
    let detail: String?
}

struct OperatorHistoryEntry: Identifiable, Hashable {
    let id: String
    let category: OperatorHistoryEntryCategory
    let linkageID: String
    let source: FlowDatasetSource
    let sourceTitle: String
    let eventType: String
    let commandAction: SnapshotActivationCommand.Action
    let resultStatus: SnapshotActivationEventStatus
    let title: String
    let timestamp: String
    let snapshotID: String?
    let proposalID: String?
    let status: String
    let detail: String?
}

enum OperatorHistoryPresentation {
    static func timelineEntry(from event: SnapshotActivationHistoryEvent) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: event.eventID,
            category: .activation,
            source: event.metadata.source,
            sourceTitle: event.metadata.source.title,
            eventType: event.type.rawValue,
            commandAction: event.metadata.commandAction,
            resultStatus: event.result.status,
            title: humanizedEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: resolvedSnapshotID(from: event),
            proposalID: nil,
            linkageID: event.metadata.commandID,
            status: humanizedEventStatus(event.result.status),
            detail: event.result.message ?? humanizedReasonCode(event.result.reasonCode)
        )
    }

    static func historyEntry(from event: SnapshotActivationHistoryEvent) -> OperatorHistoryEntry {
        OperatorHistoryEntry(
            id: event.eventID,
            category: .activation,
            linkageID: event.metadata.commandID,
            source: event.metadata.source,
            sourceTitle: event.metadata.source.title,
            eventType: event.type.rawValue,
            commandAction: event.metadata.commandAction,
            resultStatus: event.result.status,
            title: humanizedEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: resolvedSnapshotID(from: event),
            proposalID: nil,
            status: humanizedEventStatus(event.result.status),
            detail: event.result.message ?? humanizedReasonCode(event.result.reasonCode)
        )
    }

    static func timelineEntry(from event: RolloutProposalAuditEvent) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: event.id,
            category: .proposal,
            source: event.source,
            sourceTitle: event.source.title,
            eventType: event.type.rawValue,
            commandAction: event.action,
            resultStatus: status(for: event.type),
            title: humanizedProposalEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: event.targetSnapshotID,
            proposalID: event.proposalID,
            linkageID: event.proposalID,
            status: proposalStatusTitle(for: event.type),
            detail: event.reason ?? proposalDetail(for: event)
        )
    }

    static func historyEntry(from event: RolloutProposalAuditEvent) -> OperatorHistoryEntry {
        OperatorHistoryEntry(
            id: event.id,
            category: .proposal,
            linkageID: event.proposalID,
            source: event.source,
            sourceTitle: event.source.title,
            eventType: event.type.rawValue,
            commandAction: event.action,
            resultStatus: status(for: event.type),
            title: humanizedProposalEventTitle(event.type),
            timestamp: event.timestamp,
            snapshotID: event.targetSnapshotID,
            proposalID: event.proposalID,
            status: proposalStatusTitle(for: event.type),
            detail: event.reason ?? proposalDetail(for: event)
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

    static func humanizedProposalEventTitle(_ type: RolloutProposalAuditEventType) -> String {
        switch type {
        case .proposalCreated:
            return "Proposal Created"
        case .proposalApproved:
            return "Proposal Approved"
        case .proposalRejected:
            return "Proposal Rejected"
        case .proposalCancelled:
            return "Proposal Cancelled"
        }
    }

    static func proposalStatusTitle(for type: RolloutProposalAuditEventType) -> String {
        switch type {
        case .proposalCreated:
            return "Awaiting Approval"
        case .proposalApproved:
            return "Approved"
        case .proposalRejected:
            return "Rejected"
        case .proposalCancelled:
            return "Cancelled"
        }
    }

    static func status(for type: RolloutProposalAuditEventType) -> SnapshotActivationEventStatus {
        switch type {
        case .proposalCreated:
            return .requested
        case .proposalApproved:
            return .succeeded
        case .proposalRejected, .proposalCancelled:
            return .blocked
        }
    }

    private static func resolvedSnapshotID(from event: SnapshotActivationHistoryEvent) -> String? {
        event.metadata.snapshotID
            ?? event.metadata.guardDecision?.candidateSnapshotID
            ?? event.metadata.guardDecision?.rollbackTargetSnapshotID
            ?? event.metadata.execution?.resultingActiveSnapshotID
    }

    private static func proposalDetail(for event: RolloutProposalAuditEvent) -> String? {
        if let targetDatasetVersion = event.targetDatasetVersion {
            return "Version \(targetDatasetVersion)"
        }
        return event.actor.map { "Actor \($0)" }
    }
}
