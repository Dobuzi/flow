import Foundation

protocol CatalogLiveMetadataEnriching {
    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor
}

struct CatalogLiveMetadataEnricher: CatalogLiveMetadataEnriching {
    private let versionStore: DatasetVersionStoring
    private let activationPolicy: SnapshotActivationPolicying
    private let refreshStateStore: DatasetRefreshStateStoring?
    private let activationStateProjector: SnapshotActivationStateProjecting?

    init(
        versionStore: DatasetVersionStoring,
        activationPolicy: SnapshotActivationPolicying,
        refreshStateStore: DatasetRefreshStateStoring? = nil,
        activationStateProjector: SnapshotActivationStateProjecting? = nil
    ) {
        self.versionStore = versionStore
        self.activationPolicy = activationPolicy
        self.refreshStateStore = refreshStateStore
        self.activationStateProjector = activationStateProjector
    }

    func enrich(_ descriptor: MobilityDatasetDescriptor) async -> MobilityDatasetDescriptor {
        guard let base = descriptor.liveMetadata, base.supportsLiveRefresh else {
            return descriptor
        }

        let versions = await versionStore.versions(for: descriptor.source)
        let latest = versions.first
        let latestSuccessful = versions.first(where: isSuccessfulRefreshCandidate(_:))
        let activationState = await activationPolicy.currentState(for: descriptor.source)
        let refreshState = await refreshStateStore?.state(for: descriptor.source)
        let projectedActivation = await activationStateProjector?.project(for: descriptor.source)
        let latestCandidateDecision = await activationPolicy.evaluateActivation(
            source: descriptor.source,
            requestedSnapshotID: latest?.snapshotID
        )
        let rollbackDecision = await activationPolicy.evaluateRollback(source: descriptor.source)

        let latestCandidateEligibleForActivation: Bool?
        switch latestCandidateDecision.status {
        case .activatable:
            latestCandidateEligibleForActivation = true
        case .storedButNotActivatable:
            latestCandidateEligibleForActivation = false
        case .snapshotNotFound, .noCandidate:
            latestCandidateEligibleForActivation = nil
        }

        let readiness: DatasetRefreshReadiness
        if latestSuccessful != nil || activationState.activeSnapshotID != nil {
            readiness = .ready
        } else if latest == nil {
            readiness = .pendingValidation
        } else {
            readiness = .blocked
        }

        let syncState: DatasetSyncState
        switch latest?.compatibilityClassification {
        case .compatible:
            syncState = .ready
        case .partiallyCompatible:
            syncState = .degraded
        case .incompatible:
            syncState = .failed
        case .none:
            syncState = .idle
        }

        let activationMetadata = DatasetActivationMetadata(
            activeSnapshotID: projectedActivation?.activeSnapshotID ?? activationState.activeSnapshotID ?? base.activeSnapshotID,
            lastKnownGoodSnapshotID: projectedActivation?.lastKnownGoodSnapshotID ?? activationState.lastKnownGoodSnapshotID ?? base.lastKnownGoodSnapshotID,
            latestCandidateSnapshotID: projectedActivation?.latestCandidateSnapshotID ?? refreshState?.latestCandidateSnapshotID ?? latest?.snapshotID ?? base.latestCandidateSnapshotID,
            latestCandidateDatasetVersion: projectedActivation?.latestCandidateDatasetVersion ?? latest?.datasetVersion,
            latestCandidateCompatibility: projectedActivation?.latestCandidateCompatibility ?? refreshState?.latestCandidateCompatibility ?? latest?.compatibilityClassification ?? base.latestCandidateCompatibility,
            latestCandidateEligibleForActivation: projectedActivation?.latestCandidateEligibleForActivation ?? refreshState?.latestCandidateEligibleForActivation ?? latestCandidateEligibleForActivation ?? base.latestCandidateEligibleForActivation,
            rollbackAvailable: projectedActivation?.rollbackAvailable ?? (rollbackDecision.status == .rollbackAvailable),
            latestActivationEventType: projectedActivation?.latestActivationEvent?.type.rawValue,
            latestActivationEventAt: projectedActivation?.latestActivationEvent?.timestamp,
            operatorActivationStatus: DatasetOperatorActivationStatus(projectedStatus: projectedActivation?.status),
            promoteRequiresConfirmation: promoteRequiresConfirmation(
                source: descriptor.source,
                activationState: activationState,
                latestCandidate: latest,
                latestCandidateDecision: latestCandidateDecision,
                rollbackDecision: rollbackDecision
            ),
            demoteRequiresConfirmation: demoteRequiresConfirmation(
                source: descriptor.source,
                activationState: activationState,
                latestCandidate: latest,
                latestCandidateDecision: latestCandidateDecision,
                rollbackDecision: rollbackDecision
            ),
            rollbackRequiresConfirmation: rollbackRequiresConfirmation(
                source: descriptor.source,
                activationState: activationState,
                latestCandidate: latest,
                latestCandidateDecision: latestCandidateDecision,
                rollbackDecision: rollbackDecision
            )
        )

        let merged = DatasetLiveMetadata(
            supportsLiveRefresh: base.supportsLiveRefresh,
            latestKnownDatasetVersion: latest?.datasetVersion ?? base.latestKnownDatasetVersion,
            latestKnownSnapshotID: latest?.snapshotID ?? base.latestKnownSnapshotID,
            lastRefreshAttemptAt: refreshState?.lastRefreshAttemptAt ?? latest?.indexedAt ?? base.lastRefreshAttemptAt,
            lastSuccessfulRefreshAt: refreshState?.lastRefreshSucceededAt ?? latestSuccessful?.indexedAt ?? base.lastSuccessfulRefreshAt,
            lastRefreshFailedAt: refreshState?.lastRefreshFailedAt ?? base.lastRefreshFailedAt,
            lastRefreshTrigger: refreshState?.lastRefreshTrigger ?? base.lastRefreshTrigger,
            lastRefreshOutcome: refreshState?.lastRefreshOutcome ?? base.lastRefreshOutcome,
            lastRefreshFailureReason: refreshState?.lastRefreshFailureReason ?? base.lastRefreshFailureReason,
            latestCandidateSnapshotID: refreshState?.latestCandidateSnapshotID ?? latest?.snapshotID ?? base.latestCandidateSnapshotID,
            latestCandidateCompatibility: refreshState?.latestCandidateCompatibility ?? latest?.compatibilityClassification ?? base.latestCandidateCompatibility,
            latestCandidateEligibleForActivation: refreshState?.latestCandidateEligibleForActivation ?? latestCandidateEligibleForActivation ?? base.latestCandidateEligibleForActivation,
            activeSnapshotID: activationState.activeSnapshotID ?? base.activeSnapshotID,
            lastKnownGoodSnapshotID: activationState.lastKnownGoodSnapshotID ?? base.lastKnownGoodSnapshotID,
            activationMetadata: activationMetadata,
            readiness: readiness,
            syncState: syncState
        )

        return descriptor.withLiveMetadata(merged)
    }

    private func isSuccessfulRefreshCandidate(_ version: StoredSnapshotVersion) -> Bool {
        version.compatibilityClassification == .compatible
            && version.activationEligibility.state == .eligible
    }

    private func promoteRequiresConfirmation(
        source: FlowDatasetSource,
        activationState: SnapshotActivationState,
        latestCandidate: StoredSnapshotVersion?,
        latestCandidateDecision: SnapshotActivationDecision,
        rollbackDecision: SnapshotRollbackDecision
    ) -> Bool? {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: source,
                snapshotID: latestCandidate?.snapshotID,
                datasetVersion: latestCandidate?.datasetVersion,
                context: SnapshotActivationCommandContext(trigger: .operatorManual)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: activationState,
            candidateSnapshot: latestCandidate,
            rollbackTarget: rollbackDecision.target,
            activationDecision: latestCandidateDecision,
            rollbackDecision: rollbackDecision
        ).baselineDecision()
        return decision.status == .requiresConfirmation
    }

    private func demoteRequiresConfirmation(
        source: FlowDatasetSource,
        activationState: SnapshotActivationState,
        latestCandidate: StoredSnapshotVersion?,
        latestCandidateDecision: SnapshotActivationDecision,
        rollbackDecision: SnapshotRollbackDecision
    ) -> Bool? {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: source,
                expectedActiveSnapshotID: activationState.activeSnapshotID,
                preserveLastKnownGood: true,
                context: SnapshotActivationCommandContext(trigger: .operatorManual)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: activationState,
            candidateSnapshot: latestCandidate,
            rollbackTarget: rollbackDecision.target,
            activationDecision: latestCandidateDecision,
            rollbackDecision: rollbackDecision
        ).baselineDecision()
        return decision.status == .requiresConfirmation
    }

    private func rollbackRequiresConfirmation(
        source: FlowDatasetSource,
        activationState: SnapshotActivationState,
        latestCandidate: StoredSnapshotVersion?,
        latestCandidateDecision: SnapshotActivationDecision,
        rollbackDecision: SnapshotRollbackDecision
    ) -> Bool? {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: source,
                expectedActiveSnapshotID: activationState.activeSnapshotID,
                context: SnapshotActivationCommandContext(trigger: .operatorManual)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: activationState,
            candidateSnapshot: latestCandidate,
            rollbackTarget: rollbackDecision.target,
            activationDecision: latestCandidateDecision,
            rollbackDecision: rollbackDecision
        ).baselineDecision()
        return decision.status == .requiresConfirmation
    }
}

private extension DatasetOperatorActivationStatus {
    init(projectedStatus: ProjectedActivationStatus?) {
        switch projectedStatus {
        case .noHistory, .none:
            self = .noHistory
        case .inactive:
            self = .inactive
        case .inactiveCandidateReady:
            self = .inactiveCandidateReady
        case .active:
            self = .active
        case .activeRollbackReady:
            self = .activeRollbackReady
        case .attentionRequired:
            self = .attentionRequired
        }
    }
}
