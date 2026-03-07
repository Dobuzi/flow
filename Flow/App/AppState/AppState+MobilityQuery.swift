import Foundation

extension AppState {
    func toMobilityQuery() -> MobilityQuery {
        MobilityQuery(
            sources: [selectedDatasetSource],
            selectedModes: selectedModes,
            spatialLevel: spatialLevel,
            timeContext: MobilityTimeContext(
                year: selectedYear,
                month: selectedMonth,
                hour: selectedHour,
                granularity: .hourOfDay
            ),
            aggregation: .default
        )
    }
}
