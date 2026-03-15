import Foundation
import Combine

enum OperatorActionAvailability: String, Hashable {
    case allowed
    case requiresConfirmation
    case blocked
    case noOp
}

struct OperatorActionControl: Hashable {
    let action: SnapshotActivationCommand.Action
    let title: String
    let detail: String
    let availability: OperatorActionAvailability

    var canExecute: Bool {
        switch availability {
        case .allowed, .requiresConfirmation:
            return true
        case .blocked, .noOp:
            return false
        }
    }
}

struct OperatorControlsPanelState: Hashable {
    let source: FlowDatasetSource
    let activeSnapshotID: String?
    let lastKnownGoodSnapshotID: String?
    let latestCandidateSnapshotID: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
    let rollbackAvailable: Bool
    let latestActivationEventSummary: String?
    let operatorActivationStatus: DatasetOperatorActivationStatus
    let promote: OperatorActionControl
    let demote: OperatorActionControl
    let rollback: OperatorActionControl
    let recentHistory: [OperatorTimelineEntry]
    let timelineHistory: [OperatorTimelineEntry]
}

struct OperatorConfirmationPrompt: Identifiable, Hashable {
    let command: SnapshotActivationCommand
    let title: String
    let confirmButtonTitle: String
    let sourceTitle: String
    let currentActiveSnapshotID: String?
    let targetSnapshotID: String?
    let effectSummary: String

    var message: String {
        var lines: [String] = []
        lines.append("Source: \(sourceTitle)")
        if let currentActiveSnapshotID {
            lines.append("Current Active: \(currentActiveSnapshotID)")
        }
        if let targetSnapshotID {
            lines.append("Target: \(targetSnapshotID)")
        }
        lines.append(effectSummary)
        return lines.joined(separator: "\n")
    }

    var id: String {
        command.context.commandID
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var dataset: FlowDataset?
    @Published private(set) var descriptor: MobilityDatasetDescriptor?
    @Published private(set) var cacheStats: CacheDataSource.CacheStats?
    @Published private(set) var loadError: FlowNonFatalError?
    @Published private(set) var operatorControls: OperatorControlsPanelState?
    @Published private(set) var activationFeedback: String?
    @Published private(set) var isPerformingActivationAction = false
    @Published var confirmationPrompt: OperatorConfirmationPrompt?
    @Published var preferredSpatialLevelRaw: String

    private let flowRepositoryBuilder: (FlowDatasetSource) -> FlowRepository
    private let catalogRepository: MobilityCatalogRepository
    private let cacheDataSource: CacheDataSource
    private let versionStore: DatasetVersionStoring
    private let activationPolicy: SnapshotActivationPolicying
    private let activationExecutor: SnapshotActivationExecuting
    private let activationHistoryStore: SnapshotActivationHistoryStoring
    private let userDefaults: UserDefaults

    private let preferredSpatialLevelKey = "settings.preferred_spatial_level"
    private var currentSource: FlowDatasetSource = .bundledSample

    init(
        flowRepositoryBuilder: @escaping (FlowDatasetSource) -> FlowRepository = { source in
            MobilityRepositoryFactory.flowRepository(for: source)
        },
        catalogRepository: MobilityCatalogRepository = MobilityRepositoryFactory.liveAwareCatalogRepository(),
        cacheDataSource: CacheDataSource = .shared,
        versionStore: DatasetVersionStoring = MobilityRepositoryFactory.sharedVersionStore,
        activationPolicy: SnapshotActivationPolicying = MobilityRepositoryFactory.sharedActivationPolicy,
        activationExecutor: SnapshotActivationExecuting = DefaultSnapshotActivationExecutor(
            activationPolicy: MobilityRepositoryFactory.sharedActivationPolicy,
            versionStore: MobilityRepositoryFactory.sharedVersionStore,
            historyStore: MobilityRepositoryFactory.sharedActivationHistoryStore
        ),
        activationHistoryStore: SnapshotActivationHistoryStoring = MobilityRepositoryFactory.sharedActivationHistoryStore,
        userDefaults: UserDefaults = .standard
    ) {
        self.flowRepositoryBuilder = flowRepositoryBuilder
        self.catalogRepository = catalogRepository
        self.cacheDataSource = cacheDataSource
        self.versionStore = versionStore
        self.activationPolicy = activationPolicy
        self.activationExecutor = activationExecutor
        self.activationHistoryStore = activationHistoryStore
        self.userDefaults = userDefaults

        preferredSpatialLevelRaw = userDefaults.string(forKey: preferredSpatialLevelKey)
            ?? SpatialLevel.national.rawValue
    }

    func load(source: FlowDatasetSource) async {
        currentSource = source
        do {
            dataset = try await flowRepositoryBuilder(source).fetchDataset()
            let catalog = try await catalogRepository.fetchCatalog()
            descriptor = catalog.descriptor(for: source)
            operatorControls = await buildOperatorControls(for: source, descriptor: descriptor)
            loadError = nil
            activationFeedback = nil
        } catch {
            loadError = FlowLogger.nonFatalError(
                scope: .settings,
                userMessage: "Failed to load dataset settings.",
                underlying: error
            )
            dataset = nil
            descriptor = nil
            operatorControls = nil
        }
        await refreshCacheStats()
    }

    func savePreferredSpatialLevel(_ rawValue: String) {
        preferredSpatialLevelRaw = rawValue
        userDefaults.set(rawValue, forKey: preferredSpatialLevelKey)
    }

    func refreshCacheStats() async {
        cacheStats = await cacheDataSource.cacheStats()
    }

    func clearCache() async {
        await cacheDataSource.clearAll()
        await refreshCacheStats()
    }

    func triggerOperatorAction(_ action: SnapshotActivationCommand.Action) async {
        guard let command = await command(for: action, confirmed: false) else {
            activationFeedback = "Action unavailable for the current source."
            return
        }

        let decision = await guardDecision(for: command)
        switch decision.status {
        case .allowed:
            await execute(command)
        case .requiresConfirmation:
            confirmationPrompt = OperatorConfirmationPrompt(
                command: command,
                title: confirmationTitle(for: action),
                confirmButtonTitle: confirmationButtonTitle(for: action),
                sourceTitle: currentSource.title,
                currentActiveSnapshotID: descriptor?.liveMetadata?.activationMetadata?.activeSnapshotID,
                targetSnapshotID: confirmationTargetSnapshotID(for: action, decision: decision),
                effectSummary: confirmationEffectSummary(for: action, decision: decision)
            )
        case .blocked:
            activationFeedback = feedbackMessage(for: action, decision: decision, fallback: "Action is blocked.")
        case .noOp:
            activationFeedback = feedbackMessage(for: action, decision: decision, fallback: "Action is already satisfied.")
        }
    }

    func confirmPendingAction() async {
        guard let prompt = confirmationPrompt else { return }
        confirmationPrompt = nil
        await execute(replacingTrigger(in: prompt.command, with: .operatorConfirmed))
    }

    func dismissConfirmation() {
        confirmationPrompt = nil
    }

    private func execute(_ command: SnapshotActivationCommand) async {
        isPerformingActivationAction = true
        let result = await activationExecutor.execute(command)
        isPerformingActivationAction = false
        activationFeedback = feedbackMessage(for: result)
        await load(source: command.source)
        activationFeedback = feedbackMessage(for: result)
    }

    private func buildOperatorControls(
        for source: FlowDatasetSource,
        descriptor: MobilityDatasetDescriptor?
    ) async -> OperatorControlsPanelState? {
        guard let live = descriptor?.liveMetadata,
              live.supportsLiveRefresh,
              let activation = live.activationMetadata else {
            return nil
        }

        let promoteCommand = await command(for: .promote, confirmed: false)
        let demoteCommand = await command(for: .demote, confirmed: false)
        let rollbackCommand = await command(for: .rollback, confirmed: false)

        let promoteDecision: SnapshotActivationGuardDecision? = if let promoteCommand {
            await guardDecision(for: promoteCommand)
        } else {
            nil
        }
        let demoteDecision: SnapshotActivationGuardDecision? = if let demoteCommand {
            await guardDecision(for: demoteCommand)
        } else {
            nil
        }
        let rollbackDecision: SnapshotActivationGuardDecision? = if let rollbackCommand {
            await guardDecision(for: rollbackCommand)
        } else {
            nil
        }
        let timelineHistory = await activationHistoryStore.query(
            SnapshotActivationHistoryQuery(
                source: source,
                limit: 200,
                sortOrder: .newestFirst
            )
        )
        let mappedTimelineHistory = timelineHistory.map(OperatorHistoryPresentation.timelineEntry(from:))

        return OperatorControlsPanelState(
            source: source,
            activeSnapshotID: activation.activeSnapshotID,
            lastKnownGoodSnapshotID: activation.lastKnownGoodSnapshotID,
            latestCandidateSnapshotID: activation.latestCandidateSnapshotID,
            latestCandidateCompatibility: activation.latestCandidateCompatibility,
            latestCandidateEligibleForActivation: activation.latestCandidateEligibleForActivation,
            rollbackAvailable: activation.rollbackAvailable,
            latestActivationEventSummary: latestEventSummary(from: activation),
            operatorActivationStatus: activation.operatorActivationStatus,
            promote: actionControl(
                action: .promote,
                detail: activation.latestCandidateSnapshotID.map { "Candidate \($0)" } ?? "No candidate snapshot",
                decision: promoteDecision
            ),
            demote: actionControl(
                action: .demote,
                detail: activation.lastKnownGoodSnapshotID.map { "Fallback \($0)" } ?? "No safe fallback",
                decision: demoteDecision
            ),
            rollback: actionControl(
                action: .rollback,
                detail: activation.lastKnownGoodSnapshotID.map { "Restore \($0)" } ?? "No rollback target",
                decision: rollbackDecision
            ),
            recentHistory: Array(mappedTimelineHistory.prefix(5)),
            timelineHistory: mappedTimelineHistory
        )
    }

    private func command(
        for action: SnapshotActivationCommand.Action,
        confirmed: Bool
    ) async -> SnapshotActivationCommand? {
        let trigger: SnapshotActivationCommandTrigger = confirmed ? .operatorConfirmed : .operatorManual
        let context = SnapshotActivationCommandContext(trigger: trigger)

        switch action {
        case .promote:
            guard let live = descriptor?.liveMetadata,
                  let snapshotID = live.activationMetadata?.latestCandidateSnapshotID ?? live.latestCandidateSnapshotID else {
                return nil
            }
            let datasetVersion = live.activationMetadata?.latestCandidateDatasetVersion ?? live.latestKnownDatasetVersion
            return .promote(
                PromoteSnapshotCommand(
                    source: currentSource,
                    snapshotID: snapshotID,
                    datasetVersion: datasetVersion,
                    context: context
                )
            )
        case .demote:
            let expectedActiveSnapshotID = descriptor?.liveMetadata?.activationMetadata?.activeSnapshotID
            return .demote(
                DemoteSnapshotCommand(
                    source: currentSource,
                    expectedActiveSnapshotID: expectedActiveSnapshotID,
                    preserveLastKnownGood: true,
                    context: context
                )
            )
        case .rollback:
            let expectedActiveSnapshotID = descriptor?.liveMetadata?.activationMetadata?.activeSnapshotID
            return .rollback(
                RollbackSnapshotCommand(
                    source: currentSource,
                    expectedActiveSnapshotID: expectedActiveSnapshotID,
                    context: context
                )
            )
        }
    }

    private func guardDecision(for command: SnapshotActivationCommand) async -> SnapshotActivationGuardDecision {
        let source = command.source
        let currentState = await activationPolicy.currentState(for: source)
        let rollbackDecision = await activationPolicy.evaluateRollback(source: source)
        let candidateSnapshot = await resolveCandidateSnapshot(for: command)
        let activationDecision: SnapshotActivationDecision?

        if case .promote(let promote) = command {
            activationDecision = await activationPolicy.evaluateActivation(
                source: source,
                requestedSnapshotID: promote.snapshotID ?? candidateSnapshot?.snapshotID
            )
        } else {
            activationDecision = nil
        }

        return SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: source != .bundledSample,
            currentState: currentState,
            candidateSnapshot: candidateSnapshot,
            rollbackTarget: rollbackDecision.target,
            activationDecision: activationDecision,
            rollbackDecision: rollbackDecision
        ).baselineDecision()
    }

    private func resolveCandidateSnapshot(for command: SnapshotActivationCommand) async -> StoredSnapshotVersion? {
        switch command {
        case .promote(let command):
            if let snapshotID = command.snapshotID {
                return await versionStore.snapshot(snapshotID: snapshotID)
            }
            if let datasetVersion = command.datasetVersion {
                return await versionStore.snapshot(source: command.source, datasetVersion: datasetVersion)
            }
            return nil
        case .demote(let command):
            guard let expectedActiveSnapshotID = command.expectedActiveSnapshotID else { return nil }
            return await versionStore.snapshot(snapshotID: expectedActiveSnapshotID)
        case .rollback(let command):
            guard let expectedActiveSnapshotID = command.expectedActiveSnapshotID else { return nil }
            return await versionStore.snapshot(snapshotID: expectedActiveSnapshotID)
        }
    }

    private func latestEventSummary(from activation: DatasetActivationMetadata) -> String? {
        guard let type = activation.latestActivationEventType,
              let at = activation.latestActivationEventAt else {
            return nil
        }
        return "\(type.replacingOccurrences(of: "_", with: " ")) at \(at)"
    }

    private func actionControl(
        action: SnapshotActivationCommand.Action,
        detail: String,
        decision: SnapshotActivationGuardDecision?
    ) -> OperatorActionControl {
        let availability: OperatorActionAvailability
        switch decision?.status {
        case .allowed:
            availability = .allowed
        case .requiresConfirmation:
            availability = .requiresConfirmation
        case .blocked, .none:
            availability = .blocked
        case .noOp:
            availability = .noOp
        }

        return OperatorActionControl(
            action: action,
            title: title(for: action),
            detail: stateLabel(for: availability, detail: detail),
            availability: availability
        )
    }

    private func title(for action: SnapshotActivationCommand.Action) -> String {
        switch action {
        case .promote:
            return "Promote Snapshot"
        case .demote:
            return "Demote to Fallback"
        case .rollback:
            return "Rollback"
        }
    }

    private func stateLabel(for availability: OperatorActionAvailability, detail: String) -> String {
        switch availability {
        case .allowed:
            return "Allowed. \(detail)"
        case .requiresConfirmation:
            return "Confirmation required. \(detail)"
        case .blocked:
            return "Blocked. \(detail)"
        case .noOp:
            return "No action needed. \(detail)"
        }
    }

    private func confirmationTitle(for action: SnapshotActivationCommand.Action) -> String {
        switch action {
        case .promote:
            return "Confirm Snapshot Promotion"
        case .demote:
            return "Confirm Safe Demotion"
        case .rollback:
            return "Confirm Rollback"
        }
    }

    private func confirmationButtonTitle(for action: SnapshotActivationCommand.Action) -> String {
        switch action {
        case .promote:
            return "Promote"
        case .demote:
            return "Demote"
        case .rollback:
            return "Rollback"
        }
    }

    private func confirmationTargetSnapshotID(
        for action: SnapshotActivationCommand.Action,
        decision: SnapshotActivationGuardDecision
    ) -> String? {
        switch action {
        case .promote:
            return decision.candidateSnapshotID ?? descriptor?.liveMetadata?.activationMetadata?.latestCandidateSnapshotID
        case .demote:
            return decision.rollbackTargetSnapshotID ?? descriptor?.liveMetadata?.activationMetadata?.lastKnownGoodSnapshotID
        case .rollback:
            return decision.rollbackTargetSnapshotID ?? descriptor?.liveMetadata?.activationMetadata?.lastKnownGoodSnapshotID
        }
    }

    private func confirmationEffectSummary(
        for action: SnapshotActivationCommand.Action,
        decision: SnapshotActivationGuardDecision
    ) -> String {
        switch action {
        case .promote:
            let target = confirmationTargetSnapshotID(for: action, decision: decision) ?? "the candidate snapshot"
            return "This will replace the active snapshot with \(target)."
        case .demote:
            let target = confirmationTargetSnapshotID(for: action, decision: decision) ?? "the safe fallback"
            return "This will step down the active snapshot and restore \(target)."
        case .rollback:
            let target = confirmationTargetSnapshotID(for: action, decision: decision) ?? "the last-known-good snapshot"
            return "This will restore \(target) as the active snapshot."
        }
    }

    private func feedbackMessage(
        for action: SnapshotActivationCommand.Action,
        decision: SnapshotActivationGuardDecision,
        fallback: String
    ) -> String {
        if let detail = decision.details.first, !detail.isEmpty {
            return detail
        }
        switch decision.reasons.first {
        case .alreadyActive:
            return "\(title(for: action)) is already satisfied."
        case .alreadyInactive:
            return "No active snapshot to change."
        case .noRollbackTarget:
            return "No safe fallback is available."
        case .targetSnapshotIncompatible:
            return "The candidate snapshot is incompatible."
        case .targetSnapshotNotEligible:
            return "The candidate snapshot is not eligible for activation."
        case .targetSnapshotNotFound:
            return "The candidate snapshot could not be found."
        default:
            return fallback
        }
    }

    private func feedbackMessage(for result: SnapshotActivationExecutionResult) -> String {
        switch result.status {
        case .succeeded:
            return "\(title(for: result.command.action)) completed."
        case .blocked:
            return result.details.first ?? "Action blocked."
        case .failed:
            return result.details.first ?? "Action failed."
        case .noOp:
            return result.details.first ?? "No action needed."
        }
    }

    private func replacingTrigger(
        in command: SnapshotActivationCommand,
        with trigger: SnapshotActivationCommandTrigger
    ) -> SnapshotActivationCommand {
        switch command {
        case .promote(let promote):
            return .promote(
                PromoteSnapshotCommand(
                    source: promote.source,
                    snapshotID: promote.snapshotID,
                    datasetVersion: promote.datasetVersion,
                    context: SnapshotActivationCommandContext(
                        trigger: trigger,
                        requestedBy: promote.context.requestedBy,
                        note: promote.context.note
                    )
                )
            )
        case .demote(let demote):
            return .demote(
                DemoteSnapshotCommand(
                    source: demote.source,
                    expectedActiveSnapshotID: demote.expectedActiveSnapshotID,
                    preserveLastKnownGood: demote.preserveLastKnownGood,
                    context: SnapshotActivationCommandContext(
                        trigger: trigger,
                        requestedBy: demote.context.requestedBy,
                        note: demote.context.note
                    )
                )
            )
        case .rollback(let rollback):
            return .rollback(
                RollbackSnapshotCommand(
                    source: rollback.source,
                    expectedActiveSnapshotID: rollback.expectedActiveSnapshotID,
                    context: SnapshotActivationCommandContext(
                        trigger: trigger,
                        requestedBy: rollback.context.requestedBy,
                        note: rollback.context.note
                    )
                )
            )
        }
    }
}
