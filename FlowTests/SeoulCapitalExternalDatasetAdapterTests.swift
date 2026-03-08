import Foundation
import Testing
@testable import Flow

private struct StubSeoulCapitalRemoteFetcher: SeoulCapitalRemoteFetching {
    let result: Result<SeoulCapitalRemoteResponse, ExternalDatasetAdapterError>

    func fetch(request: ExternalDatasetFetchRequest) async throws -> SeoulCapitalRemoteResponse {
        try result.get()
    }
}

struct SeoulCapitalExternalDatasetAdapterTests {
    @Test
    func producesValidNormalizedPayloadForSuccessfulFetch() async throws {
        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: StubSeoulCapitalRemoteFetcher(result: .success(makeRemoteResponse()))
        )

        let payload = try await adapter.fetch(request: makeRequest())
        let validation = payload.validateStructure()

        #expect(validation.isValid)
        #expect(payload.source == .seoulCapitalSnapshot)
        #expect(payload.upstreamVersion == "2026.03")
        #expect(payload.metadata["refresh_mode"] == "incremental")
        #expect(payload.metadata["schema_version"] == "1.0.0")
        #expect(payload.files.first(where: { $0.role == .flows })?.recordCountHint == 2)
    }

    @Test
    func mapsUpstreamPartialDataToTypedError() async {
        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: StubSeoulCapitalRemoteFetcher(
                result: .failure(.partialData(missingRoles: [.flows]))
            )
        )

        await #expect(throws: ExternalDatasetAdapterError.partialData(missingRoles: [.flows])) {
            _ = try await adapter.fetch(request: makeRequest())
        }
    }

    @Test
    func rejectsSchemaIncompatibleManifest() async {
        var badManifest = makeManifestJSON()
        badManifest = badManifest.replacingOccurrences(of: "\"schemaVersion\":\"1.0.0\"", with: "\"schemaVersion\":\"2.0.0\"")
        let remote = SeoulCapitalRemoteResponse(
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .manifest: Data(badManifest.utf8),
                .nodes: Data(makeNodesJSON().utf8),
                .flows: Data(makeFlowsJSONL().utf8)
            ],
            metadata: [:]
        )
        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: StubSeoulCapitalRemoteFetcher(result: .success(remote))
        )

        await #expect(throws: ExternalDatasetAdapterError.schemaIncompatible(upstreamSchemaVersion: "2.0.0")) {
            _ = try await adapter.fetch(request: makeRequest())
        }
    }

    @Test
    func adapterOutputIsConsumableByMaterializationBoundary() async throws {
        let adapter = SeoulCapitalExternalDatasetAdapter(
            remoteFetcher: StubSeoulCapitalRemoteFetcher(result: .success(makeRemoteResponse()))
        )
        let payload = try await adapter.fetch(request: makeRequest())
        let materializer = DefaultSnapshotMaterializer()

        let result = try await materializer.materialize(
            input: payload.toMaterializationInput(rawPayloadFingerprint: "sha256:test")
        )

        #expect(result.status == .materialized)
        #expect(result.contract?.source == .seoulCapitalSnapshot)
        #expect(result.contract?.schemaVersion == "1.0.0")
    }

    @Test
    func currentSnapshotBackedSourcesRemainUsable() async throws {
        for source in [FlowDatasetSource.bundledSample, .seoulCapitalSnapshot, .koreaNational] {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            #expect(!dataset.datasetID.isEmpty)
        }
    }

    private func makeRequest() -> ExternalDatasetFetchRequest {
        ExternalDatasetFetchRequest(
            source: .seoulCapitalSnapshot,
            providerID: "seoul_open_data",
            expectedSchemaVersion: "1.0.0",
            preferredUpstreamVersion: nil,
            requestID: "req-seoul-1"
        )
    }

    private func makeRemoteResponse() -> SeoulCapitalRemoteResponse {
        SeoulCapitalRemoteResponse(
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .manifest: Data(makeManifestJSON().utf8),
                .nodes: Data(makeNodesJSON().utf8),
                .flows: Data(makeFlowsJSONL().utf8)
            ],
            metadata: ["upstream": "seoul_open_data_plaza"]
        )
    }

    private func makeManifestJSON() -> String {
        #"{"datasetId":"seoul-capital-living-mobility","version":"2026.03","source":"seoul_open_data","generatedAt":"2026-03-08T00:00:00Z","coverageStart":"2026-03-01","coverageEnd":"2026-03-31","schemaVersion":"1.0.0"}"#
    }

    private func makeNodesJSON() -> String {
        #"[{"zoneId":"A01","zoneNameKo":"강남","zoneNameEn":"Gangnam","latitude":37.4979,"longitude":127.0276,"sidoCode":"11","regionType":"district","importanceRank":1},{"zoneId":"B01","zoneNameKo":"종로","zoneNameEn":"Jongno","latitude":37.5729,"longitude":126.9793,"sidoCode":"11","regionType":"district","importanceRank":2}]"#
    }

    private func makeFlowsJSONL() -> String {
        [
            #"{"date":"2026-03-08","hour":8,"originZoneId":"A01","destinationZoneId":"B01","transportMode":"subway","movementCount":120.0,"dataSourceTag":"seoul_open_data","confidenceScore":0.93}"#,
            #"{"date":"2026-03-08","hour":9,"originZoneId":"B01","destinationZoneId":"A01","transportMode":"bus","movementCount":95.0,"dataSourceTag":"seoul_open_data","confidenceScore":0.9}"#
        ].joined(separator: "\n")
    }
}
