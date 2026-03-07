import Foundation

struct TimeSeriesEngineTests {
    static func runAll() throws {
        try testParseCanonicalBucketIDs()
        try testBucketIDFormatting()
        try testHourPlaybackStepping()
        try testVolumeByBucketZeroFill()
    }

    private static func testParseCanonicalBucketIDs() throws {
        let engine = TimeSeriesEngine()

        guard case .year(2025) = try engine.parse(bucketID: "Y:2025") else {
            throw TestFailure("Expected year bucket parsing")
        }
        guard case .month(2025, 8) = try engine.parse(bucketID: "M:2025-08") else {
            throw TestFailure("Expected month bucket parsing")
        }
        guard case .hour(2025, 8, 14) = try engine.parse(bucketID: "H:2025-08|14") else {
            throw TestFailure("Expected hour bucket parsing")
        }
    }

    private static func testBucketIDFormatting() throws {
        let engine = TimeSeriesEngine()
        let yearID = try engine.yearBucketID(year: 2025)
        let monthID = try engine.monthBucketID(year: 2025, month: 8)
        let hourID = try engine.hourBucketID(year: 2025, month: 8, hour: 4)

        guard yearID == "Y:2025" else {
            throw TestFailure("Unexpected year ID: \(yearID)")
        }
        guard monthID == "M:2025-08" else {
            throw TestFailure("Unexpected month ID: \(monthID)")
        }
        guard hourID == "H:2025-08|04" else {
            throw TestFailure("Unexpected hour ID: \(hourID)")
        }
    }

    private static func testHourPlaybackStepping() throws {
        let engine = TimeSeriesEngine()
        let next = try engine.nextHourBucketID(from: "H:2025-08|14")
        let wrap = try engine.nextHourBucketID(from: "H:2025-08|23")

        guard next == "H:2025-08|15" else {
            throw TestFailure("Expected 14 -> 15, got \(next)")
        }
        guard wrap == "H:2025-08|00" else {
            throw TestFailure("Expected 23 -> 00 wrap, got \(wrap)")
        }
    }

    private static func testVolumeByBucketZeroFill() throws {
        let engine = TimeSeriesEngine()
        let buckets = ["H:2025-08|10", "H:2025-08|11", "H:2025-08|12"]
        let flows = [
            makeFlow(id: "f1", bucketID: "H:2025-08|10", volume: 5),
            makeFlow(id: "f2", bucketID: "H:2025-08|10", volume: 3),
            makeFlow(id: "f3", bucketID: "H:2025-08|12", volume: 7)
        ]

        let totals = engine.volumeByBucket(bucketIDs: buckets, flows: flows)
        guard totals["H:2025-08|10"] == 8 else {
            throw TestFailure("Expected H:...|10 total of 8")
        }
        guard totals["H:2025-08|11"] == 0 else {
            throw TestFailure("Expected missing bucket to be zero-filled")
        }
        guard totals["H:2025-08|12"] == 7 else {
            throw TestFailure("Expected H:...|12 total of 7")
        }
    }

    private static func makeFlow(id: String, bucketID: String, volume: Double) -> FlowRecord {
        FlowRecord(
            id: id,
            originNodeID: "A",
            destinationNodeID: "B",
            transportMode: .road,
            timeBucketID: bucketID,
            volume: volume,
            unitType: .vehicles,
            metadata: nil
        )
    }
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
