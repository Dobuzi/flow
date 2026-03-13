import Foundation
import Testing
@testable import Flow

@MainActor
struct SettingsViewModelTests {
    @Test
    func staticSourceDoesNotExposeOperatorControls() async throws {
        let dataset = makeDataset(source: .bundledSample)
        let descriptor = makeDescriptor(source: .bundledSample, live: nil)
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: dataset) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .bundledSample,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.static.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .bundledSample)

        #expect(viewModel.operatorControls == nil)
    }

    @Test
    func liveSourceShowsOperatorMetadataAndConfirmationRequiredPromote() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.03", datasetVersion: "2026.03", indexedAt: "2026-03-08T01:00:00Z")
        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.04", datasetVersion: "2026.04", indexedAt: "2026-04-08T01:00:00Z")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let activation = DatasetActivationMetadata(
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: nil,
            latestCandidateSnapshotID: "seoul-2026.04",
            latestCandidateDatasetVersion: "2026.04",
            latestCandidateCompatibility: .compatible,
            latestCandidateEligibleForActivation: true,
            rollbackAvailable: false,
            latestActivationEventType: nil,
            latestActivationEventAt: nil,
            operatorActivationStatus: .active,
            promoteRequiresConfirmation: true,
            demoteRequiresConfirmation: false,
            rollbackRequiresConfirmation: false
        )
        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(source: .seoulCapitalSnapshot, activation: activation)
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.live.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)

        let controls = try #require(viewModel.operatorControls)
        #expect(controls.activeSnapshotID == "seoul-2026.03")
        #expect(controls.latestCandidateSnapshotID == "seoul-2026.04")
        #expect(controls.promote.availability == OperatorActionAvailability.requiresConfirmation)
        #expect(controls.demote.availability == OperatorActionAvailability.blocked)
        #expect(controls.rollback.availability == OperatorActionAvailability.blocked)
        #expect(controls.recentHistory.isEmpty)
    }

    @Test
    func confirmationRequiredActionDoesNotExecuteWithoutConfirmation() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.03", datasetVersion: "2026.03", indexedAt: "2026-03-08T01:00:00Z")
        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.04", datasetVersion: "2026.04", indexedAt: "2026-04-08T01:00:00Z")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: false,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .active,
                    promoteRequiresConfirmation: true,
                    demoteRequiresConfirmation: false,
                    rollbackRequiresConfirmation: false
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.confirm.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(SnapshotActivationCommand.Action.promote)

        let prompt = try #require(viewModel.confirmationPrompt)
        #expect(prompt.title == "Confirm Snapshot Promotion")
        #expect(prompt.confirmButtonTitle == "Promote")
        #expect(prompt.sourceTitle == FlowDatasetSource.seoulCapitalSnapshot.title)
        #expect(prompt.currentActiveSnapshotID == "seoul-2026.03")
        #expect(prompt.targetSnapshotID == "seoul-2026.04")
        #expect(prompt.effectSummary == "This will replace the active snapshot with seoul-2026.04.")
        #expect(prompt.message.contains("Source: Seoul Capital"))
        #expect(prompt.message.contains("Current Active: seoul-2026.03"))
        #expect(prompt.message.contains("Target: seoul-2026.04"))
        #expect(await executor.executedCommands().isEmpty)
    }

    @Test
    func demoteConfirmationContentIsActionSpecific() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.03", datasetVersion: "2026.03", indexedAt: "2026-03-08T01:00:00Z")
        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.02", datasetVersion: "2026.02", indexedAt: "2026-02-08T01:00:00Z")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.03",
                    latestCandidateDatasetVersion: "2026.03",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: false,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.demote.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(SnapshotActivationCommand.Action.demote)

        let prompt = try #require(viewModel.confirmationPrompt)
        #expect(prompt.title == "Confirm Safe Demotion")
        #expect(prompt.confirmButtonTitle == "Demote")
        #expect(prompt.currentActiveSnapshotID == "seoul-2026.03")
        #expect(prompt.targetSnapshotID == "seoul-2026.02")
        #expect(prompt.effectSummary == "This will step down the active snapshot and restore seoul-2026.02.")
        #expect(await executor.executedCommands().isEmpty)
    }

    @Test
    func rollbackConfirmationContentIsActionSpecific() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.03", datasetVersion: "2026.03", indexedAt: "2026-03-08T01:00:00Z")
        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.02", datasetVersion: "2026.02", indexedAt: "2026-02-08T01:00:00Z")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.03",
                    latestCandidateDatasetVersion: "2026.03",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: false,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.rollback.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(SnapshotActivationCommand.Action.rollback)

        let prompt = try #require(viewModel.confirmationPrompt)
        #expect(prompt.title == "Confirm Rollback")
        #expect(prompt.confirmButtonTitle == "Rollback")
        #expect(prompt.currentActiveSnapshotID == "seoul-2026.03")
        #expect(prompt.targetSnapshotID == "seoul-2026.02")
        #expect(prompt.effectSummary == "This will restore seoul-2026.02 as the active snapshot.")
        #expect(await executor.executedCommands().isEmpty)
    }

    @Test
    func recentActivityRemainsCompatibleWithPersistentHistoryStore() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("SettingsPersistentHistory", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
        let historyStore = PersistentSnapshotActivationHistoryStore(fileURL: historyFileURL)

        await historyStore.append(
            makeHistoryEvent(
                eventID: "evt-persisted-promote",
                type: .promoteSucceeded,
                timestamp: "2026-03-11T00:00:01Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                status: .succeeded,
                message: "Promotion completed."
            )
        )

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.04",
                    lastKnownGoodSnapshotID: "seoul-2026.03",
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: "promote_succeeded",
                    latestActivationEventAt: "2026-03-11T00:00:01Z",
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: false,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: PersistentSnapshotActivationHistoryStore(fileURL: historyFileURL),
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.persistentHistory.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)

        let controls = try #require(viewModel.operatorControls)
        #expect(controls.recentHistory.count == 1)
        #expect(controls.recentHistory[0].id == "evt-persisted-promote")
        #expect(controls.recentHistory[0].title == "Promote Succeeded")
        #expect(controls.recentHistory[0].status == "Succeeded")
        #expect(controls.recentHistory[0].snapshotID == "seoul-2026.04")
    }

    @Test
    func blockedActionDoesNotExecute() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: nil,
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: nil,
                    latestCandidateDatasetVersion: nil,
                    latestCandidateCompatibility: nil,
                    latestCandidateEligibleForActivation: nil,
                    rollbackAvailable: false,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .noHistory,
                    promoteRequiresConfirmation: nil,
                    demoteRequiresConfirmation: nil,
                    rollbackRequiresConfirmation: nil
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.blocked.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(SnapshotActivationCommand.Action.promote)

        #expect(viewModel.confirmationPrompt == nil)
        #expect(await executor.executedCommands().isEmpty)
        #expect(viewModel.activationFeedback != nil)
    }

    @Test
    func allowedActionExecutesWithoutConfirmation() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.04", datasetVersion: "2026.04", indexedAt: "2026-04-08T01:00:00Z")

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: nil,
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: false,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .inactiveCandidateReady,
                    promoteRequiresConfirmation: false,
                    demoteRequiresConfirmation: nil,
                    rollbackRequiresConfirmation: nil
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.allowed.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(SnapshotActivationCommand.Action.promote)

        let commands = await executor.executedCommands()
        #expect(commands.count == 1)
        #expect(commands.first?.context.trigger == .operatorManual)
        #expect(viewModel.confirmationPrompt == nil)
    }

    @Test
    func confirmedActionRoutesThroughExecutorWithConfirmedTrigger() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.03", datasetVersion: "2026.03", indexedAt: "2026-03-08T01:00:00Z")
        await seed(store: store, source: .seoulCapitalSnapshot, snapshotID: "seoul-2026.04", datasetVersion: "2026.04", indexedAt: "2026-04-08T01:00:00Z")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: nil,
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: false,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .active,
                    promoteRequiresConfirmation: true,
                    demoteRequiresConfirmation: false,
                    rollbackRequiresConfirmation: false
                )
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.confirmed-run.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)
        await viewModel.triggerOperatorAction(.promote)
        await viewModel.confirmPendingAction()

        let commands = await executor.executedCommands()
        #expect(commands.count == 1)
        #expect(commands.first?.context.trigger == .operatorConfirmed)
        #expect(viewModel.confirmationPrompt == nil)
    }

    @Test
    func liveSourceShowsRecentActivationHistoryInNewestFirstOrder() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: "rollback_succeeded",
                    latestActivationEventAt: "2026-03-10T11:00:00Z",
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: true,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        await historyStore.append(
            makeHistoryEvent(
                eventID: "older",
                type: .promoteSucceeded,
                timestamp: "2026-03-10T09:00:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                status: .succeeded,
                message: "Promote completed."
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                eventID: "newer",
                type: .rollbackBlocked,
                timestamp: "2026-03-10T11:00:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.02",
                status: .blocked,
                message: "No safe rollback target."
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.history.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)

        let controls = try #require(viewModel.operatorControls)
        #expect(controls.recentHistory.count == 2)
        #expect(controls.recentHistory[0].title == "Rollback Blocked")
        #expect(controls.recentHistory[0].status == "Blocked")
        #expect(controls.recentHistory[0].snapshotID == "seoul-2026.02")
        #expect(controls.recentHistory[0].detail == "No safe rollback target.")
        #expect(controls.recentHistory[1].title == "Promote Succeeded")
        #expect(controls.recentHistory[1].status == "Succeeded")
        #expect(controls.recentHistory[1].snapshotID == "seoul-2026.03")
    }

    @Test
    func historyIsScopedToSelectedSource() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: nil,
                    latestActivationEventAt: nil,
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: true,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        await historyStore.append(
            makeHistoryEvent(
                eventID: "seoul",
                type: .promoteSucceeded,
                timestamp: "2026-03-10T10:00:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                status: .succeeded
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                eventID: "national",
                type: .rollbackSucceeded,
                timestamp: "2026-03-10T11:00:00Z",
                source: .koreaNational,
                snapshotID: "national-2026.03",
                status: .succeeded
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.history-scope.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)

        let controls = try #require(viewModel.operatorControls)
        #expect(controls.recentHistory.count == 1)
        #expect(controls.recentHistory[0].snapshotID == "seoul-2026.04")
        #expect(controls.recentHistory[0].title == "Promote Succeeded")
    }

    @Test
    func recentActivityOrderingMatchesHistoryStoreAcrossAuditOutcomes() async throws {
        let store = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: store)
        let executor = RecordingActivationExecutor()
        let historyStore = InMemorySnapshotActivationHistoryStore()

        let descriptor = makeDescriptor(
            source: .seoulCapitalSnapshot,
            live: makeLiveMetadata(
                source: .seoulCapitalSnapshot,
                activation: DatasetActivationMetadata(
                    activeSnapshotID: "seoul-2026.03",
                    lastKnownGoodSnapshotID: "seoul-2026.02",
                    latestCandidateSnapshotID: "seoul-2026.04",
                    latestCandidateDatasetVersion: "2026.04",
                    latestCandidateCompatibility: .compatible,
                    latestCandidateEligibleForActivation: true,
                    rollbackAvailable: true,
                    latestActivationEventType: "promote_succeeded",
                    latestActivationEventAt: "2026-03-12T12:03:00Z",
                    operatorActivationStatus: .activeRollbackReady,
                    promoteRequiresConfirmation: true,
                    demoteRequiresConfirmation: true,
                    rollbackRequiresConfirmation: true
                )
            )
        )

        await historyStore.append(
            makeHistoryEvent(
                eventID: "evt-requested",
                type: .promoteRequested,
                timestamp: "2026-03-12T12:01:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                status: .requested
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                eventID: "evt-blocked",
                type: .rollbackBlocked,
                timestamp: "2026-03-12T12:02:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.02",
                status: .blocked,
                message: "No safe rollback target."
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                eventID: "evt-succeeded",
                type: .promoteSucceeded,
                timestamp: "2026-03-12T12:03:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                status: .succeeded
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                eventID: "evt-noop",
                type: .demoteBlocked,
                timestamp: "2026-03-12T12:04:00Z",
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                status: .noOp,
                message: "Already inactive."
            )
        )

        let viewModel = SettingsViewModel(
            flowRepositoryBuilder: { _ in StubFlowRepository(dataset: makeDataset(source: .seoulCapitalSnapshot)) },
            catalogRepository: StubCatalogRepository(
                catalog: MobilityDatasetCatalog(
                    version: "1",
                    defaultSource: .seoulCapitalSnapshot,
                    datasets: [descriptor]
                )
            ),
            versionStore: store,
            activationPolicy: policy,
            activationExecutor: executor,
            activationHistoryStore: historyStore,
            userDefaults: UserDefaults(suiteName: "SettingsViewModelTests.audit-order.\(UUID().uuidString)")!
        )

        await viewModel.load(source: .seoulCapitalSnapshot)

        let controls = try #require(viewModel.operatorControls)
        #expect(controls.recentHistory.count == 4)
        #expect(controls.recentHistory.map(\.id) == ["evt-noop", "evt-succeeded", "evt-blocked", "evt-requested"])
        #expect(controls.recentHistory.map(\.status) == ["No-op", "Succeeded", "Blocked", "Requested"])
        #expect(controls.recentHistory[0].title == "Demote Blocked")
        #expect(controls.recentHistory[0].detail == "Already inactive.")
        #expect(controls.recentHistory[1].title == "Promote Succeeded")
        #expect(controls.recentHistory[2].title == "Rollback Blocked")
        #expect(controls.recentHistory[2].detail == "No safe rollback target.")
        #expect(controls.recentHistory[3].title == "Promote Requested")
    }

    private func makeDataset(source: FlowDatasetSource) -> FlowDataset {
        FlowDataset(
            datasetID: source.rawValue,
            version: "2026.03",
            source: source.rawValue,
            createdAt: "2026-03-01T00:00:00Z",
            spatialLevel: .city,
            timeCoverage: "2026-03-01~2026-03-31",
            recordsCount: 100,
            schemaVersion: "1.0.0"
        )
    }

    private func makeDescriptor(source: FlowDatasetSource, live: DatasetLiveMetadata?) -> MobilityDatasetDescriptor {
        MobilityDatasetDescriptor(
            id: source.rawValue,
            datasetID: source.rawValue,
            source: source,
            providerID: "test",
            displayName: source.title,
            version: "2026.03",
            schemaVersion: "1.0.0",
            updatedAt: "2026-03-01T00:00:00Z",
            availableModes: TransportMode.allCases,
            supportedSpatialLevels: SpatialLevel.allCases,
            supportedGranularities: [.year, .month, .hourOfDay],
            reliability: .high,
            spatialPrecision: .city,
            temporalPrecision: .day,
            qualityScore: 1.0,
            liveMetadata: live
        )
    }

    private func makeLiveMetadata(source: FlowDatasetSource, activation: DatasetActivationMetadata) -> DatasetLiveMetadata {
        DatasetLiveMetadata(
            supportsLiveRefresh: source != .bundledSample,
            latestKnownDatasetVersion: activation.latestCandidateDatasetVersion,
            latestKnownSnapshotID: activation.latestCandidateSnapshotID,
            lastRefreshAttemptAt: nil,
            lastSuccessfulRefreshAt: nil,
            lastRefreshFailedAt: nil,
            lastRefreshTrigger: nil,
            lastRefreshOutcome: nil,
            lastRefreshFailureReason: nil,
            latestCandidateSnapshotID: activation.latestCandidateSnapshotID,
            latestCandidateCompatibility: activation.latestCandidateCompatibility,
            latestCandidateEligibleForActivation: activation.latestCandidateEligibleForActivation,
            activeSnapshotID: activation.activeSnapshotID,
            lastKnownGoodSnapshotID: activation.lastKnownGoodSnapshotID,
            activationMetadata: activation,
            readiness: .ready,
            syncState: .ready
        )
    }

    private func seed(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        indexedAt: String
    ) async {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: indexedAt,
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 100,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: indexedAt
        )
    }

    private func makeHistoryEvent(
        eventID: String,
        type: SnapshotActivationEventType,
        timestamp: String,
        source: FlowDatasetSource,
        snapshotID: String?,
        status: SnapshotActivationEventStatus,
        message: String? = nil
    ) -> SnapshotActivationHistoryEvent {
        SnapshotActivationHistoryEvent(
            eventID: eventID,
            type: type,
            timestamp: timestamp,
            metadata: SnapshotActivationEventMetadata(
                source: source,
                snapshotID: snapshotID,
                datasetVersion: snapshotID,
                commandID: "cmd-\(eventID)",
                commandAction: action(for: type),
                trigger: .operatorManual,
                requestedBy: nil,
                note: nil,
                validation: nil,
                guardDecision: nil,
                execution: nil
            ),
            result: SnapshotActivationEventResult(
                status: status,
                reasonCode: nil,
                message: message
            )
        )
    }

    private func action(for type: SnapshotActivationEventType) -> SnapshotActivationCommand.Action {
        switch type {
        case .promoteRequested, .promoteSucceeded, .promoteBlocked, .promoteFailed:
            return .promote
        case .demoteRequested, .demoteSucceeded, .demoteBlocked, .demoteFailed:
            return .demote
        case .rollbackRequested, .rollbackSucceeded, .rollbackBlocked, .rollbackFailed:
            return .rollback
        }
    }
}

private struct StubFlowRepository: FlowRepository {
    let dataset: FlowDataset

    func fetchDataset() async throws -> FlowDataset { dataset }
    func fetchFlowRecords() async throws -> [FlowRecord] { [] }
}

private struct StubCatalogRepository: MobilityCatalogRepository {
    let catalog: MobilityDatasetCatalog

    func fetchCatalog() async throws -> MobilityDatasetCatalog { catalog }
}

private actor RecordingActivationExecutor: SnapshotActivationExecuting {
    private var commands: [SnapshotActivationCommand] = []

    func execute(_ command: SnapshotActivationCommand) async -> SnapshotActivationExecutionResult {
        commands.append(command)
        return .succeeded(
            command: command,
            previousState: SnapshotActivationState(
                source: command.source,
                activeSnapshotID: nil,
                lastKnownGoodSnapshotID: nil,
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            resultingState: SnapshotActivationState(
                source: command.source,
                activeSnapshotID: command.targetSnapshotID,
                lastKnownGoodSnapshotID: nil,
                updatedAt: "2026-03-10T00:01:00Z"
            )
        )
    }

    func executedCommands() -> [SnapshotActivationCommand] {
        commands
    }
}

private extension SnapshotActivationCommand {
    var targetSnapshotID: String? {
        switch self {
        case .promote(let command):
            return command.snapshotID
        case .demote(let command):
            return command.expectedActiveSnapshotID
        case .rollback(let command):
            return command.expectedActiveSnapshotID
        }
    }
}
