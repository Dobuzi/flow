import Foundation
import Testing
@testable import Flow

struct RolloutProposalControlServiceTests {
    @Test
    func pauseResumeAndHaltTransitionsAreDeterministic() async throws {
        let proposal = makeProposal(
            id: "proposal-control-001",
            source: .seoulCapitalSnapshot,
            lifecycleState: .approved,
            approvalState: .approved
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalControlService(
            store: store,
            auditStore: auditStore
        )

        let paused = try await service.apply(
            .pause,
            proposalID: proposal.id,
            by: "operator-1",
            at: "2026-03-19T07:00:00Z",
            reason: "Waiting for health check"
        )
        #expect(paused.controlState == .paused)

        let resumed = try await service.apply(
            .resume,
            proposalID: proposal.id,
            by: "operator-1",
            at: "2026-03-19T07:05:00Z",
            reason: nil
        )
        #expect(resumed.controlState == .active)

        let halted = try await service.apply(
            .halt,
            proposalID: proposal.id,
            by: "operator-1",
            at: "2026-03-19T07:06:00Z",
            reason: "Safety halt"
        )
        #expect(halted.controlState == .halted)

        let events = await auditStore.events(proposalID: proposal.id)
        #expect(events.map(\.type) == [.rolloutPaused, .rolloutResumed, .rolloutHalted])
    }

    @Test
    func rollbackPreparedMarkerIsPersistedAsSafetySignalOnly() async throws {
        let proposal = makeProposal(
            id: "proposal-control-002",
            source: .seoulCapitalSnapshot,
            lifecycleState: .approved,
            approvalState: .approved
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(proposal)

        let service = DefaultRolloutProposalControlService(
            store: store,
            auditStore: auditStore
        )

        let marked = try await service.apply(
            .markRollbackPrepared,
            proposalID: proposal.id,
            by: "operator-1",
            at: "2026-03-19T07:10:00Z",
            reason: "Rollback target confirmed"
        )

        #expect(marked.controlState == .active)
        #expect(marked.rollbackPreparedAt == "2026-03-19T07:10:00Z")
        #expect(marked.lastDecisionReason == "Rollback target confirmed")
    }

    @Test
    func invalidResumeAndPauseTransitionsAreRejected() async throws {
        let rejected = makeProposal(
            id: "proposal-control-rejected",
            source: .seoulCapitalSnapshot,
            lifecycleState: .rejected,
            approvalState: .rejected
        )
        let draft = makeProposal(
            id: "proposal-control-draft",
            source: .koreaNational,
            lifecycleState: .draft,
            approvalState: .proposed
        )

        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(rejected)
        await store.save(draft)

        let service = DefaultRolloutProposalControlService(
            store: store,
            auditStore: auditStore
        )

        await #expect(throws: RolloutProposalControlTransitionError.self) {
            try await service.apply(
                .resume,
                proposalID: rejected.id,
                by: "operator-1",
                at: "2026-03-19T07:15:00Z",
                reason: nil
            )
        }

        await #expect(throws: RolloutProposalControlTransitionError.self) {
            try await service.apply(
                .pause,
                proposalID: draft.id,
                by: "operator-1",
                at: "2026-03-19T07:16:00Z",
                reason: nil
            )
        }
    }

    @Test
    func controlSemanticsRemainSourceScoped() async throws {
        let seoul = makeProposal(
            id: "proposal-control-seoul",
            source: .seoulCapitalSnapshot,
            lifecycleState: .approved,
            approvalState: .approved
        )
        let national = makeProposal(
            id: "proposal-control-national",
            source: .koreaNational,
            lifecycleState: .approved,
            approvalState: .approved
        )
        let store = InMemoryRolloutProposalStore()
        let auditStore = InMemoryRolloutProposalAuditStore()
        await store.save(seoul)
        await store.save(national)

        let service = DefaultRolloutProposalControlService(
            store: store,
            auditStore: auditStore
        )

        _ = try await service.apply(
            .pause,
            proposalID: seoul.id,
            by: "operator-1",
            at: "2026-03-19T07:20:00Z",
            reason: "Seoul pause"
        )

        let seoulStored = try #require(await store.proposal(id: seoul.id))
        let nationalStored = try #require(await store.proposal(id: national.id))
        #expect(seoulStored.controlState == .paused)
        #expect(nationalStored.controlState == .active)
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
            stages: [],
            createdAt: "2026-03-19T06:55:00Z",
            updatedAt: "2026-03-19T06:55:00Z",
            createdBy: "operator-1",
            note: nil,
            executionReadinessSummary: "candidate_ready",
            lastDecisionAt: nil,
            lastDecisionReason: nil
        )
    }
}
