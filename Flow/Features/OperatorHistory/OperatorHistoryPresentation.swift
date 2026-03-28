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

struct OperatorProposalAuditSummary: Identifiable, Hashable {
    let proposalID: String
    let source: FlowDatasetSource
    let sourceTitle: String
    let targetSnapshotID: String?
    let lifecycleSummary: String
    let latestPhase: String
    let latestTimestamp: String
    let createdAt: String?
    let approvedAt: String?
    let rejectedAt: String?
    let cancelledAt: String?
    let latestDetail: String?
    let eventCount: Int

    var id: String { proposalID }
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
        case .rolloutPaused:
            return "Rollout Paused"
        case .rolloutResumed:
            return "Rollout Resumed"
        case .rolloutHalted:
            return "Rollout Halted"
        case .rollbackPreparedMarked:
            return "Rollback Prepared"
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
        case .rolloutPaused:
            return "Paused"
        case .rolloutResumed:
            return "Approved"
        case .rolloutHalted:
            return "Halted"
        case .rollbackPreparedMarked:
            return "Rollback Prepared"
        }
    }

    static func status(for type: RolloutProposalAuditEventType) -> SnapshotActivationEventStatus {
        switch type {
        case .proposalCreated:
            return .requested
        case .proposalApproved:
            return .succeeded
        case .proposalRejected, .proposalCancelled, .rolloutHalted:
            return .blocked
        case .rolloutPaused:
            return .noOp
        case .rolloutResumed, .rollbackPreparedMarked:
            return .succeeded
        }
    }

    static func proposalAuditSummaries(from entries: [OperatorHistoryEntry]) -> [OperatorProposalAuditSummary] {
        proposalAuditSummaries(
            from: entries.compactMap { entry in
                guard entry.category == .proposal, let proposalID = entry.proposalID else { return nil }
                return ProposalAuditSummarySeed(
                    proposalID: proposalID,
                    source: entry.source,
                    sourceTitle: entry.sourceTitle,
                    targetSnapshotID: entry.snapshotID,
                    eventType: entry.eventType,
                    timestamp: entry.timestamp,
                    phaseTitle: entry.status,
                    detail: entry.detail
                )
            }
        )
    }

    static func proposalAuditSummaries(from entries: [OperatorTimelineEntry]) -> [OperatorProposalAuditSummary] {
        proposalAuditSummaries(
            from: entries.compactMap { entry in
                guard entry.category == .proposal, let proposalID = entry.proposalID else { return nil }
                return ProposalAuditSummarySeed(
                    proposalID: proposalID,
                    source: entry.source,
                    sourceTitle: entry.sourceTitle,
                    targetSnapshotID: entry.snapshotID,
                    eventType: entry.eventType,
                    timestamp: entry.timestamp,
                    phaseTitle: entry.status,
                    detail: entry.detail
                )
            }
        )
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

    private static func proposalAuditSummaries(
        from seeds: [ProposalAuditSummarySeed]
    ) -> [OperatorProposalAuditSummary] {
        Dictionary(grouping: seeds, by: \.proposalID)
            .compactMap { _, group in
                guard let first = group.first else { return nil }
                let ascending = group.sorted(by: sortAscending)
                guard let latest = ascending.last else { return nil }
                return OperatorProposalAuditSummary(
                    proposalID: first.proposalID,
                    source: first.source,
                    sourceTitle: first.sourceTitle,
                    targetSnapshotID: latest.targetSnapshotID ?? first.targetSnapshotID,
                    lifecycleSummary: ascending.compactMap(lifecycleStepTitle(for:)).removingAdjacentDuplicates().joined(separator: " -> "),
                    latestPhase: latest.phaseTitle,
                    latestTimestamp: latest.timestamp,
                    createdAt: firstTimestamp(in: ascending, eventType: RolloutProposalAuditEventType.proposalCreated.rawValue),
                    approvedAt: firstTimestamp(in: ascending, eventType: RolloutProposalAuditEventType.proposalApproved.rawValue),
                    rejectedAt: firstTimestamp(in: ascending, eventType: RolloutProposalAuditEventType.proposalRejected.rawValue),
                    cancelledAt: firstTimestamp(in: ascending, eventType: RolloutProposalAuditEventType.proposalCancelled.rawValue),
                    latestDetail: latest.detail,
                    eventCount: ascending.count
                )
            }
            .sorted(by: sortSummaryDescending)
    }

    private static func lifecycleStepTitle(for seed: ProposalAuditSummarySeed) -> String? {
        switch seed.eventType {
        case RolloutProposalAuditEventType.proposalCreated.rawValue:
            return "Created"
        case RolloutProposalAuditEventType.proposalApproved.rawValue:
            return "Approved"
        case RolloutProposalAuditEventType.proposalRejected.rawValue:
            return "Rejected"
        case RolloutProposalAuditEventType.proposalCancelled.rawValue:
            return "Cancelled"
        case RolloutProposalAuditEventType.rolloutPaused.rawValue:
            return "Paused"
        case RolloutProposalAuditEventType.rolloutResumed.rawValue:
            return "Resumed"
        case RolloutProposalAuditEventType.rolloutHalted.rawValue:
            return "Halted"
        case RolloutProposalAuditEventType.rollbackPreparedMarked.rawValue:
            return "Rollback Prepared"
        default:
            return nil
        }
    }

    private static func firstTimestamp(
        in seeds: [ProposalAuditSummarySeed],
        eventType: String
    ) -> String? {
        seeds.first(where: { $0.eventType == eventType })?.timestamp
    }

    private static func sortAscending(lhs: ProposalAuditSummarySeed, rhs: ProposalAuditSummarySeed) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.proposalID < rhs.proposalID
    }

    private static func sortSummaryDescending(lhs: OperatorProposalAuditSummary, rhs: OperatorProposalAuditSummary) -> Bool {
        if lhs.latestTimestamp != rhs.latestTimestamp {
            return lhs.latestTimestamp > rhs.latestTimestamp
        }
        return lhs.proposalID < rhs.proposalID
    }
}

private struct ProposalAuditSummarySeed: Hashable {
    let proposalID: String
    let source: FlowDatasetSource
    let sourceTitle: String
    let targetSnapshotID: String?
    let eventType: String
    let timestamp: String
    let phaseTitle: String
    let detail: String?
}

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        var result: [String] = []
        for element in self where result.last != element {
            result.append(element)
        }
        return result
    }
}
