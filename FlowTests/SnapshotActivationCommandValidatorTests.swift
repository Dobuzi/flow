import Testing
@testable import Flow

struct SnapshotActivationCommandValidatorTests {
    private let validator = DefaultSnapshotActivationCommandValidator()

    @Test
    func promoteWithValidSnapshotTargetPassesValidation() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(trigger: .operatorManual)
            )
        )

        let result = validator.validate(command, context: .init(isLiveCapable: true))
        #expect(result.isValid)
        #expect(result.issues.isEmpty)
    }

    @Test
    func promoteMissingTargetReferenceIsRejected() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: nil,
                datasetVersion: nil,
                context: .init(trigger: .operatorManual)
            )
        )

        let result = validator.validate(command, context: .init(isLiveCapable: true))

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.code == .missingTargetReference }))
    }

    @Test
    func malformedCommandContextIsRejected() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: SnapshotActivationCommandContext(
                    commandID: "   ",
                    requestedAt: "not-a-date",
                    trigger: .operatorManual
                )
            )
        )

        let result = validator.validate(command, context: .init(isLiveCapable: true))

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.code == .emptyCommandID }))
        #expect(result.issues.contains(where: { $0.code == .malformedRequestedAt }))
    }

    @Test
    func demoteWithEmptyExpectedActiveSnapshotIDIsRejected() {
        let command = SnapshotActivationCommand.demote(
            DemoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "   ",
                preserveLastKnownGood: true,
                context: .init(trigger: .operatorManual)
            )
        )

        let result = validator.validate(command, context: .init(isLiveCapable: true))

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.code == .emptyExpectedActiveSnapshotID }))
    }

    @Test
    func rollbackOnStaticSourceIsRejected() {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .bundledSample,
                expectedActiveSnapshotID: nil,
                context: .init(trigger: .recoveryRollback)
            )
        )

        let result = validator.validate(command, context: .init(isLiveCapable: false))

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.code == .rollbackUnsupportedForStaticSource }))
    }

    @Test
    func sourceMismatchAgainstCandidateAndStateIsRejected() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.04",
                context: .init(trigger: .operatorConfirmed)
            )
        )

        let currentState = SnapshotActivationState(
            source: .koreaNational,
            activeSnapshotID: "national-2026.03",
            lastKnownGoodSnapshotID: nil,
            updatedAt: "2026-03-10T00:00:00Z"
        )

        let mismatchedCandidate = makeStoredSnapshot(
            source: .koreaNational,
            snapshotID: "national-2026.04"
        )

        let result = validator.validate(
            command,
            context: .init(
                isLiveCapable: true,
                currentState: currentState,
                candidateSnapshot: mismatchedCandidate
            )
        )

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.code == .currentStateSourceMismatch }))
        #expect(result.issues.contains(where: { $0.code == .candidateSourceMismatch }))
    }

    @Test
    func guardInputUsesValidatorAndBlocksInvalidRollbackCommand() {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: .seoulCapitalSnapshot,
                expectedActiveSnapshotID: "  ",
                context: .init(trigger: .operatorManual)
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            rollbackTarget: makeStoredSnapshot(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.03"
            )
        ).baselineDecision()

        #expect(decision.status == .blocked)
        #expect(decision.reasons == [.commandInvalid])
        #expect(decision.details.contains(SnapshotActivationCommandValidationIssueCode.emptyExpectedActiveSnapshotID.rawValue))
    }

    private func makeStoredSnapshot(
        source: FlowDatasetSource,
        snapshotID: String
    ) -> StoredSnapshotVersion {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: "2026.03",
            generatedAt: "2026-03-10T00:00:00Z",
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 10,
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
            activationEligibility: SnapshotActivationEligibility(
                state: .eligible,
                reasons: []
            )
        )

        return StoredSnapshotVersion.from(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: "2026-03-10T00:01:00Z"
        )
    }
}
