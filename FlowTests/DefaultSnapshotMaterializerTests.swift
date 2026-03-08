import Foundation
import Testing
@testable import Flow

struct DefaultSnapshotMaterializerTests {
    @Test
    func materializesValidInputIntoContract() async throws {
        let materializer = DefaultSnapshotMaterializer()
        let input = makeInput()

        let result = try await materializer.materialize(input: input)

        #expect(result.status == .materialized)
        #expect(result.contract?.snapshotID == "korea_national-2026.01")
        #expect(result.contract?.requiredFiles.count == 3)
        #expect(result.contract?.recordsCount == 2)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func rejectsInputWhenRequiredFilesAreMissing() async throws {
        let materializer = DefaultSnapshotMaterializer()
        var input = makeInput()
        input = SnapshotMaterializationInput(
            source: input.source,
            providerID: input.providerID,
            upstreamVersion: input.upstreamVersion,
            fetchedAt: input.fetchedAt,
            rawPayloadFingerprint: input.rawPayloadFingerprint,
            files: input.files.filter { $0.role != .flows },
            metadata: input.metadata
        )

        let result = try await materializer.materialize(input: input)
        #expect(result.status == .rejected)
        #expect(result.warnings.contains("required_file_missing:flows"))
    }

    @Test
    func rejectsInputWhenMandatoryMetadataMissing() async throws {
        let materializer = DefaultSnapshotMaterializer()
        var input = makeInput()
        var metadata = input.metadata
        metadata["schema_version"] = ""

        input = SnapshotMaterializationInput(
            source: input.source,
            providerID: input.providerID,
            upstreamVersion: input.upstreamVersion,
            fetchedAt: input.fetchedAt,
            rawPayloadFingerprint: input.rawPayloadFingerprint,
            files: input.files,
            metadata: metadata
        )

        let result = try await materializer.materialize(input: input)
        #expect(result.status == .rejected)
        #expect(result.warnings == ["schema_version_missing"])
    }

    @Test
    func computesChecksumWhenMissingInInput() async throws {
        let materializer = DefaultSnapshotMaterializer()
        let input = SnapshotMaterializationInput(
            source: .seoulCapitalSnapshot,
            providerID: "seoul_open_data",
            upstreamVersion: "2026.03",
            fetchedAt: "2026-03-08T00:00:00Z",
            rawPayloadFingerprint: nil,
            files: [
                .init(role: .manifest, data: Data("{\"dataset\":\"x\"}".utf8), recordCountHint: nil, checksumSHA256: nil),
                .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 0, checksumSHA256: nil),
                .init(role: .flows, data: Data("{\"a\":1}\n".utf8), recordCountHint: 1, checksumSHA256: nil)
            ],
            metadata: [
                "schema_version": "1.0.0",
                "spatial_coverage": "city",
                "time_coverage": "2026-03"
            ]
        )

        let result = try await materializer.materialize(input: input)
        #expect(result.status == .materialized)
        #expect(result.contract?.requiredFiles.allSatisfy { ($0.checksumSHA256 ?? "").isEmpty == false } == true)
    }

    private func makeInput() -> SnapshotMaterializationInput {
        SnapshotMaterializationInput(
            source: .koreaNational,
            providerID: "ktdb",
            upstreamVersion: "2026.01",
            fetchedAt: "2026-03-08T00:00:00Z",
            rawPayloadFingerprint: "sha256:payload",
            files: [
                .init(role: .manifest, data: Data("{\"dataset_id\":\"korea\"}".utf8), recordCountHint: nil, checksumSHA256: "m"),
                .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 17, checksumSHA256: "n"),
                .init(role: .flows, data: Data("{\"id\":1}\n{\"id\":2}\n".utf8), recordCountHint: 2, checksumSHA256: "f")
            ],
            metadata: [
                "dataset_id": "korea-national-baseline-2026",
                "snapshot_id": "korea_national-2026.01",
                "schema_version": "1.0.0",
                "spatial_coverage": "province",
                "time_coverage": "2026-01~2026-12"
            ]
        )
    }
}
