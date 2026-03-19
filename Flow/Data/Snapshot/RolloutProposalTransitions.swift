import Foundation

enum RolloutProposalLifecycleState: String, Codable, Hashable {
    case draft
    case proposed
    case approved
    case rejected
    case cancelled
    case readyForExecution
}

enum RolloutProposalTransitionAction: String, Hashable {
    case submit
    case approve
    case reject
    case cancel
}

enum RolloutProposalTransitionError: Error, Hashable {
    case proposalNotFound(id: String)
    case invalidTransition(state: RolloutProposalLifecycleState, action: RolloutProposalTransitionAction)
}

enum RolloutProposalAuditEventType: String, Codable, Hashable {
    case proposalCreated
    case proposalApproved
    case proposalRejected
    case proposalCancelled
}

struct RolloutProposalAuditEvent: Codable, Hashable, Identifiable {
    let id: String
    let proposalID: String
    let source: FlowDatasetSource
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let action: SnapshotActivationCommand.Action
    let type: RolloutProposalAuditEventType
    let timestamp: String
    let actor: String?
    let reason: String?
}

protocol RolloutProposalAuditStoring {
    func append(_ event: RolloutProposalAuditEvent) async
    func events() async -> [RolloutProposalAuditEvent]
    func events(for source: FlowDatasetSource) async -> [RolloutProposalAuditEvent]
    func events(proposalID: String) async -> [RolloutProposalAuditEvent]
}

actor InMemoryRolloutProposalAuditStore: RolloutProposalAuditStoring {
    private var storedEvents: [RolloutProposalAuditEvent] = []

    func append(_ event: RolloutProposalAuditEvent) async {
        storedEvents.append(event)
        storedEvents.sort(by: Self.sortComparator)
    }

    func events() async -> [RolloutProposalAuditEvent] {
        storedEvents
    }

    func events(for source: FlowDatasetSource) async -> [RolloutProposalAuditEvent] {
        storedEvents.filter { $0.source == source }
    }

    func events(proposalID: String) async -> [RolloutProposalAuditEvent] {
        storedEvents.filter { $0.proposalID == proposalID }
    }

    private static func sortComparator(
        lhs: RolloutProposalAuditEvent,
        rhs: RolloutProposalAuditEvent
    ) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id < rhs.id
    }
}

protocol RolloutProposalTransitioning {
    func submitProposal(
        id: String,
        by actor: String?,
        at timestamp: String
    ) async throws -> RolloutProposal

    func approveProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal

    func rejectProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal

    func cancelProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal
}

actor DefaultRolloutProposalTransitionService: RolloutProposalTransitioning {
    private let store: RolloutProposalStoring
    private let auditStore: RolloutProposalAuditStoring

    init(
        store: RolloutProposalStoring,
        auditStore: RolloutProposalAuditStoring
    ) {
        self.store = store
        self.auditStore = auditStore
    }

    func submitProposal(
        id: String,
        by actor: String?,
        at timestamp: String
    ) async throws -> RolloutProposal {
        try await transitionProposal(
            id: id,
            action: .submit,
            actor: actor,
            timestamp: timestamp,
            reason: nil
        )
    }

    func approveProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal {
        try await transitionProposal(
            id: id,
            action: .approve,
            actor: actor,
            timestamp: timestamp,
            reason: reason
        )
    }

    func rejectProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal {
        try await transitionProposal(
            id: id,
            action: .reject,
            actor: actor,
            timestamp: timestamp,
            reason: reason
        )
    }

    func cancelProposal(
        id: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal {
        try await transitionProposal(
            id: id,
            action: .cancel,
            actor: actor,
            timestamp: timestamp,
            reason: reason
        )
    }

    private func transitionProposal(
        id: String,
        action: RolloutProposalTransitionAction,
        actor: String?,
        timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal {
        guard let proposal = await store.proposal(id: id) else {
            throw RolloutProposalTransitionError.proposalNotFound(id: id)
        }

        let transitioned = try Self.apply(
            action,
            to: proposal,
            at: timestamp,
            reason: reason
        )
        await store.save(transitioned)
        await auditStore.append(
            RolloutProposalAuditEvent(
                id: "\(proposal.id):\(action.rawValue):\(timestamp)",
                proposalID: proposal.id,
                source: proposal.source,
                targetSnapshotID: proposal.targetSnapshotID,
                targetDatasetVersion: proposal.targetDatasetVersion,
                action: proposal.action,
                type: Self.auditEventType(for: action),
                timestamp: timestamp,
                actor: actor,
                reason: reason
            )
        )
        return transitioned
    }

    private static func apply(
        _ action: RolloutProposalTransitionAction,
        to proposal: RolloutProposal,
        at timestamp: String,
        reason: String?
    ) throws -> RolloutProposal {
        switch (proposal.lifecycleState, action) {
        case (.draft, .submit):
            return proposal.updating(
                lifecycleState: .proposed,
                approvalState: .awaitingApproval,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case (.proposed, .approve):
            return proposal.updating(
                lifecycleState: .approved,
                approvalState: .approved,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case (.proposed, .reject):
            return proposal.updating(
                lifecycleState: .rejected,
                approvalState: .rejected,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case (.draft, .cancel), (.proposed, .cancel), (.approved, .cancel):
            return proposal.updating(
                lifecycleState: .cancelled,
                approvalState: .cancelled,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        default:
            throw RolloutProposalTransitionError.invalidTransition(
                state: proposal.lifecycleState,
                action: action
            )
        }
    }

    private static func auditEventType(
        for action: RolloutProposalTransitionAction
    ) -> RolloutProposalAuditEventType {
        switch action {
        case .submit:
            return .proposalCreated
        case .approve:
            return .proposalApproved
        case .reject:
            return .proposalRejected
        case .cancel:
            return .proposalCancelled
        }
    }
}
