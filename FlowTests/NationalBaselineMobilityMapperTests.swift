import Testing
@testable import Flow

struct NationalBaselineMobilityMapperTests {
    @Test
    func mapsExternalModesIntoInternalTransportCategories() {
        #expect(NationalBaselineMobilityMapper.mapMode("air") == .air)
        #expect(NationalBaselineMobilityMapper.mapMode("subway") == .rail)
        #expect(NationalBaselineMobilityMapper.mapMode("기차") == .rail)
        #expect(NationalBaselineMobilityMapper.mapMode("ferry") == .maritime)
        #expect(NationalBaselineMobilityMapper.mapMode("express bus") == .road)
        #expect(NationalBaselineMobilityMapper.mapMode("other") == .road)
    }

    @Test
    func mapsFlowOnlyWhenBucketAndVolumeAreValid() {
        let validDTO = KoreaNationalFlowSnapshotDTO(
            id: "M:2025-01|11|26|road",
            originNodeId: "11",
            destinationNodeId: "26",
            transportMode: "road",
            timeBucketId: "M:2025-01",
            volume: 1200,
            unitType: .passengers,
            metadata: KoreaNationalFlowMetadataDTO(
                corridorName: "Seoul-Busan",
                regionType: "province",
                isPassengerFlow: true,
                isFreightFlow: false,
                confidenceScore: 0.9,
                dataSourceTag: "national_baseline"
            )
        )

        let invalidBucketDTO = KoreaNationalFlowSnapshotDTO(
            id: "bad",
            originNodeId: "11",
            destinationNodeId: "26",
            transportMode: "road",
            timeBucketId: "INVALID",
            volume: 1200,
            unitType: .passengers,
            metadata: nil
        )

        let negativeVolumeDTO = KoreaNationalFlowSnapshotDTO(
            id: "bad2",
            originNodeId: "11",
            destinationNodeId: "26",
            transportMode: "road",
            timeBucketId: "M:2025-01",
            volume: -1,
            unitType: .passengers,
            metadata: nil
        )

        let mapped = NationalBaselineMobilityMapper.map(flow: validDTO)

        #expect(mapped != nil)
        #expect(mapped?.transportMode == .road)
        #expect(mapped?.timeBucketID == "M:2025-01")
        #expect(mapped?.metadata?.corridorName == "Seoul-Busan")
        #expect(NationalBaselineMobilityMapper.map(flow: invalidBucketDTO) == nil)
        #expect(NationalBaselineMobilityMapper.map(flow: negativeVolumeDTO) == nil)
    }
}
