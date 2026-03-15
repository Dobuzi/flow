import SwiftUI

struct OperatorDashboardBootstrapBannerModel: Hashable {
    let title: String
    let detail: String
    let isDegraded: Bool
}

struct OperatorDashboardCardRow: Hashable {
    let label: String
    let value: String
}

struct OperatorSourceSummaryCardModel: Identifiable, Hashable {
    let source: FlowDatasetSource
    let title: String
    let capabilityLabel: String
    let statusSummary: String
    let rows: [OperatorDashboardCardRow]

    var id: FlowDatasetSource {
        source
    }
}

enum OperatorDashboardPresentation {
    static func bootstrapBanner(from status: PersistentOperatorStateBootstrapStatus?) -> OperatorDashboardBootstrapBannerModel? {
        guard let status else { return nil }

        let detail = [
            "Activation \(dispositionTitle(status.activationState))",
            "Refresh \(dispositionTitle(status.refreshState))",
            "History \(dispositionTitle(status.activationHistory))"
        ].joined(separator: " • ")

        return OperatorDashboardBootstrapBannerModel(
            title: status.isDegraded ? "Recovered With Degraded Operator State" : "Operator State Restored",
            detail: detail,
            isDegraded: status.isDegraded
        )
    }

    static func cardModels(from summary: OperatorDashboardSummary) -> [OperatorSourceSummaryCardModel] {
        summary.sources.map(cardModel(from:))
    }

    static func cardModel(from source: OperatorSourceSummary) -> OperatorSourceSummaryCardModel {
        guard let live = source.liveSummary else {
            return OperatorSourceSummaryCardModel(
                source: source.source,
                title: source.displayName,
                capabilityLabel: "Static",
                statusSummary: "Packaged baseline dataset",
                rows: [
                    OperatorDashboardCardRow(label: "Refresh", value: "Not supported"),
                    OperatorDashboardCardRow(label: "Activation", value: "Not applicable")
                ]
            )
        }

        let rows: [OperatorDashboardCardRow] = [
            OperatorDashboardCardRow(label: "Active Snapshot", value: live.activeSnapshotID ?? "None"),
            OperatorDashboardCardRow(label: "Last Known Good", value: live.lastKnownGoodSnapshotID ?? "None"),
            OperatorDashboardCardRow(label: "Latest Candidate", value: live.latestCandidateSnapshotID ?? "None"),
            OperatorDashboardCardRow(label: "Candidate Compatibility", value: compatibilityTitle(live.latestCandidateCompatibility)),
            OperatorDashboardCardRow(label: "Candidate Ready", value: eligibilityTitle(live.latestCandidateEligibleForActivation)),
            OperatorDashboardCardRow(label: "Last Refresh", value: refreshOutcomeTitle(live.lastRefreshOutcome)),
            OperatorDashboardCardRow(label: "Last Refresh At", value: live.lastRefreshAt ?? "Unknown"),
            OperatorDashboardCardRow(label: "Rollback Available", value: live.rollbackAvailable ? "Yes" : "No"),
            OperatorDashboardCardRow(label: "Readiness", value: readinessTitle(live.readiness)),
            OperatorDashboardCardRow(label: "Sync State", value: syncStateTitle(live.syncState))
        ]

        return OperatorSourceSummaryCardModel(
            source: source.source,
            title: source.displayName,
            capabilityLabel: "Live-capable",
            statusSummary: activationStatusTitle(live.operatorActivationStatus),
            rows: rows
        )
    }

    private static func activationStatusTitle(_ status: DatasetOperatorActivationStatus) -> String {
        switch status {
        case .noHistory:
            return "No activation history"
        case .inactive:
            return "Inactive"
        case .inactiveCandidateReady:
            return "Inactive, candidate ready"
        case .active:
            return "Active"
        case .activeRollbackReady:
            return "Active, rollback ready"
        case .attentionRequired:
            return "Attention required"
        }
    }

    private static func compatibilityTitle(_ compatibility: IngestionCompatibilityClassification?) -> String {
        guard let compatibility else { return "Unknown" }
        return compatibility.rawValue.capitalized
    }

    private static func eligibilityTitle(_ eligible: Bool?) -> String {
        guard let eligible else { return "Unknown" }
        return eligible ? "Ready" : "Blocked"
    }

    private static func refreshOutcomeTitle(_ outcome: DatasetRefreshOutcome?) -> String {
        guard let outcome else { return "Unknown" }
        switch outcome {
        case .success:
            return "Success"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Failed"
        }
    }

    private static func readinessTitle(_ readiness: DatasetRefreshReadiness) -> String {
        switch readiness {
        case .staticOnly:
            return "Static only"
        case .ready:
            return "Ready"
        case .pendingValidation:
            return "Pending validation"
        case .blocked:
            return "Blocked"
        }
    }

    private static func syncStateTitle(_ syncState: DatasetSyncState) -> String {
        switch syncState {
        case .idle:
            return "Idle"
        case .ready:
            return "Ready"
        case .degraded:
            return "Degraded"
        case .failed:
            return "Failed"
        }
    }

    private static func dispositionTitle(_ disposition: PersistentStoreRestoreDisposition) -> String {
        switch disposition {
        case .empty:
            return "empty"
        case .current:
            return "current"
        case .migrated:
            return "migrated"
        case .recoveredPartial:
            return "partial recovery"
        case .resetCorrupted:
            return "reset corrupted"
        }
    }
}

struct OperatorDashboardSection: View {
    @ObservedObject var viewModel: OperatorDashboardViewModel

    var body: some View {
        Section("Operator Dashboard") {
            if let summary = viewModel.dashboard {
                NavigationLink {
                    OperatorDashboardView(viewModel: viewModel)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Operator Dashboard")
                        Text("\(summary.liveSources.count) live • \(summary.staticSources.count) static")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let banner = OperatorDashboardPresentation.bootstrapBanner(from: summary.bootstrapStatus) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(banner.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(banner.isDegraded ? .orange : .secondary)
                        Text(banner.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } else if let error = viewModel.loadError {
                NonBlockingErrorBanner(error: error)
            } else {
                ProgressView()
            }
        }
    }
}

struct OperatorDashboardView: View {
    @ObservedObject var viewModel: OperatorDashboardViewModel

    var body: some View {
        List {
            if let summary = viewModel.dashboard {
                if let banner = OperatorDashboardPresentation.bootstrapBanner(from: summary.bootstrapStatus) {
                    Section("Startup Recovery") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(banner.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(banner.isDegraded ? .orange : .primary)
                            Text(banner.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Sources") {
                    ForEach(OperatorDashboardPresentation.cardModels(from: summary)) { card in
                        OperatorSourceSummaryCard(model: card)
                    }
                }
            } else if let error = viewModel.loadError {
                Section {
                    NonBlockingErrorBanner(error: error)
                }
            } else {
                Section {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Operator Dashboard")
        .refreshable {
            await viewModel.load()
        }
        .task {
            if viewModel.dashboard == nil && viewModel.loadError == nil {
                await viewModel.load()
            }
        }
    }
}

struct OperatorSourceSummaryCard: View {
    let model: OperatorSourceSummaryCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.statusSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.capabilityLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }

            ForEach(model.rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}
