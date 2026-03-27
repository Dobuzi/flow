import SwiftUI

typealias ActivationTimelineCategoryFilter = OperatorHistoryCategoryFilter
typealias ActivationTimelineActionFilter = OperatorHistoryActionFilter
typealias ActivationTimelineStatusFilter = OperatorHistoryStatusFilter

struct ActivationTimelineBrowserState: Hashable {
    let categoryFilter: ActivationTimelineCategoryFilter
    let actionFilter: ActivationTimelineActionFilter
    let statusFilter: ActivationTimelineStatusFilter
    let visibleLimit: Int

    init(
        categoryFilter: ActivationTimelineCategoryFilter = .all,
        actionFilter: ActivationTimelineActionFilter = .all,
        statusFilter: ActivationTimelineStatusFilter = .all,
        visibleLimit: Int = 20
    ) {
        self.categoryFilter = categoryFilter
        self.actionFilter = actionFilter
        self.statusFilter = statusFilter
        self.visibleLimit = max(1, visibleLimit)
    }

    func filteredEntries(from entries: [OperatorTimelineEntry]) -> [OperatorTimelineEntry] {
        entries.filter { entry in
            categoryMatches(entry.category)
                && actionFilter.matches(
                    category: entry.category,
                    commandAction: entry.commandAction,
                    eventType: entry.eventType
                )
                && statusFilter.matches(
                    category: entry.category,
                    resultStatus: entry.resultStatus,
                    eventType: entry.eventType
                )
        }
    }

    func visibleEntries(from entries: [OperatorTimelineEntry]) -> [OperatorTimelineEntry] {
        Array(filteredEntries(from: entries).prefix(visibleLimit))
    }

    func canLoadMore(from entries: [OperatorTimelineEntry]) -> Bool {
        filteredEntries(from: entries).count > visibleEntries(from: entries).count
    }

    private func categoryMatches(_ category: OperatorHistoryEntryCategory) -> Bool {
        switch categoryFilter {
        case .all:
            return true
        case .activation:
            return category == .activation
        case .proposal:
            return category == .proposal
        }
    }
}

struct ActivationTimelineView: View {
    let sourceTitle: String
    let entries: [OperatorTimelineEntry]

    @State private var categoryFilter: ActivationTimelineCategoryFilter = .all
    @State private var actionFilter: ActivationTimelineActionFilter = .all
    @State private var statusFilter: ActivationTimelineStatusFilter = .all
    @State private var visibleLimit = 20

    private let pageSize = 20

    private var browserState: ActivationTimelineBrowserState {
        ActivationTimelineBrowserState(
            categoryFilter: categoryFilter,
            actionFilter: actionFilter,
            statusFilter: statusFilter,
            visibleLimit: visibleLimit
        )
    }

    private var filteredEntries: [OperatorTimelineEntry] {
        browserState.filteredEntries(from: entries)
    }

    private var visibleEntries: [OperatorTimelineEntry] {
        browserState.visibleEntries(from: entries)
    }

    private var proposalSummaries: [OperatorProposalAuditSummary] {
        OperatorHistoryPresentation.proposalAuditSummaries(from: filteredEntries)
    }

    var body: some View {
        List {
            Section("Source") {
                Text(sourceTitle)
            }

            Section("Filters") {
                Picker("Category", selection: $categoryFilter) {
                    ForEach(ActivationTimelineCategoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Action", selection: $actionFilter) {
                    ForEach(ActivationTimelineActionFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Status", selection: $statusFilter) {
                    ForEach(ActivationTimelineStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if !proposalSummaries.isEmpty {
                Section("Proposal Lifecycle") {
                    ForEach(proposalSummaries) { summary in
                        OperatorProposalAuditSummaryRow(summary: summary)
                    }
                }
            }

            Section("Timeline") {
                if visibleEntries.isEmpty {
                    Text(filteredEntries.isEmpty && !entries.isEmpty ? "No matching operator events." : "No operator events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Showing \(visibleEntries.count) of \(filteredEntries.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(visibleEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.category.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(entry.category == .proposal ? .orange : .secondary)
                                }
                                Spacer()
                                Text(entry.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let snapshotID = entry.snapshotID {
                                Text(snapshotID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let proposalID = entry.proposalID {
                                Text("Proposal \(proposalID)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(entry.timestamp)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if browserState.canLoadMore(from: entries) {
                        Button("Load More") {
                            visibleLimit += pageSize
                        }
                    }
                }
            }
        }
        .navigationTitle("Operator Timeline")
        .onChange(of: actionFilter) { _, _ in
            visibleLimit = pageSize
        }
        .onChange(of: categoryFilter) { _, _ in
            if !actionFilter.isCompatible(with: categoryFilter) {
                actionFilter = .all
            }
            if !statusFilter.isCompatible(with: categoryFilter) {
                statusFilter = .all
            }
            visibleLimit = pageSize
        }
        .onChange(of: statusFilter) { _, _ in
            visibleLimit = pageSize
        }
    }
}
