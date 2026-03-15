import SwiftUI
import Combine

struct OperatorHistorySourceFilter: Hashable, Identifiable {
    let source: FlowDatasetSource?

    static let all = OperatorHistorySourceFilter(source: nil)

    static let allCases: [OperatorHistorySourceFilter] = [
        .all,
        OperatorHistorySourceFilter(source: .bundledSample),
        OperatorHistorySourceFilter(source: .seoulCapitalSnapshot),
        OperatorHistorySourceFilter(source: .koreaNational)
    ]

    var id: String {
        source?.rawValue ?? "all"
    }

    var title: String {
        source?.title ?? "All Sources"
    }
}

enum OperatorHistoryActionFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case promote
    case demote
    case rollback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Events"
        case .promote:
            return "Promote"
        case .demote:
            return "Demote"
        case .rollback:
            return "Rollback"
        }
    }

    var commandAction: SnapshotActivationCommand.Action? {
        switch self {
        case .all:
            return nil
        case .promote:
            return .promote
        case .demote:
            return .demote
        case .rollback:
            return .rollback
        }
    }
}

enum OperatorHistoryStatusFilter: String, CaseIterable, Hashable, Identifiable {
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

    var resultStatus: SnapshotActivationEventStatus? {
        switch self {
        case .all:
            return nil
        case .requested:
            return .requested
        case .succeeded:
            return .succeeded
        case .blocked:
            return .blocked
        case .failed:
            return .failed
        case .noOp:
            return .noOp
        }
    }
}

struct OperatorHistoryBrowserState: Hashable {
    let sourceFilter: OperatorHistorySourceFilter
    let actionFilter: OperatorHistoryActionFilter
    let statusFilter: OperatorHistoryStatusFilter
    let visibleLimit: Int

    init(
        sourceFilter: OperatorHistorySourceFilter = .all,
        actionFilter: OperatorHistoryActionFilter = .all,
        statusFilter: OperatorHistoryStatusFilter = .all,
        visibleLimit: Int = 25
    ) {
        self.sourceFilter = sourceFilter
        self.actionFilter = actionFilter
        self.statusFilter = statusFilter
        self.visibleLimit = max(1, visibleLimit)
    }

    func query(limitOverride: Int? = nil) -> SnapshotActivationHistoryQuery {
        SnapshotActivationHistoryQuery(
            source: sourceFilter.source,
            commandAction: actionFilter.commandAction,
            resultStatus: statusFilter.resultStatus,
            limit: limitOverride ?? visibleLimit,
            sortOrder: .newestFirst
        )
    }

    func expanding(by pageSize: Int) -> OperatorHistoryBrowserState {
        OperatorHistoryBrowserState(
            sourceFilter: sourceFilter,
            actionFilter: actionFilter,
            statusFilter: statusFilter,
            visibleLimit: visibleLimit + max(1, pageSize)
        )
    }

    func withSourceFilter(_ sourceFilter: OperatorHistorySourceFilter) -> OperatorHistoryBrowserState {
        OperatorHistoryBrowserState(
            sourceFilter: sourceFilter,
            actionFilter: actionFilter,
            statusFilter: statusFilter,
            visibleLimit: visibleLimit
        )
    }

    func withActionFilter(_ actionFilter: OperatorHistoryActionFilter) -> OperatorHistoryBrowserState {
        OperatorHistoryBrowserState(
            sourceFilter: sourceFilter,
            actionFilter: actionFilter,
            statusFilter: statusFilter,
            visibleLimit: visibleLimit
        )
    }

    func withStatusFilter(_ statusFilter: OperatorHistoryStatusFilter) -> OperatorHistoryBrowserState {
        OperatorHistoryBrowserState(
            sourceFilter: sourceFilter,
            actionFilter: actionFilter,
            statusFilter: statusFilter,
            visibleLimit: visibleLimit
        )
    }
}

@MainActor
final class OperatorHistoryBrowserViewModel: ObservableObject {
    @Published private(set) var entries: [OperatorHistoryEntry] = []
    @Published private(set) var loadError: FlowNonFatalError?
    @Published private(set) var canLoadMore = false
    @Published private(set) var browserState: OperatorHistoryBrowserState

    let pageSize: Int

    private let historyStore: SnapshotActivationHistoryStoring

    init(
        historyStore: SnapshotActivationHistoryStoring = MobilityRepositoryFactory.sharedActivationHistoryStore,
        initialState: OperatorHistoryBrowserState = OperatorHistoryBrowserState(),
        pageSize: Int = 25
    ) {
        self.historyStore = historyStore
        self.browserState = initialState
        self.pageSize = max(1, pageSize)
    }

    func load() async {
        await fetch(using: browserState)
    }

    func updateSourceFilter(_ sourceFilter: OperatorHistorySourceFilter) async {
        browserState = resetVisibleLimit(for: browserState.withSourceFilter(sourceFilter))
        await fetch(using: browserState)
    }

    func updateActionFilter(_ actionFilter: OperatorHistoryActionFilter) async {
        browserState = resetVisibleLimit(for: browserState.withActionFilter(actionFilter))
        await fetch(using: browserState)
    }

    func updateStatusFilter(_ statusFilter: OperatorHistoryStatusFilter) async {
        browserState = resetVisibleLimit(for: browserState.withStatusFilter(statusFilter))
        await fetch(using: browserState)
    }

    func loadMore() async {
        guard canLoadMore else { return }
        browserState = browserState.expanding(by: pageSize)
        await fetch(using: browserState)
    }

    private func fetch(using state: OperatorHistoryBrowserState) async {
        let results = await historyStore.query(state.query(limitOverride: state.visibleLimit + 1))
        canLoadMore = results.count > state.visibleLimit
        entries = Array(results.prefix(state.visibleLimit)).map(OperatorHistoryPresentation.historyEntry(from:))
        loadError = nil
    }

    private func resetVisibleLimit(for state: OperatorHistoryBrowserState) -> OperatorHistoryBrowserState {
        OperatorHistoryBrowserState(
            sourceFilter: state.sourceFilter,
            actionFilter: state.actionFilter,
            statusFilter: state.statusFilter,
            visibleLimit: pageSize
        )
    }
}

struct OperatorHistoryBrowserView: View {
    @StateObject private var viewModel: OperatorHistoryBrowserViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: OperatorHistoryBrowserViewModel())
    }

    init(viewModel: OperatorHistoryBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section("Filters") {
                Picker("Source", selection: Binding(
                    get: { viewModel.browserState.sourceFilter },
                    set: { filter in Task { await viewModel.updateSourceFilter(filter) } }
                )) {
                    ForEach(OperatorHistorySourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Event", selection: Binding(
                    get: { viewModel.browserState.actionFilter },
                    set: { filter in Task { await viewModel.updateActionFilter(filter) } }
                )) {
                    ForEach(OperatorHistoryActionFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Status", selection: Binding(
                    get: { viewModel.browserState.statusFilter },
                    set: { filter in Task { await viewModel.updateStatusFilter(filter) } }
                )) {
                    ForEach(OperatorHistoryStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Audit History") {
                if let error = viewModel.loadError {
                    NonBlockingErrorBanner(error: error)
                } else if viewModel.entries.isEmpty {
                    Text("No activation history matches the current filters.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Showing \(viewModel.entries.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.entries) { entry in
                        OperatorHistoryRow(entry: entry)
                    }

                    if viewModel.canLoadMore {
                        Button("Load More") {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activation Audit")
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
    }
}

struct OperatorHistoryRow: View {
    let entry: OperatorHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshotID = entry.snapshotID {
                LabeledContent("Snapshot", value: snapshotID)
                    .font(.caption)
            }

            LabeledContent("Command", value: entry.commandID)
                .font(.caption)
            LabeledContent("Timestamp", value: entry.timestamp)
                .font(.caption)

            if let detail = entry.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
