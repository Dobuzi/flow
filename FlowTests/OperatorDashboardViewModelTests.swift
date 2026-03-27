import Foundation
import Testing
@testable import Flow

struct OperatorDashboardViewModelTests {
    @Test
    @MainActor
    func keepsLiveSourceWithoutProposalNotReady() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalStore = InMemoryRolloutProposalStore()

        await seedReadyCandidate(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            datasetVersion: "2026.04",
            indexedAt: "2026-03-27T01:00:00Z"
        )

        let viewModel = makeViewModel(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            proposalStore: proposalStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))

        #expect(seoul.proposalSummary == nil)
        #expect(seoul.approvalSummary == nil)
        #expect(seoul.rolloutReadinessSummary?.state == .notReady)
        #expect(seoul.rolloutReadinessSummary?.summary == "No rollout proposal")
        #expect(seoul.rolloutPreflight?.recommendation == .blocked)
    }

    @Test
    @MainActor
    func mapsApprovedProposalToProposalBackedReadySummary() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalStore = InMemoryRolloutProposalStore()

        await seedReadyCandidate(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.05",
            datasetVersion: "2026.05",
            indexedAt: "2026-03-27T02:00:00Z"
        )
        await proposalStore.save(
            makeProposal(
                id: "proposal-seoul-approved",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.05",
                targetDatasetVersion: "2026.05",
                rolloutMode: .immediate,
                lifecycleState: .approved,
                approvalState: .approved,
                updatedAt: "2026-03-27T02:05:00Z",
                lastDecisionReason: "Approved for immediate execution"
            )
        )

        let viewModel = makeViewModel(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            proposalStore: proposalStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))

        #expect(seoul.proposalSummary?.proposalID == "proposal-seoul-approved")
        #expect(seoul.approvalSummary?.approvalState == .approved)
        #expect(seoul.approvalSummary?.directExecutionCompatible == true)
        #expect(seoul.approvalSummary?.decisionSummary == "Approved for immediate execution")
        #expect(seoul.rolloutReadinessSummary?.state == .immediateReady)
        #expect(seoul.rolloutPreflight?.recommendation == .immediate)
    }

    @Test
    @MainActor
    func keepsProposalBackedStateSourceScoped() async throws {
        let versionStore = InMemoryDatasetVersionStore()
        let refreshStateStore = InMemoryDatasetRefreshStateStore()
        let historyStore = InMemorySnapshotActivationHistoryStore()
        let proposalStore = InMemoryRolloutProposalStore()

        await seedReadyCandidate(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.06",
            datasetVersion: "2026.06",
            indexedAt: "2026-03-27T03:00:00Z"
        )
        await seedBlockedCandidate(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            source: .koreaNational,
            snapshotID: "national-2026.06",
            datasetVersion: "2026.06",
            indexedAt: "2026-03-27T03:10:00Z"
        )
        await proposalStore.save(
            makeProposal(
                id: "proposal-seoul-approved",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.06",
                targetDatasetVersion: "2026.06",
                rolloutMode: .immediate,
                lifecycleState: .approved,
                approvalState: .approved,
                updatedAt: "2026-03-27T03:05:00Z",
                lastDecisionReason: "Approved for immediate execution"
            )
        )
        await proposalStore.save(
            makeProposal(
                id: "proposal-national-rejected",
                source: .koreaNational,
                targetSnapshotID: "national-2026.06",
                targetDatasetVersion: "2026.06",
                rolloutMode: .staged,
                lifecycleState: .rejected,
                approvalState: .rejected,
                updatedAt: "2026-03-27T03:15:00Z",
                lastDecisionReason: "Candidate failed review"
            )
        )

        let viewModel = makeViewModel(
            versionStore: versionStore,
            refreshStateStore: refreshStateStore,
            historyStore: historyStore,
            proposalStore: proposalStore
        )
        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        let national = try #require(dashboard.sources.first(where: { $0.source == .koreaNational }))

        #expect(seoul.proposalSummary?.proposalID == "proposal-seoul-approved")
        #expect(seoul.approvalSummary?.approvalState == .approved)
        #expect(seoul.rolloutReadinessSummary?.state == .immediateReady)

        #expect(national.proposalSummary?.proposalID == "proposal-national-rejected")
        #expect(national.approvalSummary?.approvalState == .rejected)
        #expect(national.rolloutReadinessSummary?.state == .blocked)
        #expect(national.rolloutReadinessSummary?.blockedReason == "Candidate failed review")
    }

    @Test
    @MainActor
    func choosesMostRecentProposalPerSourceDeterministically() async throws {
        let proposalStore = InMemoryRolloutProposalStore()
        await proposalStore.save(
            makeProposal(
                id: "proposal-old",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.03",
                targetDatasetVersion: "2026.03",
                rolloutMode: .staged,
                lifecycleState: .proposed,
                approvalState: .awaitingApproval,
                updatedAt: "2026-03-27T03:00:00Z"
            )
        )
        await proposalStore.save(
            makeProposal(
                id: "proposal-new",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.04",
                targetDatasetVersion: "2026.04",
                rolloutMode: .immediate,
                lifecycleState: .approved,
                approvalState: .approved,
                updatedAt: "2026-03-27T03:05:00Z"
            )
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: LocalMobilityCatalogRepository(),
            bootstrapStatus: nil,
            proposalStore: proposalStore
        )

        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let seoul = try #require(dashboard.sources.first(where: { $0.source == .seoulCapitalSnapshot }))
        #expect(seoul.proposalSummary?.proposalID == "proposal-new")
        #expect(seoul.proposalSummary?.targetSnapshotID == "seoul-2026.04")
    }

    @Test
    @MainActor
    func keepsStaticSourceSafeWithoutProposalDrivenState() async throws {
        let proposalStore = InMemoryRolloutProposalStore()
        await proposalStore.save(
            makeProposal(
                id: "proposal-seoul-only",
                source: .seoulCapitalSnapshot,
                targetSnapshotID: "seoul-2026.04",
                targetDatasetVersion: "2026.04",
                rolloutMode: .staged,
                lifecycleState: .proposed,
                approvalState: .awaitingApproval,
                updatedAt: "2026-03-27T04:00:00Z"
            )
        )

        let viewModel = OperatorDashboardViewModel(
            catalogRepository: LocalMobilityCatalogRepository(),
            bootstrapStatus: nil,
            proposalStore: proposalStore
        )

        await viewModel.load()

        let dashboard = try #require(viewModel.dashboard)
        let bundled = try #require(dashboard.sources.first(where: { $0.source == .bundledSample }))

        #expect(bundled.proposalSummary == nil)
        #expect(bundled.liveSummary == nil)
        #expect(bundled.healthSummary.state == .static)
        #expect(bundled.approvalSummary == nil)
        #expect(bundled.rolloutPreflight?.recommendation == .notApplicable)
    }

    private func makeViewModel(
        versionStore: InMemoryDatasetVersionStore,
        refreshStateStore: InMemoryDatasetRefreshStateStore,
        historyStore: InMemorySnapshotActivationHistoryStore,
        proposalStore: RolloutProposalStoring
    ) -> OperatorDashboardViewModel {
        let policy = DefaultSnapshotActivationPolicy(versionStore: versionStore)
        let repository = LocalMobilityCatalogRepository(
            liveMetadataEnricher: CatalogLiveMetadataEnricher(
                versionStore: versionStore,
                activationPolicy: policy,
                refreshStateStore: refreshStateStore,
                activationStateProjector: DefaultSnapshotActivationStateProjector(
                    activationPolicy: policy,
                    historyStore: historyStore,
                    versionStore: versionStore,
                    nowProvider: { "2026-03-27T04:30:00Z" }
                )
            )
        )

        return OperatorDashboardViewModel(
            catalogRepository: repository,
            proposalStore: proposalStore,
            activationHistoryStore: historyStore,
            refreshStateStore: refreshStateStore
        )
    }

    private func seedReadyCandidate(
        versionStore: InMemoryDatasetVersionStore,
        refreshStateStore: InMemoryDatasetRefreshStateStore,
        historyStore: InMemorySnapshotActivationHistoryStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        indexedAt: String
    ) async {
        await seedVersion(
            store: versionStore,
            source: source,
            snapshotID: snapshotID,
            datasetVersion: datasetVersion,
            indexedAt: indexedAt
        )
        await refreshStateStore.record(
            DatasetRefreshResult(
                source: source,
                trigger: .manual,
                status: .succeeded,
                startedAt: indexedAt,
                finishedAt: ISO8601DateFormatter().string(from: ISO8601DateFormatter().date(from: indexedAt)!.addingTimeInterval(60)),
                storedSnapshotID: snapshotID,
                storedDatasetVersion: datasetVersion,
                compatibilityClassification: .compatible,
                eligibleForActivation: true,
                didStoreCandidate: true,
                error: nil
            )
        )
        _ = historyStore
    }

    private func seedBlockedCandidate(
        versionStore: InMemoryDatasetVersionStore,
        refreshStateStore: InMemoryDatasetRefreshStateStore,
        historyStore: InMemorySnapshotActivationHistoryStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        indexedAt: String
    ) async {
        await seedVersion(
            store: versionStore,
            source: source,
            snapshotID: snapshotID,
            datasetVersion: datasetVersion,
            indexedAt: indexedAt
        )
        await refreshStateStore.record(
            DatasetRefreshResult(
                source: source,
                trigger: .periodic,
                status: .failed,
                startedAt: indexedAt,
                finishedAt: ISO8601DateFormatter().string(from: ISO8601DateFormatter().date(from: indexedAt)!.addingTimeInterval(60)),
                storedSnapshotID: nil,
                storedDatasetVersion: nil,
                compatibilityClassification: .incompatible,
                eligibleForActivation: false,
                didStoreCandidate: false,
                error: .ingestionFailed(.adapterFailure(.networkUnavailable))
            )
        )
        await historyStore.append(
            SnapshotActivationHistoryEvent(
                eventID: "blocked-\(source.rawValue)",
                type: .promoteBlocked,
                timestamp: ISO8601DateFormatter().string(from: ISO8601DateFormatter().date(from: indexedAt)!.addingTimeInterval(90)),
                metadata: .init(
                    source: source,
                    snapshotID: snapshotID,
                    datasetVersion: datasetVersion,
                    commandID: "blocked-\(source.rawValue)",
                    commandAction: .promote,
                    trigger: .operatorManual,
                    requestedBy: "tester",
                    note: nil,
                    validation: nil,
                    guardDecision: nil,
                    execution: nil
                ),
                result: .init(
                    status: .blocked,
                    reasonCode: "candidate_incompatible",
                    message: nil
                )
            )
        )
    }

    private func seedVersion(
        store: InMemoryDatasetVersionStore,
        source: FlowDatasetSource,
        snapshotID: String,
        datasetVersion: String,
        indexedAt: String
    ) async {
        let contract = MaterializedSnapshotContract(
            snapshotID: snapshotID,
            source: source,
            schemaVersion: "1.0.0",
            datasetVersion: datasetVersion,
            generatedAt: indexedAt,
            timeCoverage: "2026-03-01~2026-03-31",
            spatialCoverage: .city,
            recordsCount: 100,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 10, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 20, recordCount: 2),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 30, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        await store.upsert(
            contract: contract,
            compatibilityClassification: .compatible,
            isIngestionCandidate: true,
            indexedAt: indexedAt
        )
    }

    private func makeProposal(
        id: String,
        source: FlowDatasetSource,
        targetSnapshotID: String,
        targetDatasetVersion: String,
        rolloutMode: StagedRolloutMode,
        lifecycleState: RolloutProposalLifecycleState,
        approvalState: ActivationApprovalState,
        updatedAt: String,
        lastDecisionReason: String? = nil
    ) -> RolloutProposal {
        RolloutProposal(
            id: id,
            source: source,
            action: .promote,
            targetSnapshotID: targetSnapshotID,
            targetDatasetVersion: targetDatasetVersion,
            rolloutMode: rolloutMode,
            lifecycleState: lifecycleState,
            approvalState: approvalState,
            stages: [],
            createdAt: updatedAt,
            updatedAt: updatedAt,
            createdBy: "operator-1",
            note: nil,
            executionReadinessSummary: "candidate_ready",
            lastDecisionAt: updatedAt,
            lastDecisionReason: lastDecisionReason
        )
    }
}
