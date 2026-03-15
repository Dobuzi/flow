import Foundation
import Testing
@testable import Flow

struct OperatorHistoryBrowserViewTests {
    @Test
    @MainActor
    func loadsNewestFirstAuditEntriesAcrossSourcesByDefault() async throws {
        let store = InMemorySnapshotActivationHistoryStore()
        await store.append(makeEvent(
            id: "seoul-newest",
            commandID: "cmd-seoul-newest",
            source: .seoulCapitalSnapshot,
            action: .promote,
            type: .promoteSucceeded,
            status: .succeeded,
            timestamp: "2026-03-15T09:00:00Z"
        ))
        await store.append(makeEvent(
            id: "national-older",
            commandID: "cmd-national-older",
            source: .koreaNational,
            action: .rollback,
            type: .rollbackBlocked,
            status: .blocked,
            timestamp: "2026-03-15T08:00:00Z"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(historyStore: store, pageSize: 10)
        await viewModel.load()

        #expect(viewModel.entries.map(\.id) == ["seoul-newest", "national-older"])
        #expect(viewModel.entries.map(\.commandID) == ["cmd-seoul-newest", "cmd-national-older"])
        #expect(viewModel.entries.map(\.source) == [.seoulCapitalSnapshot, .koreaNational])
    }

    @Test
    @MainActor
    func sourceActionAndStatusFiltersPreserveSourceScoping() async throws {
        let store = InMemorySnapshotActivationHistoryStore()
        await store.append(makeEvent(
            id: "seoul-promote-success",
            commandID: "cmd-seoul-success",
            source: .seoulCapitalSnapshot,
            action: .promote,
            type: .promoteSucceeded,
            status: .succeeded,
            timestamp: "2026-03-15T09:00:00Z"
        ))
        await store.append(makeEvent(
            id: "seoul-demote-failed",
            commandID: "cmd-seoul-failed",
            source: .seoulCapitalSnapshot,
            action: .demote,
            type: .demoteFailed,
            status: .failed,
            timestamp: "2026-03-15T08:00:00Z"
        ))
        await store.append(makeEvent(
            id: "national-promote-success",
            commandID: "cmd-national-success",
            source: .koreaNational,
            action: .promote,
            type: .promoteSucceeded,
            status: .succeeded,
            timestamp: "2026-03-15T07:00:00Z"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(historyStore: store, pageSize: 10)
        await viewModel.load()
        await viewModel.updateSourceFilter(OperatorHistorySourceFilter(source: .seoulCapitalSnapshot))
        await viewModel.updateActionFilter(.promote)
        await viewModel.updateStatusFilter(.succeeded)

        #expect(viewModel.entries.map(\.id) == ["seoul-promote-success"])
        #expect(viewModel.entries.allSatisfy { $0.source == .seoulCapitalSnapshot })
    }

    @Test
    @MainActor
    func loadMoreUsesDeterministicPageGrowth() async throws {
        let store = InMemorySnapshotActivationHistoryStore()
        for index in stride(from: 6, through: 1, by: -1) {
            await store.append(makeEvent(
                id: "evt-\(index)",
                commandID: "cmd-\(index)",
                source: .seoulCapitalSnapshot,
                action: .promote,
                type: .promoteSucceeded,
                status: .succeeded,
                timestamp: String(format: "2026-03-15T0%d:00:00Z", index)
            ))
        }

        let viewModel = OperatorHistoryBrowserViewModel(historyStore: store, pageSize: 2)
        await viewModel.load()

        #expect(viewModel.entries.map(\.id) == ["evt-6", "evt-5"])
        #expect(viewModel.canLoadMore)

        await viewModel.loadMore()

        #expect(viewModel.entries.map(\.id) == ["evt-6", "evt-5", "evt-4", "evt-3"])
        #expect(viewModel.canLoadMore)
    }

    @Test
    @MainActor
    func staticSourceFilterRemainsSafeAndEmpty() async throws {
        let store = InMemorySnapshotActivationHistoryStore()
        await store.append(makeEvent(
            id: "seoul-only",
            commandID: "cmd-seoul-only",
            source: .seoulCapitalSnapshot,
            action: .promote,
            type: .promoteSucceeded,
            status: .succeeded,
            timestamp: "2026-03-15T09:00:00Z"
        ))

        let viewModel = OperatorHistoryBrowserViewModel(historyStore: store, pageSize: 10)
        await viewModel.updateSourceFilter(OperatorHistorySourceFilter(source: .bundledSample))

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.canLoadMore == false)
        #expect(viewModel.loadError == nil)
    }

    @Test
    func browserStateBuildsSourceScopedNewestFirstQueries() {
        let state = OperatorHistoryBrowserState(
            sourceFilter: OperatorHistorySourceFilter(source: .koreaNational),
            actionFilter: .rollback,
            statusFilter: .blocked,
            visibleLimit: 30
        )

        let query = state.query()

        #expect(query.source == .koreaNational)
        #expect(query.commandAction == .rollback)
        #expect(query.resultStatus == .blocked)
        #expect(query.limit == 30)
        #expect(query.sortOrder == .newestFirst)
    }

    @Test
    func historyEntryMappingIncludesCommandLinkageAndResolvedSnapshot() {
        let entry = OperatorHistoryPresentation.historyEntry(
            from: makeEvent(
                id: "mapped",
                commandID: "cmd-mapped",
                source: .seoulCapitalSnapshot,
                action: .rollback,
                type: .rollbackFailed,
                status: .failed,
                timestamp: "2026-03-15T09:00:00Z",
                snapshotID: nil,
                guardSnapshotID: nil,
                rollbackTargetSnapshotID: "rollback-2026.02",
                detail: nil,
                reasonCode: "rollback_target_missing"
            )
        )

        #expect(entry.commandID == "cmd-mapped")
        #expect(entry.snapshotID == "rollback-2026.02")
        #expect(entry.status == "Failed")
        #expect(entry.detail == "Rollback Target Missing")
    }

    private func makeEvent(
        id: String,
        commandID: String,
        source: FlowDatasetSource,
        action: SnapshotActivationCommand.Action,
        type: SnapshotActivationEventType,
        status: SnapshotActivationEventStatus,
        timestamp: String,
        snapshotID: String? = nil,
        guardSnapshotID: String? = nil,
        rollbackTargetSnapshotID: String? = nil,
        detail: String? = nil,
        reasonCode: String? = nil
    ) -> SnapshotActivationHistoryEvent {
        SnapshotActivationHistoryEvent(
            eventID: id,
            type: type,
            timestamp: timestamp,
            metadata: SnapshotActivationEventMetadata(
                source: source,
                snapshotID: snapshotID,
                datasetVersion: "2026.03",
                commandID: commandID,
                commandAction: action,
                trigger: .operatorManual,
                requestedBy: nil,
                note: nil,
                validation: nil,
                guardDecision: SnapshotActivationEventGuardSummary(
                    status: .allowed,
                    reasons: [],
                    details: [],
                    candidateSnapshotID: guardSnapshotID,
                    activeSnapshotID: nil,
                    rollbackTargetSnapshotID: rollbackTargetSnapshotID
                ),
                execution: nil
            ),
            result: SnapshotActivationEventResult(
                status: status,
                reasonCode: reasonCode,
                message: detail
            )
        )
    }
}
