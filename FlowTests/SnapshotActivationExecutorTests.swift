import Testing
@testable import Flow

struct SnapshotActivationExecutorTests {
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

        let history = await historyStore.events(commandID: "cmd-rollback-success")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .rollbackRequested }))
        #expect(history.contains(where: { $0.type == .rollbackSucceeded }))
    }

    @Test
    func demoteCommandIsHandledBySkeletonAndRecorded() async throws {
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
                    commandID: "cmd-demote-skeleton",
                    requestedAt: "2026-03-12T00:00:00Z",
                    trigger: .operatorManual
                )
            )
        )

        let result = await executor.execute(command)

        #expect(result.status == .blocked)
        #expect(result.blockReason == .policyRejected)
        #expect(result.details.contains("demote_execution_placeholder"))

        let history = await historyStore.events(commandID: "cmd-demote-skeleton")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .demoteRequested }))
        #expect(history.contains(where: { $0.type == .demoteBlocked }))
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

        let history = await historyStore.events(commandID: "cmd-demote-noop")
        #expect(history.count == 2)
        #expect(history.contains(where: { $0.type == .demoteBlocked }))
    }

    private func seedVersion(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        generatedAt: String
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
            indexedAt: generatedAt
        )
    }
}
