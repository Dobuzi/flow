import Foundation

struct OperatorActivationMetrics: Hashable {
    let requestedCount: Int
    let succeededCount: Int
    let blockedCount: Int
    let failedCount: Int
    let noOpCount: Int
    let rollbackRequestedCount: Int
    let latestEventAt: String?
}

struct OperatorRefreshMetrics: Hashable {
    let attemptCount: Int
    let succeededCount: Int
    let failedCount: Int
    let latestRefreshAt: String?
    let latestRefreshLatencySeconds: TimeInterval?
}

struct OperatorSourceMetrics: Hashable {
    let activation: OperatorActivationMetrics
    let refresh: OperatorRefreshMetrics
}

struct OperatorMetricsCollector {
    private let activationHistoryStore: SnapshotActivationHistoryStoring?
    private let refreshStateStore: DatasetRefreshStateStoring?

    init(
        activationHistoryStore: SnapshotActivationHistoryStoring?,
        refreshStateStore: DatasetRefreshStateStoring?
    ) {
        self.activationHistoryStore = activationHistoryStore
        self.refreshStateStore = refreshStateStore
    }

    func metrics(
        for source: FlowDatasetSource,
        isLiveCapable: Bool
    ) async -> OperatorSourceMetrics? {
        guard isLiveCapable else { return nil }

        async let activation = activationMetrics(for: source)
        async let refresh = refreshMetrics(for: source)

        return await OperatorSourceMetrics(
            activation: activation,
            refresh: refresh
        )
    }

    private func activationMetrics(for source: FlowDatasetSource) async -> OperatorActivationMetrics {
        guard let activationHistoryStore else {
            return .init(
                requestedCount: 0,
                succeededCount: 0,
                blockedCount: 0,
                failedCount: 0,
                noOpCount: 0,
                rollbackRequestedCount: 0,
                latestEventAt: nil
            )
        }

        let events = await activationHistoryStore.query(
            SnapshotActivationHistoryQuery(
                source: source,
                sortOrder: .newestFirst
            )
        )

        return OperatorActivationMetrics(
            requestedCount: events.count(where: { $0.result.status == .requested }),
            succeededCount: events.count(where: { $0.result.status == .succeeded }),
            blockedCount: events.count(where: { $0.result.status == .blocked }),
            failedCount: events.count(where: { $0.result.status == .failed }),
            noOpCount: events.count(where: { $0.result.status == .noOp }),
            rollbackRequestedCount: events.count(where: {
                $0.metadata.commandAction == .rollback && $0.result.status == .requested
            }),
            latestEventAt: events.first?.timestamp
        )
    }

    private func refreshMetrics(for source: FlowDatasetSource) async -> OperatorRefreshMetrics {
        guard let refreshStateStore,
              let state = await refreshStateStore.state(for: source) else {
            return .init(
                attemptCount: 0,
                succeededCount: 0,
                failedCount: 0,
                latestRefreshAt: nil,
                latestRefreshLatencySeconds: nil
            )
        }

        let latestRefreshAt = resolvedLatestRefreshTimestamp(from: state)
        return OperatorRefreshMetrics(
            attemptCount: state.lastRefreshAttemptAt == nil ? 0 : 1,
            succeededCount: state.lastRefreshOutcome == .success ? 1 : 0,
            failedCount: state.lastRefreshOutcome == .failed ? 1 : 0,
            latestRefreshAt: latestRefreshAt,
            latestRefreshLatencySeconds: resolvedLatency(from: state, latestRefreshAt: latestRefreshAt)
        )
    }

    private func resolvedLatestRefreshTimestamp(from state: DatasetRefreshState) -> String? {
        switch state.lastRefreshOutcome {
        case .success:
            return state.lastRefreshSucceededAt ?? state.lastRefreshAttemptAt
        case .failed:
            return state.lastRefreshFailedAt ?? state.lastRefreshAttemptAt
        case .skipped:
            return state.lastRefreshAttemptAt
        case nil:
            return state.lastRefreshAttemptAt
        }
    }

    private func resolvedLatency(
        from state: DatasetRefreshState,
        latestRefreshAt: String?
    ) -> TimeInterval? {
        guard let start = parsedDate(from: state.lastRefreshAttemptAt) else {
            return nil
        }

        let terminalTimestamp: String?
        switch state.lastRefreshOutcome {
        case .success:
            terminalTimestamp = state.lastRefreshSucceededAt
        case .failed:
            terminalTimestamp = state.lastRefreshFailedAt
        case .skipped, nil:
            terminalTimestamp = nil
        }

        guard let end = parsedDate(from: terminalTimestamp ?? latestRefreshAt) else {
            return nil
        }
        return max(0, end.timeIntervalSince(start))
    }

    private func parsedDate(from timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}
