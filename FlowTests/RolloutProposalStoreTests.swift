import Foundation
import Testing
@testable import Flow

struct RolloutProposalStoreTests {
    @Test
    func proposalPersistsAcrossStoreReload() async throws {
        let fileURL = makeFileURL(testName: "roundtrip")
        let proposal = makeProposal(
            id: "proposal-roundtrip-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval,
            createdAt: "2026-03-19T01:00:00Z",
            updatedAt: "2026-03-19T01:00:00Z"
        )

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(proposal)

        let reloaded = PersistentRolloutProposalStore(fileURL: fileURL)
        #expect(reloaded.restorationDisposition == .current)
        #expect(await reloaded.proposal(id: proposal.id) == proposal)
        #expect(await reloaded.proposals(for: .seoulCapitalSnapshot) == [proposal])
        #expect(await reloaded.allProposals() == [proposal])
    }

    @Test
    func sourceScopedProposalQueriesRemainIsolatedAfterReload() async throws {
        let fileURL = makeFileURL(testName: "source-isolation")
        let seoul = makeProposal(
            id: "proposal-seoul-001",
            source: .seoulCapitalSnapshot,
            targetSnapshotID: "seoul-2026.03",
            createdAt: "2026-03-19T02:00:00Z",
            updatedAt: "2026-03-19T02:10:00Z"
        )
        let national = makeProposal(
            id: "proposal-national-001",
            source: .koreaNational,
            targetSnapshotID: "national-2026.04",
            createdAt: "2026-03-19T02:01:00Z",
            updatedAt: "2026-03-19T02:11:00Z"
        )

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(seoul)
        await store.save(national)

        let reloaded = PersistentRolloutProposalStore(fileURL: fileURL)
        #expect(await reloaded.proposals(for: .seoulCapitalSnapshot) == [seoul])
        #expect(await reloaded.proposals(for: .koreaNational) == [national])
        #expect(await reloaded.proposals(for: .bundledSample).isEmpty)
    }

    @Test
    func approvalStateSurvivesReload() async throws {
        let fileURL = makeFileURL(testName: "approval-state")
        let proposed = makeProposal(
            id: "proposal-approval-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .proposed,
            approvalState: .proposed,
            createdAt: "2026-03-19T03:00:00Z",
            updatedAt: "2026-03-19T03:00:00Z"
        )
        let approved = proposed.updating(
            lifecycleState: .approved,
            approvalState: .approved,
            updatedAt: "2026-03-19T03:05:00Z",
            lastDecisionAt: "2026-03-19T03:05:00Z",
            lastDecisionReason: "Approved for rollout"
        )

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(proposed)
        await store.save(approved)

        let reloaded = PersistentRolloutProposalStore(fileURL: fileURL)
        let restored = try #require(await reloaded.proposal(id: approved.id))
        #expect(restored.approvalState == .approved)
        #expect(restored.lifecycleState == .approved)
        #expect(restored.lastDecisionAt == "2026-03-19T03:05:00Z")
        #expect(restored.lastDecisionReason == "Approved for rollout")
    }

    @Test
    func controlSemanticsSurviveReload() async throws {
        let fileURL = makeFileURL(testName: "control-state")
        let proposal = makeProposal(
            id: "proposal-control-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .approved,
            approvalState: .approved,
            createdAt: "2026-03-19T03:30:00Z",
            updatedAt: "2026-03-19T03:30:00Z"
        ).updating(
            controlState: .paused,
            rollbackPreparedAt: "2026-03-19T03:31:00Z",
            updatedAt: "2026-03-19T03:31:00Z",
            lastDecisionAt: "2026-03-19T03:31:00Z",
            lastDecisionReason: "Paused pending review"
        )

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(proposal)

        let reloaded = PersistentRolloutProposalStore(fileURL: fileURL)
        let restored = try #require(await reloaded.proposal(id: proposal.id))
        #expect(restored.controlState == .paused)
        #expect(restored.rollbackPreparedAt == "2026-03-19T03:31:00Z")
        #expect(restored.lastDecisionReason == "Paused pending review")
    }

    @Test
    func malformedPersistedProposalFileFallsBackSafely() async throws {
        let fileURL = makeFileURL(testName: "corrupt")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        #expect(store.restorationDisposition == .resetCorrupted)
        #expect(await store.allProposals().isEmpty)

        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(backupFiles.contains { $0.lastPathComponent.contains(".corrupted.") })
    }

    @Test
    func proposalsUseDeterministicOrdering() async throws {
        let fileURL = makeFileURL(testName: "ordering")
        let oldest = makeProposal(
            id: "proposal-order-001",
            source: .seoulCapitalSnapshot,
            createdAt: "2026-03-19T04:00:00Z",
            updatedAt: "2026-03-19T04:00:00Z"
        )
        let newest = makeProposal(
            id: "proposal-order-002",
            source: .seoulCapitalSnapshot,
            createdAt: "2026-03-19T04:01:00Z",
            updatedAt: "2026-03-19T04:10:00Z"
        )
        let tiedUpdateA = makeProposal(
            id: "proposal-order-003",
            source: .koreaNational,
            createdAt: "2026-03-19T04:05:00Z",
            updatedAt: "2026-03-19T04:05:00Z"
        )
        let tiedUpdateB = makeProposal(
            id: "proposal-order-004",
            source: .bundledSample,
            createdAt: "2026-03-19T04:04:00Z",
            updatedAt: "2026-03-19T04:05:00Z"
        )

        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(oldest)
        await store.save(newest)
        await store.save(tiedUpdateA)
        await store.save(tiedUpdateB)

        let ordered = await store.allProposals()
        #expect(ordered.map(\.id) == [
            "proposal-order-002",
            "proposal-order-003",
            "proposal-order-004",
            "proposal-order-001"
        ])
    }

    @Test
    func activationRolloutCommandCompatibilityIsPreserved() async throws {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.09",
                datasetVersion: "2026.09",
                context: .init(
                    commandID: "cmd-rollout-proposal-001",
                    requestedAt: "2026-03-19T05:00:00Z",
                    trigger: .operatorConfirmed,
                    requestedBy: "operator-1",
                    note: "Stage this candidate"
                )
            )
        )
        let rolloutCommand = command.proposedRollout(
            proposalID: "proposal-compat-001",
            state: .awaitingApproval,
            rolloutMode: .staged,
            executionReadinessSummary: "candidate_ready"
        )

        let proposal = RolloutProposal(
            rolloutCommand: rolloutCommand,
            lifecycleState: .proposed,
            stages: [
                RolloutStage(
                    stageID: "stage-0",
                    title: "Initial Approval Gate",
                    executionMode: .manualGate,
                    guardrails: .default,
                    note: nil
                )
            ],
            updatedAt: "2026-03-19T05:00:00Z"
        )

        #expect(proposal.source == .seoulCapitalSnapshot)
        #expect(proposal.targetSnapshotID == "seoul-2026.09")
        #expect(proposal.targetDatasetVersion == "2026.09")
        #expect(proposal.approvalState == .awaitingApproval)
        #expect(proposal.rolloutMode == .staged)
        #expect(proposal.activationProposal == rolloutCommand.proposal)
    }

    private func makeFileURL(testName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("PersistentRolloutProposalStore", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func makeProposal(
        id: String,
        source: FlowDatasetSource,
        targetSnapshotID: String? = nil,
        lifecycleState: RolloutProposalLifecycleState = .draft,
        approvalState: ActivationApprovalState = .proposed,
        createdAt: String,
        updatedAt: String
    ) -> RolloutProposal {
        RolloutProposal(
            id: id,
            source: source,
            action: .promote,
            targetSnapshotID: targetSnapshotID ?? "\(source.rawValue)-candidate",
            targetDatasetVersion: "2026.09",
            rolloutMode: .staged,
            lifecycleState: lifecycleState,
            approvalState: approvalState,
            stages: [
                RolloutStage(
                    stageID: "stage-0",
                    title: "Canary",
                    executionMode: .canary,
                    guardrails: .default,
                    note: "Initial check"
                )
            ],
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: "operator-1",
            note: "proposal-note",
            executionReadinessSummary: "candidate_ready",
            lastDecisionAt: nil,
            lastDecisionReason: nil
        )
    }
}
