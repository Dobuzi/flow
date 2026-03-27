import Foundation
import Testing
@testable import Flow

struct ActivationTimelineViewTests {
    @Test
    func actionFilterKeepsNewestFirstOrdering() {
        let entries = [
            makeActivationEntry(id: "rollback-blocked", action: .rollback, status: .blocked, timestamp: "2026-03-10T05:00:00Z"),
            makeActivationEntry(id: "demote-failed", action: .demote, status: .failed, timestamp: "2026-03-10T04:00:00Z"),
            makeActivationEntry(id: "promote-succeeded", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z"),
            makeActivationEntry(id: "promote-requested", action: .promote, status: .requested, timestamp: "2026-03-10T02:00:00Z")
        ]

        let browser = ActivationTimelineBrowserState(
            actionFilter: .promote,
            statusFilter: .all,
            visibleLimit: 10
        )

        let visible = browser.visibleEntries(from: entries)

        #expect(visible.map(\.id) == ["promote-succeeded", "promote-requested"])
    }

    @Test
    func statusFilterKeepsBlockedFailedAndNoOpVisibleWithoutChangingOrder() {
        let entries = [
            makeActivationEntry(id: "demote-noop", action: .demote, status: .noOp, timestamp: "2026-03-10T06:00:00Z"),
            makeActivationEntry(id: "rollback-failed", action: .rollback, status: .failed, timestamp: "2026-03-10T05:00:00Z"),
            makeActivationEntry(id: "promote-blocked", action: .promote, status: .blocked, timestamp: "2026-03-10T04:00:00Z"),
            makeActivationEntry(id: "promote-succeeded", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z")
        ]

        let blockedBrowser = ActivationTimelineBrowserState(
            actionFilter: .all,
            statusFilter: .blocked,
            visibleLimit: 10
        )
        let failedBrowser = ActivationTimelineBrowserState(
            actionFilter: .all,
            statusFilter: .failed,
            visibleLimit: 10
        )
        let noOpBrowser = ActivationTimelineBrowserState(
            actionFilter: .all,
            statusFilter: .noOp,
            visibleLimit: 10
        )

        #expect(blockedBrowser.visibleEntries(from: entries).map(\.id) == ["promote-blocked"])
        #expect(failedBrowser.visibleEntries(from: entries).map(\.id) == ["rollback-failed"])
        #expect(noOpBrowser.visibleEntries(from: entries).map(\.id) == ["demote-noop"])
    }

    @Test
    func loadMoreIsDeterministicWithinFilteredResults() {
        let entries = [
            makeActivationEntry(id: "evt-6", action: .promote, status: .succeeded, timestamp: "2026-03-10T06:00:00Z"),
            makeActivationEntry(id: "evt-5", action: .promote, status: .succeeded, timestamp: "2026-03-10T05:00:00Z"),
            makeActivationEntry(id: "evt-4", action: .promote, status: .succeeded, timestamp: "2026-03-10T04:00:00Z"),
            makeActivationEntry(id: "evt-3", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z"),
            makeActivationEntry(id: "evt-2", action: .promote, status: .succeeded, timestamp: "2026-03-10T02:00:00Z"),
            makeActivationEntry(id: "evt-1", action: .promote, status: .succeeded, timestamp: "2026-03-10T01:00:00Z")
        ]

        let firstPage = ActivationTimelineBrowserState(
            actionFilter: .promote,
            statusFilter: .succeeded,
            visibleLimit: 2
        )
        let secondPage = ActivationTimelineBrowserState(
            actionFilter: .promote,
            statusFilter: .succeeded,
            visibleLimit: 4
        )

        #expect(firstPage.visibleEntries(from: entries).map(\.id) == ["evt-6", "evt-5"])
        #expect(firstPage.canLoadMore(from: entries))
        #expect(secondPage.visibleEntries(from: entries).map(\.id) == ["evt-6", "evt-5", "evt-4", "evt-3"])
        #expect(secondPage.canLoadMore(from: entries))
    }

    @Test
    func sourceScopedEntriesRemainIntactDuringFiltering() {
        let entries = [
            makeActivationEntry(
                id: "seoul-promote",
                sourceTitle: FlowDatasetSource.seoulCapitalSnapshot.title,
                action: .promote,
                status: .succeeded,
                timestamp: "2026-03-10T03:00:00Z"
            )
        ]

        let browser = ActivationTimelineBrowserState(
            actionFilter: .promote,
            statusFilter: .succeeded,
            visibleLimit: 10
        )

        let visible = browser.visibleEntries(from: entries)

        #expect(visible.count == 1)
        #expect(visible[0].sourceTitle == FlowDatasetSource.seoulCapitalSnapshot.title)
    }

    @Test
    func proposalFilterShowsProposalEntriesWithoutMasqueradingAsActivation() {
        let entries = [
            makeProposalEntry(id: "proposal-approved", status: .succeeded, timestamp: "2026-03-10T05:00:00Z"),
            makeActivationEntry(id: "promote-succeeded", action: .promote, status: .succeeded, timestamp: "2026-03-10T04:00:00Z")
        ]

        let browser = ActivationTimelineBrowserState(
            actionFilter: .proposal,
            statusFilter: .all,
            visibleLimit: 10
        )

        let visible = browser.visibleEntries(from: entries)

        #expect(visible.map(\.id) == ["proposal-approved"])
        #expect(visible.first?.category == .proposal)
        #expect(visible.first?.proposalID == "proposal-proposal-approved")
    }

    @Test
    func proposalEntriesPreserveNewestFirstOrderingAcrossMixedHistory() {
        let entries = [
            makeActivationEntry(id: "activation-older", action: .rollback, status: .blocked, timestamp: "2026-03-10T03:00:00Z"),
            makeProposalEntry(id: "proposal-newest", status: .requested, timestamp: "2026-03-10T04:00:00Z")
        ]

        let browser = ActivationTimelineBrowserState(
            actionFilter: .all,
            statusFilter: .all,
            visibleLimit: 10
        )

        #expect(browser.visibleEntries(from: entries).map(\.id) == ["proposal-newest", "activation-older"])
    }

    private func makeActivationEntry(
        id: String,
        sourceTitle: String = FlowDatasetSource.seoulCapitalSnapshot.title,
        action: SnapshotActivationCommand.Action,
        status: SnapshotActivationEventStatus,
        timestamp: String
    ) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: id,
            category: .activation,
            source: .seoulCapitalSnapshot,
            sourceTitle: sourceTitle,
            eventType: eventType(for: action, status: status).rawValue,
            commandAction: action,
            resultStatus: status,
            title: id,
            timestamp: timestamp,
            snapshotID: "snapshot-\(id)",
            proposalID: nil,
            linkageID: "cmd-\(id)",
            status: status.rawValue,
            detail: nil
        )
    }

    private func makeProposalEntry(
        id: String,
        source: FlowDatasetSource = .seoulCapitalSnapshot,
        status: SnapshotActivationEventStatus,
        timestamp: String
    ) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: id,
            category: .proposal,
            source: source,
            sourceTitle: source.title,
            eventType: RolloutProposalAuditEventType.proposalApproved.rawValue,
            commandAction: .promote,
            resultStatus: status,
            title: id,
            timestamp: timestamp,
            snapshotID: "snapshot-\(id)",
            proposalID: "proposal-\(id)",
            linkageID: "proposal-\(id)",
            status: status.rawValue,
            detail: nil
        )
    }

    private func eventType(
        for action: SnapshotActivationCommand.Action,
        status: SnapshotActivationEventStatus
    ) -> SnapshotActivationEventType {
        switch (action, status) {
        case (.promote, .requested):
            return .promoteRequested
        case (.promote, .succeeded), (.promote, .noOp):
            return .promoteSucceeded
        case (.promote, .blocked):
            return .promoteBlocked
        case (.promote, .failed):
            return .promoteFailed
        case (.demote, .requested):
            return .demoteRequested
        case (.demote, .succeeded), (.demote, .noOp):
            return .demoteSucceeded
        case (.demote, .blocked):
            return .demoteBlocked
        case (.demote, .failed):
            return .demoteFailed
        case (.rollback, .requested):
            return .rollbackRequested
        case (.rollback, .succeeded), (.rollback, .noOp):
            return .rollbackSucceeded
        case (.rollback, .blocked):
            return .rollbackBlocked
        case (.rollback, .failed):
            return .rollbackFailed
        }
    }
}
