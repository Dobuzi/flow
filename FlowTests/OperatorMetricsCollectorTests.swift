import Testing
@testable import Flow

struct OperatorMetricsCollectorTests {
    @Test
    func derivesActivationMetricsFromHistoryEvents() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let collector = OperatorMetricsCollector(
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )

        await historyStore.append(
            makeHistoryEvent(
                id: "rollback-requested",
                source: .seoulCapitalSnapshot,
                action: .rollback,
                type: .rollbackRequested,
                status: .requested,
                timestamp: "2026-03-15T09:05:00Z"
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                id: "promote-failed",
                source: .seoulCapitalSnapshot,
                action: .promote,
                type: .promoteFailed,
                status: .failed,
                timestamp: "2026-03-15T09:04:00Z"
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                id: "demote-noop",
                source: .seoulCapitalSnapshot,
                action: .demote,
                type: .demoteBlocked,
                status: .noOp,
                timestamp: "2026-03-15T09:03:00Z"
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                id: "promote-blocked",
                source: .seoulCapitalSnapshot,
                action: .promote,
                type: .promoteBlocked,
                status: .blocked,
                timestamp: "2026-03-15T09:02:00Z"
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                id: "promote-succeeded",
                source: .seoulCapitalSnapshot,
                action: .promote,
                type: .promoteSucceeded,
                status: .succeeded,
                timestamp: "2026-03-15T09:01:00Z"
            )
        )
        await historyStore.append(
            makeHistoryEvent(
                id: "national-requested",
                source: .koreaNational,
                action: .promote,
                type: .promoteRequested,
                status: .requested,
                timestamp: "2026-03-15T08:59:00Z"
            )
        )

        let metrics = try #require(await collector.metrics(for: .seoulCapitalSnapshot, isLiveCapable: true))

        #expect(metrics.activation.requestedCount == 1)
        #expect(metrics.activation.succeededCount == 1)
        #expect(metrics.activation.blockedCount == 1)
        #expect(metrics.activation.failedCount == 1)
        #expect(metrics.activation.noOpCount == 1)
        #expect(metrics.activation.rollbackRequestedCount == 1)
        #expect(metrics.activation.latestEventAt == "2026-03-15T09:05:00Z")
    }

    @Test
    func derivesRefreshMetricsFromLatestPersistedRefreshState() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let collector = OperatorMetricsCollector(
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )

        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .seoulCapitalSnapshot,
                trigger: .manual,
                status: .succeeded,
                startedAt: "2026-03-15T10:00:00Z",
                finishedAt: "2026-03-15T10:02:30Z",
                storedSnapshotID: "seoul-2026.04",
                storedDatasetVersion: "2026.04",
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )

        let metrics = try #require(await collector.metrics(for: .seoulCapitalSnapshot, isLiveCapable: true))

        #expect(metrics.refresh.attemptCount == 1)
        #expect(metrics.refresh.succeededCount == 1)
        #expect(metrics.refresh.failedCount == 0)
        #expect(metrics.refresh.latestRefreshAt == "2026-03-15T10:02:30Z")
        #expect(metrics.refresh.latestRefreshLatencySeconds == 150)
    }

    @Test
    func keepsMetricsSourceScopedAndSkipsStaticSources() async throws {
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let collector = OperatorMetricsCollector(
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )

        await historyStore.append(
            makeHistoryEvent(
                id: "national-succeeded",
                source: .koreaNational,
                action: .promote,
                type: .promoteSucceeded,
                status: .succeeded,
                timestamp: "2026-03-15T11:00:00Z"
            )
        )
        await refreshStateStore.record(
            DatasetRefreshResult(
                source: .koreaNational,
                trigger: .periodic,
                status: .failed,
                startedAt: "2026-03-15T11:05:00Z",
                finishedAt: "2026-03-15T11:06:00Z",
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: nil,
                eligibleForActivation: nil,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )

        let nationalMetrics = try #require(await collector.metrics(for: .koreaNational, isLiveCapable: true))
        let bundledMetrics = await collector.metrics(for: .bundledSample, isLiveCapable: false)

        #expect(nationalMetrics.activation.succeededCount == 1)
        #expect(nationalMetrics.refresh.failedCount == 1)
        #expect(await collector.metrics(for: .seoulCapitalSnapshot, isLiveCapable: true)?.activation.succeededCount == 0)
        #expect(bundledMetrics == nil)
    }

    private func makeHistoryEvent(
        id: String,
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
            metadata: .init(
                source: source,
                snapshotID: "\(source.rawValue)-snapshot",
                datasetVersion: "2026.04",
                commandID: "command-\(id)",
                commandAction: action,
                trigger: .operatorManual,
                requestedBy: "tester",
                note: nil,
                validation: nil,
                guardDecision: nil,
                execution: nil
            ),
            result: .init(
                status: status,
                reasonCode: nil,
                message: nil
            )
        )
    }
}
