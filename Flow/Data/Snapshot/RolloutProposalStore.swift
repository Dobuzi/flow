import Foundation

enum RolloutProposalControlState: String, Codable, Hashable {
    case active
    case paused
    case halted
}

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
    let controlState: RolloutProposalControlState
    let rollbackPreparedAt: String?

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
        lastDecisionReason: String?,
        controlState: RolloutProposalControlState = .active,
        rollbackPreparedAt: String? = nil
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
        self.controlState = controlState
        self.rollbackPreparedAt = rollbackPreparedAt
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
            lastDecisionReason: rolloutCommand.decisionReason,
            controlState: .active,
            rollbackPreparedAt: rolloutCommand.rolloutMode == .rollbackPrepared
                ? (updatedAt ?? rolloutCommand.decidedAt ?? rolloutCommand.proposal.createdAt)
                : nil
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
        controlState: RolloutProposalControlState? = nil,
        rollbackPreparedAt: String? = nil,
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
            lastDecisionReason: lastDecisionReason ?? self.lastDecisionReason,
            controlState: controlState ?? self.controlState,
            rollbackPreparedAt: rollbackPreparedAt ?? self.rollbackPreparedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case action
        case targetSnapshotID
        case targetDatasetVersion
        case rolloutMode
        case lifecycleState
        case approvalState
        case stages
        case createdAt
        case updatedAt
        case createdBy
        case note
        case executionReadinessSummary
        case lastDecisionAt
        case lastDecisionReason
        case controlState
        case rollbackPreparedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(FlowDatasetSource.self, forKey: .source)
        action = try container.decode(SnapshotActivationCommand.Action.self, forKey: .action)
        targetSnapshotID = try container.decodeIfPresent(String.self, forKey: .targetSnapshotID)
        targetDatasetVersion = try container.decodeIfPresent(String.self, forKey: .targetDatasetVersion)
        rolloutMode = try container.decode(StagedRolloutMode.self, forKey: .rolloutMode)
        lifecycleState = try container.decode(RolloutProposalLifecycleState.self, forKey: .lifecycleState)
        approvalState = try container.decode(ActivationApprovalState.self, forKey: .approvalState)
        stages = try container.decode([RolloutStage].self, forKey: .stages)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        executionReadinessSummary = try container.decodeIfPresent(String.self, forKey: .executionReadinessSummary)
        lastDecisionAt = try container.decodeIfPresent(String.self, forKey: .lastDecisionAt)
        lastDecisionReason = try container.decodeIfPresent(String.self, forKey: .lastDecisionReason)
        controlState = try container.decodeIfPresent(RolloutProposalControlState.self, forKey: .controlState) ?? .active
        rollbackPreparedAt = try container.decodeIfPresent(String.self, forKey: .rollbackPreparedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(targetSnapshotID, forKey: .targetSnapshotID)
        try container.encodeIfPresent(targetDatasetVersion, forKey: .targetDatasetVersion)
        try container.encode(rolloutMode, forKey: .rolloutMode)
        try container.encode(lifecycleState, forKey: .lifecycleState)
        try container.encode(approvalState, forKey: .approvalState)
        try container.encode(stages, forKey: .stages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(executionReadinessSummary, forKey: .executionReadinessSummary)
        try container.encodeIfPresent(lastDecisionAt, forKey: .lastDecisionAt)
        try container.encodeIfPresent(lastDecisionReason, forKey: .lastDecisionReason)
        try container.encode(controlState, forKey: .controlState)
        try container.encodeIfPresent(rollbackPreparedAt, forKey: .rollbackPreparedAt)
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
