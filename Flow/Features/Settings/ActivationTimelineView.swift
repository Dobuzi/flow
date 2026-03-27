import SwiftUI

enum ActivationTimelineActionFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case promote
    case demote
    case rollback
    case proposal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Actions"
        case .promote:
            return "Promote"
        case .demote:
            return "Demote"
        case .rollback:
            return "Rollback"
        case .proposal:
            return "Proposal"
        }
    }

    fileprivate func matches(_ action: SnapshotActivationCommand.Action, category: OperatorHistoryEntryCategory) -> Bool {
        switch self {
        case .all:
            return true
        case .proposal:
            return category == .proposal
        case .promote:
            return action == .promote
        case .demote:
            return action == .demote
        case .rollback:
            return action == .rollback
        }
    }
}

enum ActivationTimelineStatusFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case requested
    case succeeded
    case blocked
    case failed
    case noOp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Statuses"
        case .requested:
            return "Requested"
        case .succeeded:
            return "Succeeded"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
        case .noOp:
            return "No-op"
        }
    }

    fileprivate func matches(_ status: SnapshotActivationEventStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .requested:
            return status == .requested
        case .succeeded:
            return status == .succeeded
        case .blocked:
            return status == .blocked
        case .failed:
            return status == .failed
        case .noOp:
            return status == .noOp
        }
    }
}

struct ActivationTimelineBrowserState: Hashable {
    let actionFilter: ActivationTimelineActionFilter
    let statusFilter: ActivationTimelineStatusFilter
    let visibleLimit: Int

    init(
        actionFilter: ActivationTimelineActionFilter = .all,
        statusFilter: ActivationTimelineStatusFilter = .all,
        visibleLimit: Int = 20
    ) {
        self.actionFilter = actionFilter
        self.statusFilter = statusFilter
        self.visibleLimit = max(1, visibleLimit)
    }

    func filteredEntries(from entries: [OperatorTimelineEntry]) -> [OperatorTimelineEntry] {
        entries.filter { entry in
            actionFilter.matches(entry.commandAction, category: entry.category) && statusFilter.matches(entry.resultStatus)
        }
    }

    func visibleEntries(from entries: [OperatorTimelineEntry]) -> [OperatorTimelineEntry] {
        Array(filteredEntries(from: entries).prefix(visibleLimit))
    }

    func canLoadMore(from entries: [OperatorTimelineEntry]) -> Bool {
        filteredEntries(from: entries).count > visibleEntries(from: entries).count
    }
}

struct ActivationTimelineView: View {
    let sourceTitle: String
    let entries: [OperatorTimelineEntry]

    @State private var actionFilter: ActivationTimelineActionFilter = .all
    @State private var statusFilter: ActivationTimelineStatusFilter = .all
    @State private var visibleLimit = 20

    private let pageSize = 20

    private var browserState: ActivationTimelineBrowserState {
        ActivationTimelineBrowserState(
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

    var body: some View {
        List {
            Section("Source") {
                Text(sourceTitle)
            }

            Section("Filters") {
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
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
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
        .navigationTitle("Activation Timeline")
        .onChange(of: actionFilter) { _, _ in
            visibleLimit = pageSize
        }
        .onChange(of: statusFilter) { _, _ in
            visibleLimit = pageSize
        }
    }
}
