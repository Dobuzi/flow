import Foundation

enum PersistentStoreRestoreDisposition: String, Hashable {
    case empty
    case current
    case migrated
    case recoveredPartial
    case resetCorrupted

    var isDegraded: Bool {
        switch self {
        case .empty, .current, .migrated:
            return false
        case .recoveredPartial, .resetCorrupted:
            return true
        }
    }
}

struct PersistentOperatorStateBootstrapStatus: Hashable {
    let activationState: PersistentStoreRestoreDisposition
    let refreshState: PersistentStoreRestoreDisposition
    let activationHistory: PersistentStoreRestoreDisposition

    var isDegraded: Bool {
        activationState.isDegraded || refreshState.isDegraded || activationHistory.isDegraded
    }
}

struct PersistentOperatorStateBootstrapResult {
    let activationStateStore: SnapshotActivationStateStoring
    let activationPolicy: SnapshotActivationPolicying
    let refreshStateStore: DatasetRefreshStateStoring
    let activationHistoryStore: SnapshotActivationHistoryStoring
    let activationStateProjector: SnapshotActivationStateProjecting
    let status: PersistentOperatorStateBootstrapStatus
}

struct PersistentOperatorStateBootstrap {
    let versionStore: DatasetVersionStoring
    let activationStateFileURL: URL?
    let refreshStateFileURL: URL?
    let activationHistoryFileURL: URL?

    init(
        versionStore: DatasetVersionStoring,
        activationStateFileURL: URL? = nil,
        refreshStateFileURL: URL? = nil,
        activationHistoryFileURL: URL? = nil
    ) {
        self.versionStore = versionStore
        self.activationStateFileURL = activationStateFileURL
        self.refreshStateFileURL = refreshStateFileURL
        self.activationHistoryFileURL = activationHistoryFileURL
    }

    func bootstrap() -> PersistentOperatorStateBootstrapResult {
        let activationStateStore = PersistentSnapshotActivationStateStore(fileURL: activationStateFileURL)
        let activationPolicy = DefaultSnapshotActivationPolicy(
            versionStore: versionStore,
            stateStore: activationStateStore
        )
        let refreshStateStore = PersistentDatasetRefreshStateStore(fileURL: refreshStateFileURL)
        let activationHistoryStore = PersistentSnapshotActivationHistoryStore(fileURL: activationHistoryFileURL)
        let activationStateProjector = DefaultSnapshotActivationStateProjector(
            activationPolicy: activationPolicy,
            historyStore: activationHistoryStore,
            versionStore: versionStore
        )

        let status = PersistentOperatorStateBootstrapStatus(
            activationState: activationStateStore.restorationDisposition,
            refreshState: refreshStateStore.restorationDisposition,
            activationHistory: activationHistoryStore.restorationDisposition
        )

        FlowLogger.log(
            level: .info,
            message: "Bootstrapped persistent operator state.",
            metadata: [
                "activation_state": status.activationState.rawValue,
                "refresh_state": status.refreshState.rawValue,
                "activation_history": status.activationHistory.rawValue,
                "degraded": String(status.isDegraded)
            ]
        )

        return PersistentOperatorStateBootstrapResult(
            activationStateStore: activationStateStore,
            activationPolicy: activationPolicy,
            refreshStateStore: refreshStateStore,
            activationHistoryStore: activationHistoryStore,
            activationStateProjector: activationStateProjector,
            status: status
        )
    }
}
