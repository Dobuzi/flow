import Testing
@testable import Flow

struct SnapshotActivationGuardPrimitivesTests {
    @Test
    func staticSourcePromoteIsBlocked() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .bundledSample,
                snapshotID: "sample-2026.03",
                context: .init(trigger: .operatorManual)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: false
        ).baselineDecision()

        #expect(decision.status == .blocked)
        #expect(decision.reasons == [.staticSource])
    }

    @Test
    func promoteWithActivatableDecisionRequiresConfirmationWhenActiveSnapshotWillChange() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                context: .init(trigger: .operatorConfirmed)
            )
        )

        let candidate = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            compatibility: .compatible,
            activationState: .eligible
        )
        let activationDecision = SnapshotActivationDecision(
            source: .seoulCapitalSnapshot,
            requestedSnapshotID: "seoul-2026.03",
            status: .activatable,
            candidate: candidate,
            reasons: []
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.02",
                lastKnownGoodSnapshotID: "seoul-2026.01",
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            activationDecision: activationDecision
        ).baselineDecision()

        #expect(decision.status == .requiresConfirmation)
        #expect(decision.reasons == [.activeSnapshotWillChange])
        #expect(decision.details.contains("active_snapshot_change"))
        #expect(decision.candidateSnapshotID == "seoul-2026.03")
    }

    @Test
    func initialPromoteWithActivatableDecisionRemainsAllowed() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                context: .init(trigger: .operatorConfirmed)
            )
        )

        let candidate = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            compatibility: .compatible,
            activationState: .eligible
        )
        let activationDecision = SnapshotActivationDecision(
            source: .seoulCapitalSnapshot,
            requestedSnapshotID: "seoul-2026.03",
            status: .activatable,
            candidate: candidate,
            reasons: []
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: nil,
                lastKnownGoodSnapshotID: nil,
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            activationDecision: activationDecision
        ).baselineDecision()

        #expect(decision.status == .allowed)
        #expect(decision.reasons.isEmpty)
    }

    @Test
    func promoteToAlreadyActiveSnapshotIsNoOp() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03",
                context: .init(trigger: .operatorManual)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: "seoul-2026.02",
                updatedAt: "2026-03-10T00:00:00Z"
            )
        ).baselineDecision()

        #expect(decision.status == .noOp)
        #expect(decision.reasons == [.alreadyActive])
    }

    @Test
    func incompatiblePromoteDecisionIsBlockedWithStructuredReason() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(trigger: .operatorManual)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            activationDecision: SnapshotActivationDecision(
                source: .seoulCapitalSnapshot,
                requestedSnapshotID: "seoul-2026.04",
                status: .storedButNotActivatable,
                candidate: nil,
                reasons: ["compatibility_incompatible"]
            )
        ).baselineDecision()

        #expect(decision.status == .blocked)
        #expect(decision.reasons == [.targetSnapshotIncompatible])
    }

    @Test
    func demoteWithoutActiveSnapshotIsNoOp() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: nil,
                preserveLastKnownGood: true,
                context: .init(trigger: .operatorManual)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: nil,
                lastKnownGoodSnapshotID: "seoul-2026.02",
                updatedAt: "2026-03-10T00:00:00Z"
            )
        ).baselineDecision()

        #expect(decision.status == .noOp)
        #expect(decision.reasons == [.alreadyInactive])
    }

    @Test
    func demoteWithoutSafeFallbackIsBlocked() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(trigger: .operatorConfirmed)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: nil,
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_missing"]
            )
        ).baselineDecision()

        #expect(decision.status == .blocked)
        #expect(decision.reasons == [.noRollbackTarget])
    }

    @Test
    func demoteWithSafeFallbackRequiresConfirmation() {
        let target = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            compatibility: .compatible,
            activationState: .eligible
        )

        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                preserveLastKnownGood: true,
                context: .init(trigger: .operatorManual)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: "seoul-2026.02",
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .rollbackAvailable,
                target: target,
                reasons: []
            )
        ).baselineDecision()

        #expect(decision.status == .requiresConfirmation)
        #expect(decision.reasons == [.fallbackTransition])
        #expect(decision.rollbackTargetSnapshotID == "seoul-2026.02")
    }

    @Test
    func rollbackWithoutTargetIsBlocked() {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(trigger: .recoveryRollback)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_missing"]
            )
        ).baselineDecision()

        #expect(decision.status == .blocked)
        #expect(decision.reasons == [.noRollbackTarget])
    }

    @Test
    func rollbackAvailableRequiresConfirmationByDefault() {
        let target = makeStoredSnapshot(
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            compatibility: .compatible,
            activationState: .eligible
        )
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "seoul-2026.03",
                context: .init(trigger: .recoveryRollback)
            )
        )
        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            currentState: SnapshotActivationState(
                source: .seoulCapitalSnapshot,
                activeSnapshotID: "seoul-2026.03",
                lastKnownGoodSnapshotID: "seoul-2026.02",
                updatedAt: "2026-03-10T00:00:00Z"
            ),
            rollbackDecision: SnapshotRollbackDecision(
                source: .seoulCapitalSnapshot,
                status: .rollbackAvailable,
                target: target,
                reasons: []
            )
        ).baselineDecision()

        #expect(decision.status == .requiresConfirmation)
        #expect(decision.reasons == [.fallbackTransition])
        #expect(decision.rollbackTargetSnapshotID == "seoul-2026.02")
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
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(
                state: activationState,
                reasons: activationState == .eligible ? [] : ["activation_ineligible"]
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
