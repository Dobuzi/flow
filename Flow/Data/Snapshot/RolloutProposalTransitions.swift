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
    case rolloutPaused
    case rolloutResumed
    case rolloutHalted
    case rollbackPreparedMarked
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

actor PersistentRolloutProposalAuditStore: RolloutProposalAuditStoring {
    private let fileURL: URL
    private var storedEvents: [RolloutProposalAuditEvent]
    nonisolated let restorationDisposition: PersistentStoreRestoreDisposition

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: .default)
        let loadResult = Self.loadEvents(from: self.fileURL)
        self.storedEvents = loadResult.events.sorted(by: Self.sortComparator)
        self.restorationDisposition = loadResult.disposition
        if loadResult.shouldRewrite {
            Self.persist(self.storedEvents, to: self.fileURL)
        }
    }

    func append(_ event: RolloutProposalAuditEvent) async {
        storedEvents.append(event)
        storedEvents.sort(by: Self.sortComparator)
        Self.persist(storedEvents, to: fileURL)
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

    nonisolated private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Flow", isDirectory: true)
            .appendingPathComponent("RolloutProposals", isDirectory: true)
            .appendingPathComponent("rollout_proposal_audit.json", isDirectory: false)
    }

    nonisolated private static func loadEvents(from fileURL: URL) -> AuditLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AuditLoadResult(events: [], shouldRewrite: false, disposition: .empty)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? JSONDecoder.rolloutProposalAuditStoreDecoder.decode(
                RolloutProposalAuditPersistenceEnvelope.self,
                from: data
            ) {
                return AuditLoadResult(
                    events: envelope.events,
                    shouldRewrite: envelope.formatVersion != RolloutProposalAuditPersistenceEnvelope.currentFormatVersion,
                    disposition: envelope.formatVersion == RolloutProposalAuditPersistenceEnvelope.currentFormatVersion ? .current : .migrated
                )
            }

            if let legacyEvents = try? JSONDecoder.rolloutProposalAuditStoreDecoder.decode(
                [RolloutProposalAuditEvent].self,
                from: data
            ) {
                return AuditLoadResult(
                    events: legacyEvents,
                    shouldRewrite: true,
                    disposition: .migrated
                )
            }

            backupCorruptedFile(at: fileURL)
            return AuditLoadResult(events: [], shouldRewrite: true, disposition: .resetCorrupted)
        } catch {
            return AuditLoadResult(events: [], shouldRewrite: false, disposition: .resetCorrupted)
        }
    }

    nonisolated private static func persist(_ events: [RolloutProposalAuditEvent], to fileURL: URL) {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let envelope = RolloutProposalAuditPersistenceEnvelope(
                formatVersion: RolloutProposalAuditPersistenceEnvelope.currentFormatVersion,
                events: events
            )
            let data = try JSONEncoder.rolloutProposalAuditStoreEncoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to persist rollout proposal audit store.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
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
                message: "Failed to back up corrupted rollout proposal audit file.",
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

private struct RolloutProposalAuditPersistenceEnvelope: Codable, Hashable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let events: [RolloutProposalAuditEvent]
}

private struct AuditLoadResult {
    let events: [RolloutProposalAuditEvent]
    let shouldRewrite: Bool
    let disposition: PersistentStoreRestoreDisposition
}

private extension JSONEncoder {
    static let rolloutProposalAuditStoreEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let rolloutProposalAuditStoreDecoder = JSONDecoder()
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

enum RolloutProposalControlAction: String, Hashable {
    case pause
    case resume
    case halt
    case markRollbackPrepared
}

enum RolloutProposalControlTransitionError: Error, Hashable {
    case proposalNotFound(id: String)
    case invalidTransition(
        lifecycleState: RolloutProposalLifecycleState,
        controlState: RolloutProposalControlState,
        action: RolloutProposalControlAction
    )
}

protocol RolloutProposalControlling {
    func apply(
        _ action: RolloutProposalControlAction,
        proposalID: String,
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

actor DefaultRolloutProposalControlService: RolloutProposalControlling {
    private let store: RolloutProposalStoring
    private let auditStore: RolloutProposalAuditStoring

    init(
        store: RolloutProposalStoring,
        auditStore: RolloutProposalAuditStoring
    ) {
        self.store = store
        self.auditStore = auditStore
    }

    func apply(
        _ action: RolloutProposalControlAction,
        proposalID: String,
        by actor: String?,
        at timestamp: String,
        reason: String?
    ) async throws -> RolloutProposal {
        guard let proposal = await store.proposal(id: proposalID) else {
            throw RolloutProposalControlTransitionError.proposalNotFound(id: proposalID)
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
        _ action: RolloutProposalControlAction,
        to proposal: RolloutProposal,
        at timestamp: String,
        reason: String?
    ) throws -> RolloutProposal {
        switch action {
        case .pause:
            guard isControllableLifecycle(proposal.lifecycleState), proposal.controlState == .active else {
                throw RolloutProposalControlTransitionError.invalidTransition(
                    lifecycleState: proposal.lifecycleState,
                    controlState: proposal.controlState,
                    action: action
                )
            }
            return proposal.updating(
                controlState: .paused,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case .resume:
            guard isControllableLifecycle(proposal.lifecycleState), proposal.controlState == .paused else {
                throw RolloutProposalControlTransitionError.invalidTransition(
                    lifecycleState: proposal.lifecycleState,
                    controlState: proposal.controlState,
                    action: action
                )
            }
            return proposal.updating(
                controlState: .active,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case .halt:
            guard isControllableLifecycle(proposal.lifecycleState),
                  proposal.controlState == .active || proposal.controlState == .paused else {
                throw RolloutProposalControlTransitionError.invalidTransition(
                    lifecycleState: proposal.lifecycleState,
                    controlState: proposal.controlState,
                    action: action
                )
            }
            return proposal.updating(
                controlState: .halted,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        case .markRollbackPrepared:
            guard isControllableLifecycle(proposal.lifecycleState),
                  proposal.controlState == .active || proposal.controlState == .paused else {
                throw RolloutProposalControlTransitionError.invalidTransition(
                    lifecycleState: proposal.lifecycleState,
                    controlState: proposal.controlState,
                    action: action
                )
            }
            return proposal.updating(
                rollbackPreparedAt: timestamp,
                updatedAt: timestamp,
                lastDecisionAt: timestamp,
                lastDecisionReason: reason
            )
        }
    }

    private static func isControllableLifecycle(_ lifecycleState: RolloutProposalLifecycleState) -> Bool {
        switch lifecycleState {
        case .approved, .readyForExecution:
            return true
        case .draft, .proposed, .rejected, .cancelled:
            return false
        }
    }

    private static func auditEventType(
        for action: RolloutProposalControlAction
    ) -> RolloutProposalAuditEventType {
        switch action {
        case .pause:
            return .rolloutPaused
        case .resume:
            return .rolloutResumed
        case .halt:
            return .rolloutHalted
        case .markRollbackPrepared:
            return .rollbackPreparedMarked
        }
    }
}
