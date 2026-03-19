import Foundation

struct RolloutProposal: Codable, Hashable {
    let id: String
    let source: FlowDatasetSource
    let action: SnapshotActivationCommand.Action
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let rolloutMode: StagedRolloutMode
    let lifecycleState: RolloutProposalLifecycleState
    let approvalState: ActivationApprovalState
    let stages: [RolloutStage]
    let createdAt: String
    let updatedAt: String
    let createdBy: String?
    let note: String?
    let executionReadinessSummary: String?
    let lastDecisionAt: String?
    let lastDecisionReason: String?

    init(
        id: String,
        source: FlowDatasetSource,
        action: SnapshotActivationCommand.Action,
        targetSnapshotID: String?,
        targetDatasetVersion: String?,
        rolloutMode: StagedRolloutMode,
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState,
        stages: [RolloutStage],
        createdAt: String,
        updatedAt: String,
        createdBy: String?,
        note: String?,
        executionReadinessSummary: String?,
        lastDecisionAt: String?,
        lastDecisionReason: String?
    ) {
        self.id = id
        self.source = source
        self.action = action
        self.targetSnapshotID = targetSnapshotID
        self.targetDatasetVersion = targetDatasetVersion
        self.rolloutMode = rolloutMode
        self.lifecycleState = lifecycleState
        self.approvalState = approvalState
        self.stages = stages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.note = note
        self.executionReadinessSummary = executionReadinessSummary
        self.lastDecisionAt = lastDecisionAt
        self.lastDecisionReason = lastDecisionReason
    }

    init(
        rolloutCommand: ActivationRolloutCommand,
        lifecycleState: RolloutProposalLifecycleState,
        stages: [RolloutStage],
        updatedAt: String? = nil
    ) {
        self.init(
            id: rolloutCommand.proposal.proposalID,
            source: rolloutCommand.source,
            action: rolloutCommand.action,
            targetSnapshotID: rolloutCommand.proposal.targetSnapshotID,
            targetDatasetVersion: rolloutCommand.proposal.targetDatasetVersion,
            rolloutMode: rolloutCommand.rolloutMode,
            lifecycleState: lifecycleState,
            approvalState: rolloutCommand.approvalState,
            stages: stages,
            createdAt: rolloutCommand.proposal.createdAt,
            updatedAt: updatedAt ?? rolloutCommand.decidedAt ?? rolloutCommand.proposal.createdAt,
            createdBy: rolloutCommand.proposal.createdBy,
            note: rolloutCommand.proposal.note,
            executionReadinessSummary: rolloutCommand.proposal.executionReadinessSummary,
            lastDecisionAt: rolloutCommand.decidedAt,
            lastDecisionReason: rolloutCommand.decisionReason
        )
    }

    var activationProposal: ActivationProposal {
        ActivationProposal(
            proposalID: id,
            source: source,
            action: action,
            targetSnapshotID: targetSnapshotID,
            targetDatasetVersion: targetDatasetVersion,
            createdAt: createdAt,
            createdBy: createdBy,
            note: note,
            approvalState: approvalState,
            rolloutMode: rolloutMode,
            executionReadinessSummary: executionReadinessSummary
        )
    }

    func updating(
        lifecycleState: RolloutProposalLifecycleState? = nil,
        approvalState: ActivationApprovalState? = nil,
        updatedAt: String,
        lastDecisionAt: String? = nil,
        lastDecisionReason: String? = nil
    ) -> RolloutProposal {
        RolloutProposal(
            id: id,
            source: source,
            action: action,
            targetSnapshotID: targetSnapshotID,
            targetDatasetVersion: targetDatasetVersion,
            rolloutMode: rolloutMode,
            lifecycleState: lifecycleState ?? self.lifecycleState,
            approvalState: approvalState ?? self.approvalState,
            stages: stages,
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: createdBy,
            note: note,
            executionReadinessSummary: executionReadinessSummary,
            lastDecisionAt: lastDecisionAt ?? self.lastDecisionAt,
            lastDecisionReason: lastDecisionReason ?? self.lastDecisionReason
        )
    }
}

protocol RolloutProposalStoring {
    func save(_ proposal: RolloutProposal) async
    func proposal(id: String) async -> RolloutProposal?
    func proposals(for source: FlowDatasetSource) async -> [RolloutProposal]
    func allProposals() async -> [RolloutProposal]
    func delete(id: String) async
}

actor InMemoryRolloutProposalStore: RolloutProposalStoring {
    private var storage = RolloutProposalStorage()

    func save(_ proposal: RolloutProposal) async {
        storage.save(proposal)
    }

    func proposal(id: String) async -> RolloutProposal? {
        storage.proposal(id: id)
    }

    func proposals(for source: FlowDatasetSource) async -> [RolloutProposal] {
        storage.proposals(for: source)
    }

    func allProposals() async -> [RolloutProposal] {
        storage.allProposals()
    }

    func delete(id: String) async {
        storage.delete(id: id)
    }
}

actor PersistentRolloutProposalStore: RolloutProposalStoring {
    private let fileURL: URL
    private var storage: RolloutProposalStorage
    nonisolated let restorationDisposition: PersistentStoreRestoreDisposition

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: .default)
        let loadResult = Self.loadStorage(from: self.fileURL)
        self.storage = loadResult.storage
        self.restorationDisposition = loadResult.disposition
        if loadResult.shouldRewrite {
            Self.persistStorage(loadResult.storage, to: self.fileURL)
        }
    }

    func save(_ proposal: RolloutProposal) async {
        storage.save(proposal)
        persist()
    }

    func proposal(id: String) async -> RolloutProposal? {
        storage.proposal(id: id)
    }

    func proposals(for source: FlowDatasetSource) async -> [RolloutProposal] {
        storage.proposals(for: source)
    }

    func allProposals() async -> [RolloutProposal] {
        storage.allProposals()
    }

    func delete(id: String) async {
        storage.delete(id: id)
        persist()
    }

    private func persist() {
        Self.persistStorage(storage, to: fileURL)
    }

    nonisolated private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Flow", isDirectory: true)
            .appendingPathComponent("RolloutProposals", isDirectory: true)
            .appendingPathComponent("rollout_proposals.json", isDirectory: false)
    }

    nonisolated private static func loadStorage(from fileURL: URL) -> RolloutProposalLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .init(storage: RolloutProposalStorage(), shouldRewrite: false, disposition: .empty)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? JSONDecoder.rolloutProposalStoreDecoder.decode(
                RolloutProposalPersistenceEnvelope.self,
                from: data
            ) {
                let storage = RolloutProposalStorage(proposals: envelope.proposals)
                return .init(
                    storage: storage,
                    shouldRewrite: envelope.formatVersion != RolloutProposalPersistenceEnvelope.currentFormatVersion,
                    disposition: envelope.formatVersion == RolloutProposalPersistenceEnvelope.currentFormatVersion ? .current : .migrated
                )
            }

            if let legacyProposals = try? JSONDecoder.rolloutProposalStoreDecoder.decode(
                [RolloutProposal].self,
                from: data
            ) {
                return .init(
                    storage: RolloutProposalStorage(proposals: legacyProposals),
                    shouldRewrite: true,
                    disposition: .migrated
                )
            }

            let recovered = recoverStorage(from: data)
            if recovered.recoveredEntryCount > 0 {
                backupCorruptedFile(at: fileURL)
                FlowLogger.log(
                    level: .warning,
                    message: "Recovered valid rollout proposal subset from malformed persisted file.",
                    metadata: [
                        "path": fileURL.path,
                        "recovered_entries": String(recovered.recoveredEntryCount)
                    ]
                )
                return .init(
                    storage: recovered.storage,
                    shouldRewrite: true,
                    disposition: .recoveredPartial
                )
            }

            backupCorruptedFile(at: fileURL)
            FlowLogger.log(
                level: .error,
                message: "Persisted rollout proposal file was unreadable. Starting with empty proposal state.",
                metadata: [
                    "path": fileURL.path
                ]
            )
            return .init(
                storage: RolloutProposalStorage(),
                shouldRewrite: true,
                disposition: .resetCorrupted
            )
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to load persisted rollout proposal store. Starting with empty state.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
            return .init(
                storage: RolloutProposalStorage(),
                shouldRewrite: false,
                disposition: .resetCorrupted
            )
        }
    }

    nonisolated private static func persistStorage(_ storage: RolloutProposalStorage, to fileURL: URL) {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let envelope = RolloutProposalPersistenceEnvelope(
                formatVersion: RolloutProposalPersistenceEnvelope.currentFormatVersion,
                proposals: storage.persistedProposals()
            )
            let data = try JSONEncoder.rolloutProposalStoreEncoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            FlowLogger.log(
                level: .error,
                message: "Failed to persist rollout proposal store.",
                metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func recoverStorage(from data: Data) -> RolloutProposalRecoveryResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(storage: RolloutProposalStorage(), recoveredEntryCount: 0)
        }

        if let proposals = root["proposals"] as? [Any] {
            return recoveredStorage(fromProposalObjects: proposals)
        }

        return .init(storage: RolloutProposalStorage(), recoveredEntryCount: 0)
    }

    nonisolated private static func recoveredStorage(fromProposalObjects objects: [Any]) -> RolloutProposalRecoveryResult {
        let recoveredProposals: [RolloutProposal] = objects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? JSONDecoder.rolloutProposalStoreDecoder.decode(RolloutProposal.self, from: data)
        }

        guard !recoveredProposals.isEmpty else {
            return .init(storage: RolloutProposalStorage(), recoveredEntryCount: 0)
        }

        return .init(
            storage: RolloutProposalStorage(proposals: recoveredProposals),
            recoveredEntryCount: recoveredProposals.count
        )
    }

    nonisolated private static func backupCorruptedFile(at fileURL: URL) {
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupted.\(safeBackupTimestamp()).json")

        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
            }
        } catch {
            FlowLogger.log(
                level: .warning,
                message: "Failed to back up corrupted rollout proposal file.",
                metadata: [
                    "path": fileURL.path,
                    "backup_path": backupURL.path,
                    "error": String(describing: error)
                ]
            )
        }
    }

    nonisolated private static func safeBackupTimestamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: now)
    }
}

private struct RolloutProposalStorage: Hashable {
    private var proposalsByID: [String: RolloutProposal] = [:]

    init(proposals: [RolloutProposal] = []) {
        self.proposalsByID = Dictionary(uniqueKeysWithValues: proposals.map { ($0.id, $0) })
    }

    mutating func save(_ proposal: RolloutProposal) {
        proposalsByID[proposal.id] = proposal
    }

    func proposal(id: String) -> RolloutProposal? {
        proposalsByID[id]
    }

    func proposals(for source: FlowDatasetSource) -> [RolloutProposal] {
        proposalsByID.values
            .filter { $0.source == source }
            .sorted(by: RolloutProposal.sortComparator)
    }

    func allProposals() -> [RolloutProposal] {
        proposalsByID.values.sorted(by: RolloutProposal.sortComparator)
    }

    mutating func delete(id: String) {
        proposalsByID.removeValue(forKey: id)
    }

    func persistedProposals() -> [RolloutProposal] {
        allProposals()
    }
}

private struct RolloutProposalPersistenceEnvelope: Codable, Hashable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let proposals: [RolloutProposal]
}

private struct RolloutProposalLoadResult {
    let storage: RolloutProposalStorage
    let shouldRewrite: Bool
    let disposition: PersistentStoreRestoreDisposition
}

private struct RolloutProposalRecoveryResult {
    let storage: RolloutProposalStorage
    let recoveredEntryCount: Int
}

private extension RolloutProposal {
    static func sortComparator(lhs: RolloutProposal, rhs: RolloutProposal) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}

private extension JSONEncoder {
    static let rolloutProposalStoreEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let rolloutProposalStoreDecoder = JSONDecoder()
}
