import Testing
@testable import Flow

struct SnapshotActivationExecutorTests {
    @Test
    func promoteHistorySequenceAndMetadataStayAuditCorrect() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                datasetVersion: "2026.04",
                context: .init(
                    commandID: "cmd-promote-audit-sequence",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .succeeded)

        let history = await historyStore.query(
            SnapshotActivationHistoryQuery(
                commandID: "cmd-promote-audit-sequence",
                sortOrder: .oldestFirst
            )
        )
        #expect(history.count == 2)
        #expect(history[0].type == .promoteRequested)
        #expect(history[1].type == .promoteSucceeded)
        #expect(history[0].result.status == .requested)
        #expect(history[1].result.status == .succeeded)
        #expect(history[0].metadata.commandID == "cmd-promote-audit-sequence")
        #expect(history[1].metadata.commandID == "cmd-promote-audit-sequence")
        #expect(history[0].metadata.source == .seoulCapitalSnapshot)
        #expect(history[1].metadata.source == .seoulCapitalSnapshot)
        #expect(history[0].metadata.snapshotID == "seoul-2026.04")
        #expect(history[1].metadata.snapshotID == "seoul-2026.04")
        #expect(history[1].metadata.execution?.status == .succeeded)
    }

    @Test
    func promoteCommandRunsValidationGuardExecutionAndStoresHistory() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(
                    commandID: "cmd-promote-success",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .succeeded)
        #expect(result.resultingState?.activeSnapshotID == "seoul-2026.04")

        let history = await historyStore.events(commandID: "cmd-promote-success")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .promoteRequested }))
        #expect(history.contains(where: { $0.type == .promoteSucceeded }))
    }

    @Test
    func riskyPromoteRequiresConfirmationForManualTrigger() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(
                    commandID: "cmd-promote-requires-confirmation",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .policyRejected)
        #expect(result.details.contains("requires_confirmation"))
        #expect(result.details.contains("active_snapshot_change"))

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)
    }

    @Test
    func invalidCommandFailsEarlyAndStoresFailureEvent() async {
        let versionStore = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: nil,
                datasetVersion: nil,
                context: .init(
                    commandID: "cmd-invalid",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .failed)
        #expect(result.failureReason == .policyEvaluationFailed)

        let history = await historyStore.events(commandID: "cmd-invalid")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .promoteRequested }))
        #expect(history.contains(where: { $0.type == .promoteFailed }))
    }

    @Test
    func blockedGuardCommandProducesBlockedResult() async {
        let versionStore = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .bundledSample,
                snapshotID: "sample-2026.01",
                context: .init(
                    commandID: "cmd-static-block",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .blocked)
        #expect(result.blockReason == .policyRejected)
        let stateAfter = await policy.currentState(for: .bundledSample)
        #expect(stateAfter.activeSnapshotID == nil)
        #expect(stateAfter.lastKnownGoodSnapshotID == nil)

        let history = await historyStore.events(commandID: "cmd-static-block")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .promoteBlocked }))
    }

    @Test
    func rollbackCommandCanSucceedWhenRecoveryTriggerIsUsed() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-03-02T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(
                    commandID: "cmd-rollback-success",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .recoveryRollback
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .succeeded)
        #expect(result.resultingState?.activeSnapshotID == "seoul-2026.02")
        #expect(result.resultingState?.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(result.details.contains("rollback_executed"))
        #expect(result.details.contains("rollback_target_restored"))
        #expect(result.details.contains("last_known_good_preserved"))

        let history = await historyStore.events(commandID: "cmd-rollback-success")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .rollbackRequested }))
        #expect(history.contains(where: { $0.type == .rollbackSucceeded }))
    }

    @Test
    func demoteHistorySequenceAndProjectionStayAligned() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-03-02T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-demote-audit-sequence",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .succeeded)

        let history = await historyStore.query(
            SnapshotActivationHistoryQuery(
                commandID: "cmd-demote-audit-sequence",
                sortOrder: .oldestFirst
            )
        )
        #expect(history.count == 2)
        #expect(history[0].type == .demoteRequested)
        #expect(history[1].type == .demoteSucceeded)
        #expect(history[1].result.status == .succeeded)

        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: versionStore
        )
        let projected = await projector.project(for: .seoulCapitalSnapshot)
        #expect(projected.activeSnapshotID == "seoul-2026.02")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(projected.latestActivationEvent?.type == .demoteSucceeded)
    }

    @Test
    func demoteCommandSucceedsWhenSafeFallbackIsAvailableAndConfirmed() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-03-02T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-demote-success",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .succeeded)
        #expect(result.resultingState?.activeSnapshotID == "seoul-2026.02")
        #expect(result.resultingState?.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(result.details.contains("demoted_to_safe_fallback"))
        #expect(result.details.contains("safe_fallback_restored"))
        #expect(result.details.contains("last_known_good_preserved"))
        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter.activeSnapshotID == "seoul-2026.02")
        #expect(stateAfter.lastKnownGoodSnapshotID == "seoul-2026.03")

        let history = await historyStore.events(commandID: "cmd-demote-success")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .demoteRequested }))
        #expect(history.contains(where: { $0.type == .demoteSucceeded }))

        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: versionStore
        )
        let projected = await projector.project(for: .seoulCapitalSnapshot)
        #expect(projected.activeSnapshotID == "seoul-2026.02")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(projected.latestActivationEvent?.type == .demoteSucceeded)
        #expect(projected.rollbackAvailable)
    }

    @Test
    func rollbackBlocksClearlyWhenNoSafeRollbackTargetExists() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(
                    commandID: "cmd-rollback-no-safe-target",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .recoveryRollback
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .noRollbackTarget)

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)

        let history = await historyStore.events(commandID: "cmd-rollback-no-safe-target")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .rollbackBlocked }))
    }

    @Test
    func rollbackNoOpIsSurfacedWhenTargetIsAlreadyActive() async throws {
        let rollbackTarget = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            compatibility: .compatible,
            activationState: .eligible
        )
        let policy = StubRollbackPolicy(
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: "seoul-2026.03",
                updatedAt: "2026-03-12T00:00:00Z"
            ),
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .rollbackAvailable,
                target: rollbackTarget,
                reasons: []
            )
        )
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: InMemoryDatasetVersionStore(),
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(
                    commandID: "cmd-rollback-noop",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .recoveryRollback
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .noOp)
        #expect(result.blockReason == .alreadyActive)
        #expect(await policy.rollbackCallCount == 0)
    }

    @Test
    func rollbackBlocksClearlyWhenFallbackTargetIsIncompatible() async {
        let incompatibleTarget = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02-bad",
            compatibility: .incompatible,
            activationState: .ineligible
        )
        let currentState = SnapshotActivationState(
            source: .seoulCapitalSnapshot,
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: "seoul-2026.02-bad",
            updatedAt: "2026-03-12T00:00:00Z"
        )
        let policy = StubRollbackPolicy(
            currentState: currentState,
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .noSafeRollback,
                target: incompatibleTarget,
                reasons: ["last_known_good_not_activatable", "compatibility_incompatible"]
            )
        )
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: InMemoryDatasetVersionStore(),
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(
                    commandID: "cmd-rollback-incompatible-target",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .recoveryRollback
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .snapshotIncompatible)
        #expect(result.previousState == currentState)
        #expect(await policy.rollbackCallCount == 0)

        let history = await historyStore.events(commandID: "cmd-rollback-incompatible-target")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .rollbackBlocked }))
    }

    @Test
    func noOpCommandIsSurfacedConsistently() async {
        let versionStore = InMemoryDatasetVersionStore()
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: nil,
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-demote-noop",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .noOp)
        #expect(result.blockReason == .alreadyInactive)
        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter.activeSnapshotID == nil)
        #expect(stateAfter.lastKnownGoodSnapshotID == nil)

        let history = await historyStore.query(
            SnapshotActivationHistoryQuery(
                commandID: "cmd-demote-noop",
                sortOrder: .oldestFirst
            )
        )
        #expect(history.count == 2)
        #expect(history[0].type == .demoteRequested)
        #expect(history[1].type == .demoteBlocked)
        #expect(history[1].result.status == .noOp)
        #expect(history.contains(where: { $0.type == .demoteBlocked }))
        #expect(history.contains(where: { $0.type == .demoteSucceeded }) == false)
    }

    @Test
    func demoteBlocksWhenNoSafeFallbackExists() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-demote-blocked-no-fallback",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .noRollbackTarget)

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)

        let history = await historyStore.events(commandID: "cmd-demote-blocked-no-fallback")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .demoteBlocked }))
    }

    @Test
    func demoteRequiresConfirmationForManualTrigger() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            datasetVersion: "2026.02",
            generatedAt: "2026-03-02T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.02")
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(
                    commandID: "cmd-demote-requires-confirmation",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .policyRejected)
        #expect(result.details.contains("requires_confirmation"))

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)
    }

    @Test
    func promotePreservesLastKnownGoodAndProjectionRemainsConsistent() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z"
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(
                    commandID: "cmd-promote-lkg",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .succeeded)
        #expect(result.resultingState?.activeSnapshotID == "seoul-2026.04")
        #expect(result.resultingState?.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(result.details.contains("last_known_good_preserved"))

        let projector = DefaultSnapshotActivationStateProjector(
            activationPolicy: policy,
            historyStore: historyStore,
            versionStore: versionStore
        )
        let projected = await projector.project(for: .seoulCapitalSnapshot)
        #expect(projected.activeSnapshotID == "seoul-2026.04")
        #expect(projected.lastKnownGoodSnapshotID == "seoul-2026.03")
        #expect(projected.rollbackAvailable)
    }

    @Test
    func blockedPromotionDoesNotMutateActivationState() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04-partial",
            datasetVersion: "2026.04",
            generatedAt: "2026-03-04T00:00:00Z",
            compatibilityClassification: .partiallyCompatible,
            eligibilityState: .ineligible,
            compatibilityReasons: ["required_fields_missing"],
            activationReasons: ["required_fields_missing"]
        )

        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04-partial",
                context: .init(
                    commandID: "cmd-promote-blocked-no-mutate",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .blocked)
        #expect(result.blockReason == .snapshotIncompatible || result.blockReason == .snapshotNotEligible)

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)
    }

    @Test
    func failedCommandDoesNotMutateActivationState() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        await seedVersion(
            store: versionStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-03T00:00:00Z"
        )
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        _ = try await policy.activate(source: .seoulCapitalSnapshot, requestedSnapshotID: "seoul-2026.03")
        let stateBefore = await policy.currentState(for: .seoulCapitalSnapshot)

        let historyStore = InMemorySnapshotActivationHistoryStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let invalid = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: nil,
                datasetVersion: nil,
                context: .init(
                    commandID: "cmd-invalid-no-mutate",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(invalid)
        #expect(result.status == .failed)
        #expect(result.failureReason == .policyEvaluationFailed)

        let stateAfter = await policy.currentState(for: .seoulCapitalSnapshot)
        #expect(stateAfter == stateBefore)
    }

    @Test
    func failedExecutionRecordsRequestedThenFailedAuditEvents() async {
        let failingState = SnapshotActivationState(
            source: .seoulCapitalSnapshot,
            activeSnapshotID: "seoul-2026.03",
            lastKnownGoodSnapshotID: nil,
            updatedAt: "2026-03-12T00:00:00Z"
        )
        let candidate = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            compatibility: .compatible,
            activationState: .eligible
        )
        let policy = ThrowingActivatePolicy(
            currentState: failingState,
            candidateSnapshot: candidate
        )
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let versionStore = InMemoryDatasetVersionStore()
        let executor = DefaultSnapshotActivationExecutor(
            activationPolicy: policy,
            versionStore: versionStore,
            historyStore: historyStore
        )

        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(
                    commandID: "cmd-promote-failed-audit",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorConfirmed
                )
            )
        )

        let result = await executor.execute(command)
        #expect(result.status == .failed)
        #expect(result.failureReason == .stateMutationFailed)

        let history = await historyStore.query(
            SnapshotActivationHistoryQuery(
                commandID: "cmd-promote-failed-audit",
                sortOrder: .oldestFirst
            )
        )
        #expect(history.count == 2)
        #expect(history[0].type == .promoteRequested)
        #expect(history[1].type == .promoteFailed)
        #expect(history[1].result.status == .failed)
        #expect(history[1].metadata.commandID == "cmd-promote-failed-audit")
        #expect(history[1].metadata.source == .seoulCapitalSnapshot)
    }

    private func seedVersion(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String,
        compatibilityClassification: IngestionCompatibilityClassification = .compatible,
        eligibilityState: SnapshotActivationEligibility.State = .eligible,
        compatibilityReasons: [String] = [],
        activationReasons: [String] = []
    ) async {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: generatedAt,
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 100,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: compatibilityClassification != .incompatible,
                isCompatibilityCheckPassed: compatibilityClassification == .compatible,
                compatibilityReasons: compatibilityReasons,
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: eligibilityState, reasons: activationReasons)
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: compatibilityClassification,
            isIngestionCandidate: true,
            indexedAt: generatedAt
        )
    }

    private func makeStoredSnapshot(
        source: FlowDatasetSource,
        snapshotID: String,
        compatibility: IngestionCompatibilityClassification,
        activationState: SnapshotActivationEligibility.State
    ) -> StoredSnapshotVersion {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-10T00:00:00Z",
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 100,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: compatibility != .incompatible,
                isCompatibilityCheckPassed: compatibility == .compatible,
                compatibilityReasons: compatibility == .compatible ? [] : ["compatibility_\(compatibility.rawValue)"],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(
                state: activationState,
                reasons: activationState == .eligible ? [] : ["activation_\(activationState.rawValue)"]
            )
        )

        return StoredSnapshotVersion.from(
            contract: contract,
            compatibilityClassification: compatibility,
            isIngestionCandidate: true,
            indexedAt: "2026-03-10T00:01:00Z"
        )
    }
}

private actor StubRollbackPolicy: SnapshotActivationPolicying {
    private let stubCurrentState: SnapshotActivationState
    private let stubRollbackDecision: SnapshotRollbackDecision
    private(set) var rollbackCallCount = 0

    init(
        currentState: SnapshotActivationState,
        rollbackDecision: SnapshotRollbackDecision
    ) {
        self.stubCurrentState = currentState
        self.stubRollbackDecision = rollbackDecision
    }

    func currentState(for source: FlowDatasetSource) async -> SnapshotActivationState {
        stubCurrentState
    }

    func evaluateActivation(source: FlowDatasetSource, requestedSnapshotID: String?) async -> SnapshotActivationDecision {
        SnapshotActivationDecision(
            source: source,
            requestedSnapshotID: requestedSnapshotID,
            status: .noCandidate,
            candidate: nil,
            reasons: ["unsupported_in_stub"]
        )
    }

    func activate(source: FlowDatasetSource, requestedSnapshotID: String?) async throws -> SnapshotActivationState {
        stubCurrentState
    }

    func evaluateRollback(source: FlowDatasetSource) async -> SnapshotRollbackDecision {
        stubRollbackDecision
    }

    func rollback(source: FlowDatasetSource) async throws -> SnapshotActivationState {
        rollbackCallCount += 1
        throw SnapshotActivationError.noRollbackTarget(source)
    }
}

private actor ThrowingActivatePolicy: SnapshotActivationPolicying {
    private let stubCurrentState: SnapshotActivationState
    private let candidateSnapshot: StoredSnapshotVersion

    init(
        currentState: SnapshotActivationState,
        candidateSnapshot: StoredSnapshotVersion
    ) {
        self.stubCurrentState = currentState
        self.candidateSnapshot = candidateSnapshot
    }

    func currentState(for source: FlowDatasetSource) async -> SnapshotActivationState {
        stubCurrentState
    }

    func evaluateActivation(source: FlowDatasetSource, requestedSnapshotID: String?) async -> SnapshotActivationDecision {
        SnapshotActivationDecision(
            source: source,
            requestedSnapshotID: requestedSnapshotID,
            status: .activatable,
            candidate: candidateSnapshot,
            reasons: []
        )
    }

    func activate(source: FlowDatasetSource, requestedSnapshotID: String?) async throws -> SnapshotActivationState {
        struct SyntheticMutationError: Error {}
        throw SyntheticMutationError()
    }

    func evaluateRollback(source: FlowDatasetSource) async -> SnapshotRollbackDecision {
        SnapshotRollbackDecision(
            source: source,
            status: .noSafeRollback,
            target: nil,
            reasons: ["no_rollback_target"]
        )
    }

    func rollback(source: FlowDatasetSource) async throws -> SnapshotActivationState {
        stubCurrentState
    }
}
