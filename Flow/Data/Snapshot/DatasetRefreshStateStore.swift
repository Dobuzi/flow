import Foundation

struct DatasetRefreshState: Hashable {
    let source: FlowDatasetSource
    let lastRefreshAttemptAt: String?
    let lastRefreshSucceededAt: String?
    let lastRefreshFailedAt: String?
    let lastRefreshTrigger: DatasetRefreshTrigger?
    let lastRefreshOutcome: DatasetRefreshOutcome?
    let latestCandidateSnapshotID: String?
    let latestCandidateCompatibility: IngestionCompatibilityClassification?
    let latestCandidateEligibleForActivation: Bool?
    let lastRefreshFailureReason: String?
}

protocol DatasetRefreshStateStoring {
    func record(_ result: DatasetRefreshResult) async
    func state(for source: FlowDatasetSource) async -> DatasetRefreshState?
}

actor InMemoryDatasetRefreshStateStore: DatasetRefreshStateStoring {
    private var states: [FlowDatasetSource: DatasetRefreshState] = [:]

    func record(_ result: DatasetRefreshResult) async {
        let existing = states[result.source]
        let outcome: DatasetRefreshOutcome = switch result.status {
        case .succeeded: .success
        case .skipped: .skipped
        case .failed: .failed
        }

        let failureAt = result.status == .failed ? result.finishedAt : existing?.lastRefreshFailedAt
        let failureReason: String?
        if result.status == .failed {
            failureReason = summarize(result.error)
        } else if result.status == .succeeded {
            failureReason = nil
        } else {
            failureReason = summarize(result.error) ?? existing?.lastRefreshFailureReason
        }

        let candidateSnapshotID = result.storedSnapshotID ?? existing?.latestCandidateSnapshotID
        let candidateCompatibility = result.compatibilityClassification ?? existing?.latestCandidateCompatibility
        let candidateEligible = result.eligibleForActivation ?? existing?.latestCandidateEligibleForActivation

        states[result.source] = DatasetRefreshState(
            source: result.source,
            lastRefreshAttemptAt: result.startedAt,
            lastRefreshSucceededAt: result.status == .succeeded ? result.finishedAt : existing?.lastRefreshSucceededAt,
            lastRefreshFailedAt: failureAt,
            lastRefreshTrigger: result.trigger,
            lastRefreshOutcome: outcome,
            latestCandidateSnapshotID: candidateSnapshotID,
            latestCandidateCompatibility: candidateCompatibility,
            latestCandidateEligibleForActivation: candidateEligible,
            lastRefreshFailureReason: failureReason
        )
    }

    func state(for source: FlowDatasetSource) async -> DatasetRefreshState? {
        states[source]
    }

    private func summarize(_ error: DatasetRefreshError?) -> String? {
        guard let error else { return nil }

        switch error {
        case .catalogUnavailable:
            return "catalog_unavailable"
        case .schedulerFailure:
            return "scheduler_failure"
        case .sourceNotLiveCapable:
            return "source_not_live_capable"
        case .adapterNotConfigured:
            return "adapter_not_configured"
        case .refreshInProgress:
            return "refresh_in_progress"
        case .periodicNotDue:
            return "periodic_not_due"
        case .ingestionFailed(let ingestionError):
            return "ingestion_failed_\(ingestionError.code)"
        }
    }
}

private extension IngestionPipelineError {
    var code: String {
        switch self {
        case .adapterFailure:
            return "adapter_failure"
        case .payloadValidationFailed:
            return "payload_validation_failed"
        case .materializationFailed:
            return "materialization_failed"
        case .materializationRejected:
            return "materialization_rejected"
        case .contractValidationFailed:
            return "contract_validation_failed"
        case .integrityFailed:
            return "integrity_failed"
        case .schemaValidationFailed:
            return "schema_validation_failed"
        case .compatibilityFailed:
            return "compatibility_failed"
        }
    }
}
