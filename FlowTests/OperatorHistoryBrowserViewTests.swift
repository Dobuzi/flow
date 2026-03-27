import Foundation
import Testing
@testable import Flow

struct OperatorHistoryBrowserViewTests {
    @Test
    @MainActor
    func loadsActivationAndProposalEntriesNewestFirstAcrossSources() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalAuditStore = InMemoryRolloutProposalAuditStore()

        await historyStore.append(makeActivationEvent(
            id: "activation-older",
            commandID: "cmd-activation-older",
            source: .koreaNational,
            action: .rollback,
            type: .rollbackBlocked,
            status: .blocked,
            timestamp: "2026-03-15T08:00:00Z"
        ))
        await proposalAuditStore.append(makeProposalEvent(
            id: "proposal-newest",
            proposalID: "proposal-seoul",
            source: .seoulCapitalSnapshot,
            type: .proposalApproved,
            timestamp: "2026-03-15T09:00:00Z",
            reason: "Approved for immediate execution"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(
            historyStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            pageSize: 10
        )
        await viewModel.load()

        #expect(viewModel.entries.map(\.id) == ["proposal-newest", "activation-older"])
        #expect(viewModel.entries.map(\.category) == [.proposal, .activation])
        #expect(viewModel.entries.map(\.linkageID) == ["proposal-seoul", "cmd-activation-older"])
    }

    @Test
    @MainActor
    func sourceCategoryAndStatusFiltersPreserveSourceScoping() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalAuditStore = InMemoryRolloutProposalAuditStore()

        await historyStore.append(makeActivationEvent(
            id: "seoul-promote-success",
            commandID: "cmd-seoul-success",
            source: .seoulCapitalSnapshot,
            action: .promote,
            type: .promoteSucceeded,
            status: .succeeded,
            timestamp: "2026-03-15T09:00:00Z"
        ))
        await proposalAuditStore.append(makeProposalEvent(
            id: "seoul-proposal-rejected",
            proposalID: "proposal-seoul",
            source: .seoulCapitalSnapshot,
            type: .proposalRejected,
            timestamp: "2026-03-15T08:00:00Z",
            reason: "Candidate failed review"
        ))
        await proposalAuditStore.append(makeProposalEvent(
            id: "national-proposal-approved",
            proposalID: "proposal-national",
            source: .koreaNational,
            type: .proposalApproved,
            timestamp: "2026-03-15T07:00:00Z"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(
            historyStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            pageSize: 10
        )
        await viewModel.load()
        await viewModel.updateSourceFilter(OperatorHistorySourceFilter(source: .seoulCapitalSnapshot))
        await viewModel.updateCategoryFilter(.proposal)
        await viewModel.updateStatusFilter(.blocked)

        #expect(viewModel.entries.map(\.id) == ["seoul-proposal-rejected"])
        #expect(viewModel.entries.allSatisfy { $0.source == .seoulCapitalSnapshot })
        #expect(viewModel.entries.allSatisfy { $0.category == .proposal })
    }

    @Test
    @MainActor
    func loadMoreUsesDeterministicPageGrowthForMixedHistory() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalAuditStore = InMemoryRolloutProposalAuditStore()

        for index in stride(from: 6, through: 1, by: -1) {
            if index.isMultiple(of: 2) {
                await historyStore.append(makeActivationEvent(
                    id: "activation-\(index)",
                    commandID: "cmd-\(index)",
                    source: .seoulCapitalSnapshot,
                    action: .promote,
                    type: .promoteSucceeded,
                    status: .succeeded,
                    timestamp: String(format: "2026-03-15T0%d:00:00Z", index)
                ))
            } else {
                await proposalAuditStore.append(makeProposalEvent(
                    id: "proposal-\(index)",
                    proposalID: "proposal-\(index)",
                    source: .seoulCapitalSnapshot,
                    type: .proposalCreated,
                    timestamp: String(format: "2026-03-15T0%d:00:00Z", index)
                ))
            }
        }

        let viewModel = OperatorHistoryBrowserViewModel(
            historyStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            pageSize: 2
        )
        await viewModel.load()

        #expect(viewModel.entries.map(\.id) == ["activation-6", "proposal-5"])
        #expect(viewModel.canLoadMore)

        await viewModel.loadMore()

        #expect(viewModel.entries.map(\.id) == ["activation-6", "proposal-5", "activation-4", "proposal-3"])
        #expect(viewModel.canLoadMore)
    }

    @Test
    @MainActor
    func staticSourceFilterRemainsSafeAndEmpty() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalAuditStore = InMemoryRolloutProposalAuditStore()
        await proposalAuditStore.append(makeProposalEvent(
            id: "seoul-only",
            proposalID: "proposal-seoul-only",
            source: .seoulCapitalSnapshot,
            type: .proposalCreated,
            timestamp: "2026-03-15T09:00:00Z"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(
            historyStore: historyStore,
            proposalAuditStore: proposalAuditStore,
            pageSize: 10
        )
        await viewModel.updateSourceFilter(OperatorHistorySourceFilter(source: .bundledSample))

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.canLoadMore == false)
        #expect(viewModel.loadError == nil)
    }

    @Test
    func browserStateFiltersProposalCategoryAndSourceDeterministically() {
        let entries = [
            makeHistoryEntry(id: "proposal-seoul", source: .seoulCapitalSnapshot, category: .proposal, action: .promote, status: .blocked, timestamp: "2026-03-15T03:00:00Z"),
            makeHistoryEntry(id: "activation-national", source: .koreaNational, category: .activation, action: .rollback, status: .blocked, timestamp: "2026-03-15T02:00:00Z")
        ]

        let state = OperatorHistoryBrowserState(
            sourceFilter: OperatorHistorySourceFilter(source: .seoulCapitalSnapshot),
            categoryFilter: .proposal,
            actionFilter: .proposal,
            statusFilter: .blocked,
            visibleLimit: 30
        )

        #expect(state.visibleEntries(from: entries).map(\.id) == ["proposal-seoul"])
        #expect(state.canLoadMore(from: entries) == false)
    }

    @Test
    func historyEntryMappingIncludesProposalLinkageAndReason() {
        let entry = OperatorHistoryPresentation.historyEntry(
            from: makeProposalEvent(
                id: "proposal-mapped",
                proposalID: "proposal-001",
                source: .seoulCapitalSnapshot,
                type: .proposalRejected,
                timestamp: "2026-03-15T09:00:00Z",
                reason: "Candidate failed review"
            )
        )

        #expect(entry.category == .proposal)
        #expect(entry.linkageID == "proposal-001")
        #expect(entry.proposalID == "proposal-001")
        #expect(entry.snapshotID == "seoulCapitalSnapshot-candidate")
        #expect(entry.status == "Blocked")
        #expect(entry.detail == "Candidate failed review")
    }

    private func makeHistoryEntry(
        id: String,
        source: FlowDatasetSource,
        category: OperatorHistoryEntryCategory,
        action: SnapshotActivationCommand.Action,
        status: SnapshotActivationEventStatus,
        timestamp: String
    ) -> OperatorHistoryEntry {
        OperatorHistoryEntry(
            id: id,
            category: category,
            linkageID: category == .proposal ? "proposal-\(id)" : "cmd-\(id)",
            source: source,
            sourceTitle: source.title,
            eventType: category == .proposal ? RolloutProposalAuditEventType.proposalCreated.rawValue : SnapshotActivationEventType.promoteRequested.rawValue,
            commandAction: action,
            resultStatus: status,
            title: id,
            timestamp: timestamp,
            snapshotID: "snapshot-\(id)",
            proposalID: category == .proposal ? "proposal-\(id)" : nil,
            status: status.rawValue,
            detail: nil
        )
    }

    private func makeActivationEvent(
        id: String,
        commandID: String,
        source: FlowDatasetSource,
        action: SnapshotActivationCommand.Action,
        type: SnapshotActivationEventType,
        status: SnapshotActivationEventStatus,
        timestamp: String
    ) -> SnapshotActivationHistoryEvent {
        SnapshotActivationHistoryEvent(
            eventID: id,
            type: type,
            timestamp: timestamp,
            metadata: SnapshotActivationEventMetadata(
                source: source,
                snapshotID: "\(source.rawValue)-candidate",
                datasetVersion: "2026.03",
                commandID: commandID,
                commandAction: action,
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
                message: nil
            )
        )
    }

    private func makeProposalEvent(
        id: String,
        proposalID: String,
        source: FlowDatasetSource,
        type: RolloutProposalAuditEventType,
        timestamp: String,
        reason: String? = nil
    ) -> RolloutProposalAuditEvent {
        RolloutProposalAuditEvent(
            id: id,
            proposalID: proposalID,
            source: source,
            targetSnapshotID: "\(source.rawValue)-candidate",
            targetDatasetVersion: "2026.03",
            action: .promote,
            type: type,
            timestamp: timestamp,
            actor: "operator-1",
            reason: reason
        )
    }
}
