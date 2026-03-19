import Foundation
import Testing
@testable import Flow

struct RolloutProposalTransitionServiceTests {
    @Test
    func submitTransitionMovesDraftProposalIntoAwaitingApproval() async throws {
        let proposal = makeProposal(
            id: "proposal-submit-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .draft,
            approvalState: .proposed
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        let transitioned = try await service.submitProposal(
            id: proposal.id,
            by: "operator-1",
            at: "2026-03-19T06:00:00Z"
        )

        #expect(transitioned.lifecycleState == .proposed)
        #expect(transitioned.approvalState == .awaitingApproval)
        #expect(transitioned.updatedAt == "2026-03-19T06:00:00Z")
        #expect(transitioned.lastDecisionAt == "2026-03-19T06:00:00Z")

        let auditEvents = await auditStore.events(proposalID: proposal.id)
        #expect(auditEvents.count == 1)
        #expect(auditEvents[0].type == .proposalCreated)
    }

    @Test
    func approveTransitionPersistsApprovedState() async throws {
        let proposal = makeProposal(
            id: "proposal-approve-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        let approved = try await service.approveProposal(
            id: proposal.id,
            by: "approver-1",
            at: "2026-03-19T06:05:00Z",
            reason: "Ready for operator execution"
        )

        #expect(approved.lifecycleState == .approved)
        #expect(approved.approvalState == .approved)
        #expect(approved.lastDecisionReason == "Ready for operator execution")
        #expect(await store.proposal(id: proposal.id) == approved)
    }

    @Test
    func rejectTransitionCapturesReasonAndAuditEvent() async throws {
        let proposal = makeProposal(
            id: "proposal-reject-001",
            source: .koreaNational,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        let rejected = try await service.rejectProposal(
            id: proposal.id,
            by: "approver-2",
            at: "2026-03-19T06:10:00Z",
            reason: "Candidate failed review"
        )

        #expect(rejected.lifecycleState == .rejected)
        #expect(rejected.approvalState == .rejected)
        #expect(rejected.lastDecisionReason == "Candidate failed review")

        let auditEvents = await auditStore.events(proposalID: proposal.id)
        #expect(auditEvents.map(\.type) == [.proposalRejected])
        #expect(auditEvents[0].reason == "Candidate failed review")
    }

    @Test
    func cancelTransitionIsAllowedForApprovedProposal() async throws {
        let proposal = makeProposal(
            id: "proposal-cancel-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .approved,
            approvalState: .approved
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        let cancelled = try await service.cancelProposal(
            id: proposal.id,
            by: "operator-2",
            at: "2026-03-19T06:15:00Z",
            reason: "Operator withdrew rollout"
        )

        #expect(cancelled.lifecycleState == .cancelled)
        #expect(cancelled.approvalState == .cancelled)
    }

    @Test
    func invalidTransitionsAreRejectedDeterministically() async throws {
        let proposal = makeProposal(
            id: "proposal-invalid-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .cancelled,
            approvalState: .cancelled
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        await #expect(throws: RolloutProposalTransitionError.self) {
            try await service.approveProposal(
                id: proposal.id,
                by: "approver-1",
                at: "2026-03-19T06:20:00Z",
                reason: nil
            )
        }
    }

    @Test
    func transitionedProposalSurvivesPersistentReload() async throws {
        let fileURL = makeFileURL(testName: "transition-reload")
        let proposal = makeProposal(
            id: "proposal-persist-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval
        )
        let store = PersistentRolloutProposalStore(fileURL: fileURL)
        await store.save(proposal)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: InMemoryRolloutProposalAuditStore()
        )
        _ = try await service.approveProposal(
            id: proposal.id,
            by: "approver-1",
            at: "2026-03-19T06:25:00Z",
            reason: "Approved for execution preparation"
        )

        let reloaded = PersistentRolloutProposalStore(fileURL: fileURL)
        let restored = try #require(await reloaded.proposal(id: proposal.id))
        #expect(restored.lifecycleState == .approved)
        #expect(restored.approvalState == .approved)
        #expect(restored.lastDecisionReason == "Approved for execution preparation")
    }

    @Test
    func auditEventsRemainSourceScoped() async throws {
        let seoul = makeProposal(
            id: "proposal-source-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval
        )
        let national = makeProposal(
            id: "proposal-source-002",
            source: .koreaNational,
            lifecycleState: .proposed,
            approvalState: .awaitingApproval
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(seoul)
        await store.save(national)

        let service = DefaultRolloutProposalTransitionService(
            store: store,
            auditStore: auditStore
        )

        _ = try await service.approveProposal(
            id: seoul.id,
            by: "approver-seoul",
            at: "2026-03-19T06:30:00Z",
            reason: nil
        )
        _ = try await service.rejectProposal(
            id: national.id,
            by: "approver-national",
            at: "2026-03-19T06:31:00Z",
            reason: "National candidate blocked"
        )

        let seoulEvents = await auditStore.events(for: .seoulCapitalSnapshot)
        let nationalEvents = await auditStore.events(for: .koreaNational)

        #expect(seoulEvents.count == 1)
        #expect(seoulEvents[0].proposalID == seoul.id)
        #expect(seoulEvents[0].source == .seoulCapitalSnapshot)

        #expect(nationalEvents.count == 1)
        #expect(nationalEvents[0].proposalID == national.id)
        #expect(nationalEvents[0].source == .koreaNational)
    }

    private func makeFileURL(testName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("PersistentRolloutProposalTransitionStore", isDirectory: true)
            .appendingPathComponent(testName, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func makeProposal(
        id: String,
        source: FlowDatasetSource,
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState
    ) -> RolloutProposal {
        RolloutProposal(
            id: id,
            source: source,
            action: .promote,
            targetSnapshotID: "\(source.rawValue)-2026.10",
            targetDatasetVersion: "2026.10",
            rolloutMode: .staged,
            lifecycleState: lifecycleState,
            approvalState: approvalState,
            stages: [
                RolloutStage(
                    stageID: "stage-0",
                    title: "Approval Gate",
                    executionMode: .manualGate,
                    guardrails: .default,
                    note: nil
                )
            ],
            createdAt: "2026-03-19T05:55:00Z",
            updatedAt: "2026-03-19T05:55:00Z",
            createdBy: "operator-1",
            note: "proposal",
            executionReadinessSummary: "candidate_ready",
            lastDecisionAt: nil,
            lastDecisionReason: nil
        )
    }
}
