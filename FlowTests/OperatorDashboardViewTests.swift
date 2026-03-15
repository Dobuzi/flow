import Testing
@testable import Flow

struct OperatorDashboardViewTests {
    @Test
    func buildsLiveCapableCardWithCandidateReadinessAndRefreshHealth() throws {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
                OperatorSourceSummary(
                    source: .seoulCapitalSnapshot,
                    displayName: "Seoul Capital Area",
                    isLiveCapable: true,
                    liveSummary: OperatorSourceLiveSummary(
                        activeSnapshotID: "seoul-2026.03",
                        lastKnownGoodSnapshotID: "seoul-2026.02",
                        latestCandidateSnapshotID: "seoul-2026.04",
                        latestCandidateCompatibility: .compatible,
                        latestCandidateEligibleForActivation: true,
                        lastRefreshOutcome: .success,
                        lastRefreshAt: "2026-03-15T08:00:00Z",
                        rollbackAvailable: true,
                        operatorActivationStatus: .activeRollbackReady,
                        readiness: .ready,
                        syncState: .ready
                    )
                )
            ],
            bootstrapStatus: nil
        )

        let card = try #require(OperatorDashboardPresentation.cardModels(from: summary).first)

        #expect(card.title == "Seoul Capital Area")
        #expect(card.capabilityLabel == "Live-capable")
        #expect(card.statusSummary == "Active, rollback ready")
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Active Snapshot", value: "seoul-2026.03")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Last Known Good", value: "seoul-2026.02")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Latest Candidate", value: "seoul-2026.04")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Candidate Compatibility", value: "Compatible")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Candidate Ready", value: "Ready")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Last Refresh", value: "Success")))
        #expect(card.rows.contains(OperatorDashboardCardRow(label: "Rollback Available", value: "Yes")))
    }

    @Test
    func buildsStaticCardWithoutBogusOperatorState() {
        let card = OperatorDashboardPresentation.cardModel(
            from: OperatorSourceSummary(
                source: .bundledSample,
                displayName: "Bundled Sample",
                isLiveCapable: false,
                liveSummary: nil
            )
        )

        #expect(card.capabilityLabel == "Static")
        #expect(card.statusSummary == "Packaged baseline dataset")
        #expect(card.rows == [
            OperatorDashboardCardRow(label: "Refresh", value: "Not supported"),
            OperatorDashboardCardRow(label: "Activation", value: "Not applicable")
        ])
    }

    @Test
    func preservesDeterministicSourceOrderingAcrossCards() {
        let summary = OperatorDashboardSummary(
            catalogVersion: "2026.03",
            sources: [
                OperatorSourceSummary(source: .bundledSample, displayName: "Bundled Sample", isLiveCapable: false, liveSummary: nil),
                OperatorSourceSummary(source: .seoulCapitalSnapshot, displayName: "Seoul Capital Area", isLiveCapable: true, liveSummary: nil),
                OperatorSourceSummary(source: .koreaNational, displayName: "Korea National", isLiveCapable: true, liveSummary: nil)
            ],
            bootstrapStatus: nil
        )

        let cards = OperatorDashboardPresentation.cardModels(from: summary)

        #expect(cards.map(\.source) == [.bundledSample, .seoulCapitalSnapshot, .koreaNational])
    }

    @Test
    func surfacesDegradedBootstrapBanner() throws {
        let banner = OperatorDashboardPresentation.bootstrapBanner(
            from: PersistentOperatorStateBootstrapStatus(
                activationState: .current,
                refreshState: .resetCorrupted,
                activationHistory: .recoveredPartial
            )
        )

        let resolved = try #require(banner)
        #expect(resolved.isDegraded)
        #expect(resolved.title == "Recovered With Degraded Operator State")
        #expect(resolved.detail.contains("Activation current"))
        #expect(resolved.detail.contains("Refresh reset corrupted"))
        #expect(resolved.detail.contains("History partial recovery"))
    }
}
