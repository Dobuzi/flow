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

enum OperatorDashboardHealthTone: Hashable {
    case neutral
    case good
    case warning
    case critical
}

struct OperatorDashboardHealthBadgeModel: Hashable {
    let title: String
    let tone: OperatorDashboardHealthTone
}

struct OperatorSourceSummaryCardModel: Identifiable, Hashable {
    let source: FlowDatasetSource
    let title: String
    let capabilityLabel: String
    let healthBadge: OperatorDashboardHealthBadgeModel
    let statusSummary: String
    let reasonSummary: String?
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
                healthBadge: .init(title: "Static", tone: .neutral),
                statusSummary: "Packaged baseline dataset",
                reasonSummary: nil,
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
            OperatorDashboardCardRow(label: "Approval", value: approvalStateTitle(source.approvalSummary)),
            OperatorDashboardCardRow(label: "Approval Detail", value: source.approvalSummary?.decisionSummary ?? "Not applicable"),
            OperatorDashboardCardRow(label: "Rollout Mode", value: rolloutModeTitle(source.approvalSummary?.rolloutMode)),
            OperatorDashboardCardRow(label: "Rollout Readiness", value: rolloutReadinessTitle(source.rolloutReadinessSummary)),
            OperatorDashboardCardRow(label: "Preflight", value: preflightRecommendationTitle(source.rolloutPreflight)),
            OperatorDashboardCardRow(label: "Last Refresh", value: refreshOutcomeTitle(live.lastRefreshOutcome)),
            OperatorDashboardCardRow(label: "Last Refresh At", value: live.lastRefreshAt ?? "Unknown"),
            OperatorDashboardCardRow(label: "Rollback Available", value: live.rollbackAvailable ? "Yes" : "No"),
            OperatorDashboardCardRow(label: "Rollout Reason", value: source.rolloutReadinessSummary?.blockedReason ?? source.rolloutReadinessSummary?.summary ?? "None"),
            OperatorDashboardCardRow(label: "Preflight Notes", value: preflightNotes(source.rolloutPreflight)),
            OperatorDashboardCardRow(label: "Readiness", value: readinessTitle(live.readiness)),
            OperatorDashboardCardRow(label: "Sync State", value: syncStateTitle(live.syncState))
        ]

        return OperatorSourceSummaryCardModel(
            source: source.source,
            title: source.displayName,
            capabilityLabel: "Live-capable",
            healthBadge: healthBadge(from: source.healthSummary),
            statusSummary: operationalStatusTitle(source.healthSummary.operationalStatus),
            reasonSummary: reasonSummary(from: source.healthSummary),
            rows: rows
        )
    }

    private static func healthBadge(from summary: OperatorSourceHealthSummary) -> OperatorDashboardHealthBadgeModel {
        switch summary.state {
        case .static:
            return .init(title: "Static", tone: .neutral)
        case .healthy:
            return .init(title: "Healthy", tone: .good)
        case .degraded:
            return .init(title: "Degraded", tone: .warning)
        case .blocked:
            return .init(title: "Blocked", tone: .critical)
        case .unavailable:
            return .init(title: "Unavailable", tone: .critical)
        case .recoveryNeeded:
            return .init(title: "Recovery Needed", tone: .warning)
        }
    }

    private static func operationalStatusTitle(_ status: OperatorOperationalStatus) -> String {
        switch status {
        case .staticBaseline:
            return "Packaged baseline dataset"
        case .active:
            return "Active"
        case .candidateReady:
            return "Candidate ready"
        case .rollbackReady:
            return "Rollback ready"
        case .inactive:
            return "Inactive"
        case .blocked:
            return "Candidate blocked"
        case .degraded:
            return "Attention needed"
        case .unavailable:
            return "Unavailable"
        case .recoveryNeeded:
            return "Recovered state needs review"
        }
    }

    private static func reasonSummary(from summary: OperatorSourceHealthSummary) -> String? {
        let filteredReasons = summary.reasons.filter {
            switch $0 {
            case .active, .inactive, .staticSource:
                return false
            case .bootstrapDegraded,
                 .syncFailed,
                 .syncDegraded,
                 .refreshFailed,
                 .candidateIncompatible,
                 .candidateIneligible,
                 .readinessBlocked,
                 .pendingValidation,
                 .rollbackReady,
                 .candidateReady:
                return true
            }
        }

        guard !filteredReasons.isEmpty else { return nil }
        return filteredReasons.prefix(2).map(reasonTitle).joined(separator: " • ")
    }

    private static func reasonTitle(_ reason: OperatorSourceHealthReason) -> String {
        switch reason {
        case .staticSource:
            return "Static source"
        case .bootstrapDegraded:
            return "Startup recovery degraded"
        case .syncFailed:
            return "Sync failed"
        case .syncDegraded:
            return "Sync degraded"
        case .refreshFailed:
            return "Refresh failed"
        case .candidateIncompatible:
            return "Candidate incompatible"
        case .candidateIneligible:
            return "Candidate not eligible"
        case .readinessBlocked:
            return "Readiness blocked"
        case .pendingValidation:
            return "Pending validation"
        case .rollbackReady:
            return "Rollback ready"
        case .candidateReady:
            return "Candidate ready"
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
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

    private static func approvalStateTitle(_ summary: OperatorApprovalSummary?) -> String {
        guard let summary else { return "Not applicable" }
        switch summary.approvalState {
        case .proposed:
            return "Proposed"
        case .awaitingApproval:
            return "Awaiting Approval"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .cancelled:
            return "Cancelled"
        case .executed:
            return "Executed"
        case .executionBlocked:
            return "Execution Blocked"
        case .executionFailed:
            return "Execution Failed"
        }
    }

    private static func rolloutModeTitle(_ mode: StagedRolloutMode?) -> String {
        guard let mode else { return "Not applicable" }
        switch mode {
        case .immediate:
            return "Immediate"
        case .staged:
            return "Staged"
        case .rollbackPrepared:
            return "Rollback Prepared"
        case .dryRun:
            return "Dry Run"
        }
    }

    private static func rolloutReadinessTitle(_ summary: OperatorRolloutReadinessSummary?) -> String {
        guard let summary else { return "Not applicable" }
        switch summary.state {
        case .staticBaseline:
            return "Static baseline"
        case .immediateReady:
            return "Immediate Ready"
        case .stagedEligible:
            return "Staged Eligible"
        case .blocked:
            return "Blocked"
        case .notReady:
            return "Not Ready"
        }
    }

    private static func preflightRecommendationTitle(_ result: RolloutPreflightResult?) -> String {
        guard let result else { return "Not applicable" }
        switch result.recommendation {
        case .immediate:
            return "Immediate"
        case .staged:
            return "Staged"
        case .blocked:
            return "Blocked"
        case .notApplicable:
            return "Not applicable"
        }
    }

    private static func preflightNotes(_ result: RolloutPreflightResult?) -> String {
        guard let result else { return "Not applicable" }
        if let firstBlocker = result.blockingReasons.first {
            return firstBlocker
        }
        if let firstWarning = result.warningReasons.first {
            return firstWarning
        }
        return result.checklistItems.first(where: { $0.status == .passed })?.detail ?? "None"
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
                Section("Audit") {
                    NavigationLink {
                        OperatorHistoryBrowserView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Activation Audit")
                            Text("Browse source-scoped activation history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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
                    if let reasonSummary = model.reasonSummary {
                        Text(reasonSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.healthBadge.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(foregroundStyle(for: model.healthBadge.tone))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(backgroundStyle(for: model.healthBadge.tone))
                        .clipShape(Capsule())

                    Text(model.capabilityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }

            ForEach(model.rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }

    private func foregroundStyle(for tone: OperatorDashboardHealthTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .good:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func backgroundStyle(for tone: OperatorDashboardHealthTone) -> some ShapeStyle {
        switch tone {
        case .neutral:
            return Color.gray.opacity(0.12)
        case .good:
            return Color.green.opacity(0.14)
        case .warning:
            return Color.orange.opacity(0.14)
        case .critical:
            return Color.red.opacity(0.14)
        }
    }
}
