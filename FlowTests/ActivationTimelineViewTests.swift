import Foundation
import Testing
@testable import Flow

struct ActivationTimelineViewTests {
    @Test
    func actionFilterKeepsNewestFirstOrdering() {
        let entries = [
            makeEntry(id: "rollback-blocked", action: .rollback, status: .blocked, timestamp: "2026-03-10T05:00:00Z"),
            makeEntry(id: "demote-failed", action: .demote, status: .failed, timestamp: "2026-03-10T04:00:00Z"),
            makeEntry(id: "promote-succeeded", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z"),
            makeEntry(id: "promote-requested", action: .promote, status: .requested, timestamp: "2026-03-10T02:00:00Z")
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
            makeEntry(id: "demote-noop", action: .demote, status: .noOp, timestamp: "2026-03-10T06:00:00Z"),
            makeEntry(id: "rollback-failed", action: .rollback, status: .failed, timestamp: "2026-03-10T05:00:00Z"),
            makeEntry(id: "promote-blocked", action: .promote, status: .blocked, timestamp: "2026-03-10T04:00:00Z"),
            makeEntry(id: "promote-succeeded", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z")
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
            makeEntry(id: "evt-6", action: .promote, status: .succeeded, timestamp: "2026-03-10T06:00:00Z"),
            makeEntry(id: "evt-5", action: .promote, status: .succeeded, timestamp: "2026-03-10T05:00:00Z"),
            makeEntry(id: "evt-4", action: .promote, status: .succeeded, timestamp: "2026-03-10T04:00:00Z"),
            makeEntry(id: "evt-3", action: .promote, status: .succeeded, timestamp: "2026-03-10T03:00:00Z"),
            makeEntry(id: "evt-2", action: .promote, status: .succeeded, timestamp: "2026-03-10T02:00:00Z"),
            makeEntry(id: "evt-1", action: .promote, status: .succeeded, timestamp: "2026-03-10T01:00:00Z")
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
            makeEntry(
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

    private func makeEntry(
        id: String,
        sourceTitle: String = FlowDatasetSource.seoulCapitalSnapshot.title,
        action: SnapshotActivationCommand.Action,
        status: SnapshotActivationEventStatus,
        timestamp: String
    ) -> OperatorTimelineEntry {
        OperatorTimelineEntry(
            id: id,
            sourceTitle: sourceTitle,
            eventType: eventType(for: action, status: status),
            commandAction: action,
            resultStatus: status,
            title: id,
            timestamp: timestamp,
            snapshotID: "snapshot-\(id)",
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
