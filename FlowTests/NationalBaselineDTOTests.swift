import Foundation
import Testing
@testable import Flow

struct NationalBaselineDTOTests {
    @Test
    func decodesNationalSnapshotDTOs() throws {
        let manifestData = Data(
            """
            {
              "datasetId": "korea-national-baseline-2025",
              "version": "2025.1",
              "source": "korea_national",
              "generatedAt": "2025-12-31T00:00:00Z",
              "coverageStart": "2025-01-01",
              "coverageEnd": "2025-12-31",
              "schemaVersion": "1.0.0",
              "spatialLevel": "province"
            }
            """.utf8
        )
        let nodeData = Data(
            """
            {
              "nodeId": "11",
              "nameKo": "서울특별시",
              "nameEn": "Seoul",
              "lat": 37.5665,
              "lon": 126.9780,
              "regionCode": "11",
              "regionType": "province",
              "importanceRank": 1
            }
            """.utf8
        )
        let flowData = Data(
            """
            {
              "id": "M:2025-01|11|26|road",
              "originNodeId": "11",
              "destinationNodeId": "26",
              "transportMode": "road",
              "timeBucketId": "M:2025-01",
              "volume": 12345.0,
              "unitType": "passengers",
              "metadata": {
                "corridorName": "Seoul-Busan",
                "regionType": "province",
                "isPassengerFlow": true,
                "isFreightFlow": false,
                "confidenceScore": 0.84,
                "dataSourceTag": "korea_transport_institute"
              }
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        let manifest = try decoder.decode(KoreaNationalDatasetManifestDTO.self, from: manifestData)
        let node = try decoder.decode(KoreaNationalNodeDTO.self, from: nodeData)
        let flow = try decoder.decode(KoreaNationalFlowSnapshotDTO.self, from: flowData)

        #expect(manifest.datasetId == "korea-national-baseline-2025")
        #expect(manifest.spatialLevel == .province)
        #expect(node.nodeId == "11")
        #expect(node.importanceRank == 1)
        #expect(flow.transportMode == "road")
        #expect(flow.unitType == .passengers)
        #expect(flow.metadata?.dataSourceTag == "korea_transport_institute")
    }

    @Test
    func failsWhenRequiredFieldIsMissing() {
        let invalidManifest = Data(
            """
            {
              "datasetId": "korea-national-baseline-2025",
              "version": "2025.1",
              "source": "korea_national",
              "generatedAt": "2025-12-31T00:00:00Z",
              "coverageStart": "2025-01-01",
              "coverageEnd": "2025-12-31",
              "spatialLevel": "province"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(KoreaNationalDatasetManifestDTO.self, from: invalidManifest)
        }
    }
}
