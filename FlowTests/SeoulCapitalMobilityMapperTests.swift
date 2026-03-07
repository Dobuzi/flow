import Testing
@testable import Flow

struct SeoulCapitalMobilityMapperTests {
    @Test
    func mapsExternalTransportModesIntoInternalCategories() {
        #expect(SeoulCapitalMobilityMapper.mapMode("air") == .air)
        #expect(SeoulCapitalMobilityMapper.mapMode("지하철") == .rail)
        #expect(SeoulCapitalMobilityMapper.mapMode("rail/train") == .rail)
        #expect(SeoulCapitalMobilityMapper.mapMode("express bus") == .road)
        #expect(SeoulCapitalMobilityMapper.mapMode("walking") == .road)
        #expect(SeoulCapitalMobilityMapper.mapMode("other") == .road)
        #expect(SeoulCapitalMobilityMapper.mapMode("ferry") == .maritime)
    }

    @Test
    func mapsSnapshotFlowIntoCanonicalBucketFormat() {
        let dto = SeoulCapitalFlowSnapshotDTO(
            date: "2025-01-15",
            hour: 12,
            originZoneId: "11110515",
            destinationZoneId: "11680521",
            transportMode: "subway",
            movementCount: 1234,
            dataSourceTag: "seoul_open_data_plaza",
            confidenceScore: 0.9
        )
        let record = SeoulCapitalMobilityMapper.map(flow: dto)

        #expect(record != nil)
        #expect(record?.timeBucketID == "H:2025-01|12")
        #expect(record?.transportMode == .rail)
        #expect(record?.unitType == .passengers)
    }
}
