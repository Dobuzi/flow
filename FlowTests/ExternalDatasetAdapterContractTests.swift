import Foundation
import Testing
@testable import Flow

struct ExternalDatasetAdapterContractTests {
    @Test
    func payloadCanRepresentFutureAPIDatasetAndMapToMaterializationInput() {
        let payload = makeValidPayload()

        let validation = payload.validateStructure()
        #expect(validation.isValid)

        let input = payload.toMaterializationInput(rawPayloadFingerprint: "sha256:abc")
        #expect(input.source == .seoulCapitalSnapshot)
        #expect(input.providerID == "seoul_open_data")
        #expect(input.upstreamVersion == "2026.03")
        #expect(input.rawPayloadFingerprint == "sha256:abc")
    }

    @Test
    func payloadValidationRejectsIncompleteOutput() {
        let payload = ExternalDatasetPayload(
            source: .koreaNational,
            providerID: "ktdb",
            upstreamVersion: "2026.01",
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .init(role: .manifest, data: Data("{}".utf8), recordCountHint: nil, checksumSHA256: nil),
                .init(role: .nodes, data: Data(), recordCountHint: 10, checksumSHA256: nil)
            ],
            metadata: [:]
        )

        let result = payload.validateStructure()
        #expect(!result.isValid)
        #expect(result.reasons.contains("required_payload_file_missing:flows"))
        #expect(result.reasons.contains("payload_file_empty"))
    }

    @Test
    func adapterErrorModelExposesTypedCategoriesAndRetryability() {
        #expect(ExternalDatasetAdapterError.networkUnavailable.isRetryable)
        #expect(ExternalDatasetAdapterError.timeout(seconds: 10).isRetryable)
        #expect(ExternalDatasetAdapterError.rateLimited(retryAfterSeconds: 30).isRetryable)
        #expect(!ExternalDatasetAdapterError.unauthorized.isRetryable)
        #expect(!ExternalDatasetAdapterError.schemaIncompatible(upstreamSchemaVersion: "2.0.0").isRetryable)

        #expect(ExternalDatasetAdapterError.forbidden.category == "auth")
        #expect(ExternalDatasetAdapterError.payloadInvalid(reason: "malformed").category == "payload")
        #expect(ExternalDatasetAdapterError.unsupportedUpstreamVersion(version: "v9").category == "compatibility")
    }

    @Test
    func currentSnapshotBackedSourcesRemainUsable() async throws {
        let sources: [FlowDatasetSource] = [.bundledSample, .seoulCapitalSnapshot, .koreaNational]

        for source in sources {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            #expect(!dataset.datasetID.isEmpty)
            #expect(!dataset.version.isEmpty)
            #expect(!dataset.schemaVersion.isEmpty)
        }
    }

    private func makeValidPayload() -> ExternalDatasetPayload {
        ExternalDatasetPayload(
            source: .seoulCapitalSnapshot,
            providerID: "seoul_open_data",
            upstreamVersion: "2026.03",
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .init(role: .manifest, data: Data("{\"datasetId\":\"x\"}".utf8), recordCountHint: nil, checksumSHA256: "m1"),
                .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 0, checksumSHA256: "n1"),
                .init(role: .flows, data: Data("{}\n".utf8), recordCountHint: 1, checksumSHA256: "f1")
            ],
            metadata: ["region": "capital"]
        )
    }
}
