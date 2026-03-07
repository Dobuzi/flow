import Testing
@testable import Flow

struct MobilityQueryTests {
    @Test
    func buildsQueryFromAppState() {
        var state = AppState()
        state.selectedYear = 2026
        state.selectedMonth = 3
        state.selectedHour = 9
        state.selectedDatasetSource = .seoulCapitalSnapshot
        state.selectedModes = [.rail, .road]
        state.spatialLevel = .city

        let query = state.toMobilityQuery()

        #expect(query.sources == [.seoulCapitalSnapshot])
        #expect(query.selectedModes == [.rail, .road])
        #expect(query.spatialLevel == .city)
        #expect(query.timeContext.year == 2026)
        #expect(query.timeContext.month == 3)
        #expect(query.timeContext.hour == 9)
        #expect(query.timeContext.granularity == .hourOfDay)
        #expect(query.aggregation.strategy == .rawFlows)
    }

    @Test
    func defaultQueryCoversExistingBehavior() {
        let query = MobilityQuery.default
        #expect(query.sources == [.bundledSample])
        #expect(query.selectedModes == Set(TransportMode.allCases))
        #expect(query.timeContext.granularity == .hourOfDay)
        #expect(query.aggregation.strategy == .rawFlows)
    }
}
