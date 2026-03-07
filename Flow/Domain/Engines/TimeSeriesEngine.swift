import Foundation

enum TimeSeriesEngineError: Error {
    case invalidBucketID(String)
    case invalidYear(Int)
    case invalidMonth(Int)
    case invalidHour(Int)
}

struct TimeSeriesEngine {
    enum BucketKey: Equatable {
        case year(Int)
        case month(year: Int, month: Int)
        case hour(year: Int, month: Int, hour: Int)
    }

    func parse(bucketID: String) throws -> BucketKey {
        if bucketID.hasPrefix("Y:") {
            let yearString = String(bucketID.dropFirst(2))
            guard let year = Int(yearString), year > 0 else {
                throw TimeSeriesEngineError.invalidBucketID(bucketID)
            }
            return .year(year)
        }

        if bucketID.hasPrefix("M:") {
            let payload = String(bucketID.dropFirst(2))
            let parts = payload.split(separator: "-").map(String.init)
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
                throw TimeSeriesEngineError.invalidBucketID(bucketID)
            }
            try validate(year: year, month: month)
            return .month(year: year, month: month)
        }

        if bucketID.hasPrefix("H:") {
            let payload = String(bucketID.dropFirst(2))
            let parts = payload.split(separator: "|").map(String.init)
            guard parts.count == 2 else {
                throw TimeSeriesEngineError.invalidBucketID(bucketID)
            }

            let ym = parts[0].split(separator: "-").map(String.init)
            guard ym.count == 2, let year = Int(ym[0]), let month = Int(ym[1]), let hour = Int(parts[1]) else {
                throw TimeSeriesEngineError.invalidBucketID(bucketID)
            }
            try validate(year: year, month: month, hour: hour)
            return .hour(year: year, month: month, hour: hour)
        }

        throw TimeSeriesEngineError.invalidBucketID(bucketID)
    }

    func yearBucketID(year: Int) throws -> String {
        guard year > 0 else { throw TimeSeriesEngineError.invalidYear(year) }
        return "Y:\(year)"
    }

    func monthBucketID(year: Int, month: Int) throws -> String {
        try validate(year: year, month: month)
        return String(format: "M:%04d-%02d", year, month)
    }

    func hourBucketID(year: Int, month: Int, hour: Int) throws -> String {
        try validate(year: year, month: month, hour: hour)
        return String(format: "H:%04d-%02d|%02d", year, month, hour)
    }

    func nextHourBucketID(from currentBucketID: String) throws -> String {
        let parsed = try parse(bucketID: currentBucketID)
        guard case .hour(let year, let month, let hour) = parsed else {
            throw TimeSeriesEngineError.invalidBucketID(currentBucketID)
        }
        let nextHour = (hour + 1) % 24
        return try hourBucketID(year: year, month: month, hour: nextHour)
    }

    func flows(matching bucketID: String, from flows: [FlowRecord]) -> [FlowRecord] {
        flows.filter { $0.timeBucketID == bucketID }
    }

    func volumeByBucket(bucketIDs: [String], flows: [FlowRecord]) -> [String: Double] {
        var output = Dictionary(uniqueKeysWithValues: bucketIDs.map { ($0, 0.0) })
        for flow in flows where output.keys.contains(flow.timeBucketID) {
            output[flow.timeBucketID, default: 0] += flow.volume
        }
        return output
    }

    private func validate(year: Int, month: Int) throws {
        guard year > 0 else { throw TimeSeriesEngineError.invalidYear(year) }
        guard (1...12).contains(month) else { throw TimeSeriesEngineError.invalidMonth(month) }
    }

    private func validate(year: Int, month: Int, hour: Int) throws {
        try validate(year: year, month: month)
        guard (0...23).contains(hour) else { throw TimeSeriesEngineError.invalidHour(hour) }
    }
}
