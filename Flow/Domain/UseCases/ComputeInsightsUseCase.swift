import Foundation

struct InsightsSummary: Equatable {
    struct ModeShareItem: Equatable, Identifiable {
        let mode: TransportMode
        let count: Int
        let volume: Double
        let ratio: Double

        var id: TransportMode { mode }
    }

    struct CorridorItem: Equatable, Identifiable {
        let id: String
        let label: String
        let volume: Double
        let flowCount: Int
    }

    struct TimeDistributionItem: Equatable, Identifiable {
        let id: String
        let bucketID: String
        let volume: Double
        let flowCount: Int
    }

    let datasetVersion: String?
    let totalFlowCount: Int
    let totalNodeCount: Int
    let scopedFlowCount: Int
    let scopedVolume: Double
    let activeTimeLabel: String
    let activeModes: [TransportMode]
    let modeShare: [ModeShareItem]
    let topCorridors: [CorridorItem]
    let timeDistribution: [TimeDistributionItem]
}

struct ComputeInsightsUseCase {
    private let filteringEngine: FilteringEngine
    private let timeSeriesEngine: TimeSeriesEngine

    init(
        filteringEngine: FilteringEngine = FilteringEngine(),
        timeSeriesEngine: TimeSeriesEngine = TimeSeriesEngine()
    ) {
        self.filteringEngine = filteringEngine
        self.timeSeriesEngine = timeSeriesEngine
    }

    func execute(
        datasetVersion: String?,
        flows: [FlowRecord],
        nodes: [LocationNode],
        state: AppState
    ) -> InsightsSummary {
        let activeBucketID = resolveBucketID(
            flows: flows,
            year: state.selectedYear,
            month: state.selectedMonth,
            hour: state.selectedHour
        )

        let scopeByTime = activeBucketID.map { bucketID in
            flows.filter { $0.timeBucketID == bucketID }
        } ?? []

        let scopedFlows = filteringEngine.filter(
            flows: scopeByTime,
            nodes: nodes,
            criteria: FlowFilterCriteria(
                modes: state.selectedModes,
                allowedRegionCodes: nil,
                minimumVolume: nil
            )
        )

        let modeScopedAllFlows = filteringEngine.filter(
            flows: flows,
            nodes: nodes,
            criteria: FlowFilterCriteria(
                modes: state.selectedModes,
                allowedRegionCodes: nil,
                minimumVolume: nil
            )
        )

        let scopedVolume = scopedFlows.reduce(0) { $0 + $1.volume }
        let modeShare = buildModeShare(scopedFlows: scopedFlows, totalVolume: scopedVolume)
        let topCorridors = buildTopCorridors(scopedFlows: scopedFlows, nodes: nodes)
        let timeDistribution = buildTimeDistribution(flows: modeScopedAllFlows)

        return InsightsSummary(
            datasetVersion: datasetVersion,
            totalFlowCount: flows.count,
            totalNodeCount: nodes.count,
            scopedFlowCount: scopedFlows.count,
            scopedVolume: scopedVolume,
            activeTimeLabel: String(format: "%04d-%02d %02d:00", state.selectedYear, state.selectedMonth, state.selectedHour),
            activeModes: state.selectedModes.sorted { $0.rawValue < $1.rawValue },
            modeShare: modeShare,
            topCorridors: topCorridors,
            timeDistribution: timeDistribution
        )
    }

    private func buildModeShare(scopedFlows: [FlowRecord], totalVolume: Double) -> [InsightsSummary.ModeShareItem] {
        let grouped = Dictionary(grouping: scopedFlows, by: \.transportMode)
        return TransportMode.allCases.compactMap { mode in
            guard let bucket = grouped[mode], !bucket.isEmpty else { return nil }
            let volume = bucket.reduce(0) { $0 + $1.volume }
            let ratio = totalVolume > 0 ? volume / totalVolume : 0
            return InsightsSummary.ModeShareItem(
                mode: mode,
                count: bucket.count,
                volume: volume,
                ratio: ratio
            )
        }
        .sorted { $0.volume > $1.volume }
    }

    private func buildTopCorridors(scopedFlows: [FlowRecord], nodes: [LocationNode]) -> [InsightsSummary.CorridorItem] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        let grouped = Dictionary(grouping: scopedFlows) { flow in
            "\(flow.originNodeID)->\(flow.destinationNodeID)"
        }

        return grouped.compactMap { key, bucket in
            let ids = key.split(separator: "->").map(String.init)
            guard ids.count == 2 else { return nil }
            let origin = nodesByID[ids[0]]?.nameEn ?? nodesByID[ids[0]]?.nameKo ?? ids[0]
            let destination = nodesByID[ids[1]]?.nameEn ?? nodesByID[ids[1]]?.nameKo ?? ids[1]

            return InsightsSummary.CorridorItem(
                id: key,
                label: "\(origin) → \(destination)",
                volume: bucket.reduce(0) { $0 + $1.volume },
                flowCount: bucket.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.volume != rhs.volume {
                return lhs.volume > rhs.volume
            }
            return lhs.id < rhs.id
        }
        .prefix(5)
        .map { $0 }
    }

    private func buildTimeDistribution(flows: [FlowRecord]) -> [InsightsSummary.TimeDistributionItem] {
        let grouped = Dictionary(grouping: flows, by: \.timeBucketID)
        return grouped.map { bucketID, bucket in
            InsightsSummary.TimeDistributionItem(
                id: bucketID,
                bucketID: bucketID,
                volume: bucket.reduce(0) { $0 + $1.volume },
                flowCount: bucket.count
            )
        }
        .sorted { lhs, rhs in
            let lhsParsed = try? timeSeriesEngine.parse(bucketID: lhs.bucketID)
            let rhsParsed = try? timeSeriesEngine.parse(bucketID: rhs.bucketID)
            return compare(lhs: lhsParsed, rhs: rhsParsed, lhsRaw: lhs.bucketID, rhsRaw: rhs.bucketID)
        }
    }

    private func compare(
        lhs: TimeSeriesEngine.BucketKey?,
        rhs: TimeSeriesEngine.BucketKey?,
        lhsRaw: String,
        rhsRaw: String
    ) -> Bool {
        switch (lhs, rhs) {
        case (.year(let l), .year(let r)):
            return l < r
        case (.month(let ly, let lm), .month(let ry, let rm)):
            return (ly, lm) < (ry, rm)
        case (.hour(let ly, let lm, let lh), .hour(let ry, let rm, let rh)):
            return (ly, lm, lh) < (ry, rm, rh)
        case (.year, .month), (.year, .hour), (.month, .hour):
            return true
        case (.month, .year), (.hour, .year), (.hour, .month):
            return false
        default:
            return lhsRaw < rhsRaw
        }
    }

    private func resolveBucketID(flows: [FlowRecord], year: Int, month: Int, hour: Int) -> String? {
        let hourID = try? timeSeriesEngine.hourBucketID(year: year, month: month, hour: hour)
        if let hourID, flows.contains(where: { $0.timeBucketID == hourID }) {
            return hourID
        }

        let monthID = try? timeSeriesEngine.monthBucketID(year: year, month: month)
        if let monthID, flows.contains(where: { $0.timeBucketID == monthID }) {
            return monthID
        }

        let yearID = try? timeSeriesEngine.yearBucketID(year: year)
        if let yearID, flows.contains(where: { $0.timeBucketID == yearID }) {
            return yearID
        }
        return monthID ?? yearID ?? hourID
    }
}
