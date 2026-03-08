import CryptoKit
import Foundation
import Testing
@testable import Flow

private struct StubExternalAdapter: ExternalDatasetAdapting {
    let source: FlowDatasetSource
    let capabilities: ExternalDatasetAdapterCapabilities
    let result: Result<ExternalDatasetPayload, ExternalDatasetAdapterError>

    init(
        source: FlowDatasetSource = .koreaNational,
        result: Result<ExternalDatasetPayload, ExternalDatasetAdapterError>
    ) {
        self.source = source
        self.capabilities = ExternalDatasetAdapterCapabilities(
            supportsIncrementalFetch: false,
            supportsVersionSelection: true,
            maxPageSize: nil
        )
        self.result = result
    }

    func fetch(request: ExternalDatasetFetchRequest) async throws -> ExternalDatasetPayload {
        try result.get()
    }
}

private struct StubMaterializer: SnapshotMaterializing {
    let result: Result<SnapshotMaterializationResult, Error>

    func materialize(input: SnapshotMaterializationInput) async throws -> SnapshotMaterializationResult {
        try result.get()
    }
}

private struct StubIntegrityChecker: SnapshotIntegrityChecking {
    let result: SnapshotIntegrityCheckResult

    func check(
        contract: MaterializedSnapshotContract,
        files: [SnapshotMaterializationInput.FilePayload]
    ) -> SnapshotIntegrityCheckResult {
        result
    }
}

private struct StubSchemaValidator: DatasetSchemaValidating {
    let result: DatasetSchemaValidationResult

    func validate(dataset: FlowDataset) -> DatasetSchemaValidationResult {
        result
    }
}

private struct StubCompatibilityChecker: DatasetCompatibilityChecking {
    let result: DatasetCompatibilityResult

    func evaluate(dataset: FlowDataset, source: FlowDatasetSource) -> DatasetCompatibilityResult {
        result
    }
}

struct IngestionPipelineCoordinatorTests {
    @Test
    func coordinatorWorksWithDefaultSnapshotMaterializer() async throws {
        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: DefaultSnapshotMaterializer()
        )

        let output = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
        #expect(output.status == .succeeded)
        #expect(output.contract?.source == .koreaNational)
        #expect(output.contract?.requiredFiles.count == 3)
    }

    @Test
    func succeedsWhenAllPipelineStagesPass() async throws {
        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(
                status: .materialized,
                contract: makeValidContract(),
                warnings: []
            ))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: []))
        )

        let output = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))

        #expect(output.status == .succeeded)
        #expect(output.contract?.snapshotID == "korea_national-2026.01")
        #expect(output.stepStatus.adapterFetched)
        #expect(output.stepStatus.payloadValidated)
        #expect(output.stepStatus.materializerInvoked)
        #expect(output.stepStatus.contractValidated)
        #expect(output.stepStatus.schemaValidated)
        #expect(output.stepStatus.compatibilityEvaluated)
        #expect(output.stepStatus.compatibilityPassed)
        #expect(output.schemaValidation?.isCompatible == true)
        #expect(output.compatibilityGate?.classification == .compatible)
    }

    @Test
    func surfacesAdapterFailure() async {
        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .failure(.rateLimited(retryAfterSeconds: 30))),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: makeValidContract(), warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: []))
        )

        await #expect(throws: IngestionPipelineError.adapterFailure(.rateLimited(retryAfterSeconds: 30))) {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
        }
    }

    @Test
    func rejectsInvalidAdapterPayload() async {
        let invalidPayload = ExternalDatasetPayload(
            source: .koreaNational,
            providerID: "ktdb",
            upstreamVersion: "2026.01",
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .init(role: .manifest, data: Data("{}".utf8), recordCountHint: nil, checksumSHA256: nil),
                .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 0, checksumSHA256: nil)
            ],
            metadata: [:]
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(invalidPayload)),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: makeValidContract(), warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: []))
        )

        await #expect(throws: IngestionPipelineError.payloadValidationFailed(["required_payload_file_missing:flows"])) {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
        }
    }

    @Test
    func rejectsInvalidMaterializedContract() async {
        let invalidContract = MaterializedSnapshotContract(
            snapshotID: "",
            source: .koreaNational,
            schemaVersion: "1.0.0",
            datasetVersion: "2026.01",
            generatedAt: "2026-03-08T00:00:00Z",
            timeCoverage: "2026-01~2026-12",
            spatialCoverage: .province,
            recordsCount: 100,
            requiredFiles: standardRequiredFiles(),
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: []
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: invalidContract, warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: []))
        )

        await #expect(throws: IngestionPipelineError.contractValidationFailed(["snapshot_id_missing"])) {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
        }
    }

    @Test
    func surfacesIntegrityFailure() async {
        let files = makeValidPayload().files
        let contractWithMismatch = MaterializedSnapshotContract(
            snapshotID: "korea_national-2026.01",
            source: .koreaNational,
            schemaVersion: "1.0.0",
            datasetVersion: "2026.01",
            generatedAt: "2026-03-08T00:00:00Z",
            timeCoverage: "2026-01~2026-12",
            spatialCoverage: .province,
            recordsCount: 1,
            requiredFiles: [
                SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: sha256Hex(for: files[0].data), byteCount: files[0].data.count, recordCount: nil),
                SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: sha256Hex(for: files[1].data), byteCount: files[1].data.count, recordCount: 0),
                SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "wrong-checksum", byteCount: files[2].data.count, recordCount: 1)
            ],
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: contractWithMismatch, warnings: [])))
        )

        await #expect(throws: IngestionPipelineError.integrityFailed(["checksum_mismatch:flows"])) {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
        }
    }

    @Test
    func surfacesSchemaValidationFailure() async {
        let contract = makeValidContract(schemaVersion: "2.0.0")
        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: contract, warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: []))
        )

        do {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
            Issue.record("Expected schemaValidationFailed")
        } catch let error as IngestionPipelineError {
            switch error {
            case .schemaValidationFailed(let result):
                #expect(result.schemaVersion == "2.0.0")
                #expect(result.isCompatible == false)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-pipeline error: \(error)")
        }
    }

    @Test
    func classifiesPartiallyCompatibleSnapshot() async {
        let compatibility = DatasetCompatibilityResult(
            source: .koreaNational,
            isCompatible: false,
            reasons: ["required_fields_missing"],
            checkedFields: ["datasetID"],
            missingFields: ["datasetID"]
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: makeValidContract(), warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: [])),
            schemaValidator: StubSchemaValidator(result: .init(
                schemaVersion: "1.0.0",
                supportedVersions: ["1.0.0"],
                isCompatible: true,
                reason: nil
            )),
            compatibilityChecker: StubCompatibilityChecker(result: compatibility)
        )

        do {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
            Issue.record("Expected compatibilityFailed(partiallyCompatible)")
        } catch let error as IngestionPipelineError {
            switch error {
            case .compatibilityFailed(let classification, let result):
                #expect(classification == .partiallyCompatible)
                #expect(result.reasons == ["required_fields_missing"])
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-pipeline error: \(error)")
        }
    }

    @Test
    func classifiesIncompatibleSnapshot() async {
        let compatibility = DatasetCompatibilityResult(
            source: .koreaNational,
            isCompatible: false,
            reasons: ["schema_version_unsupported"],
            checkedFields: ["schemaVersion"],
            missingFields: []
        )

        let coordinator = DefaultIngestionPipelineCoordinator(
            adapter: StubExternalAdapter(result: .success(makeValidPayload())),
            materializer: StubMaterializer(result: .success(.init(status: .materialized, contract: makeValidContract(), warnings: []))),
            integrityChecker: StubIntegrityChecker(result: .init(isValid: true, issues: [])),
            schemaValidator: StubSchemaValidator(result: .init(
                schemaVersion: "1.0.0",
                supportedVersions: ["1.0.0"],
                isCompatible: true,
                reason: nil
            )),
            compatibilityChecker: StubCompatibilityChecker(result: compatibility)
        )

        do {
            _ = try await coordinator.ingest(request: .init(fetchRequest: makeRequest()))
            Issue.record("Expected compatibilityFailed(incompatible)")
        } catch let error as IngestionPipelineError {
            switch error {
            case .compatibilityFailed(let classification, let result):
                #expect(classification == .incompatible)
                #expect(result.reasons == ["schema_version_unsupported"])
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-pipeline error: \(error)")
        }
    }

    @Test
    func currentSnapshotBackedSourcesRemainCompatible() async throws {
        for source in [FlowDatasetSource.bundledSample, .seoulCapitalSnapshot, .koreaNational] {
            let dataset = try await MobilityRepositoryFactory.flowRepository(for: source).fetchDataset()
            #expect(!dataset.datasetID.isEmpty)
        }
    }

    private func makeRequest() -> ExternalDatasetFetchRequest {
        ExternalDatasetFetchRequest(
            source: .koreaNational,
            providerID: "ktdb",
            expectedSchemaVersion: "1.0.0",
            preferredUpstreamVersion: nil,
            requestID: "req-1"
        )
    }

    private func makeValidPayload() -> ExternalDatasetPayload {
        ExternalDatasetPayload(
            source: .koreaNational,
            providerID: "ktdb",
            upstreamVersion: "2026.01",
            fetchedAt: "2026-03-08T00:00:00Z",
            files: [
                .init(role: .manifest, data: Data("{}".utf8), recordCountHint: nil, checksumSHA256: nil),
                .init(role: .nodes, data: Data("[]".utf8), recordCountHint: 0, checksumSHA256: nil),
                .init(role: .flows, data: Data("{}\n".utf8), recordCountHint: 1, checksumSHA256: nil)
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

    private func makeValidContract(schemaVersion: String = "1.0.0") -> MaterializedSnapshotContract {
        MaterializedSnapshotContract(
            snapshotID: "korea_national-2026.01",
            source: .koreaNational,
            schemaVersion: schemaVersion,
            datasetVersion: "2026.01",
            generatedAt: "2026-03-08T00:00:00Z",
            timeCoverage: "2026-01~2026-12",
            spatialCoverage: .province,
            recordsCount: 100,
            requiredFiles: standardRequiredFiles(),
            compatibility: SnapshotCompatibilityMetadata(
                isSchemaCompatible: true,
                isCompatibilityCheckPassed: true,
                compatibilityReasons: [],
                checkedFields: ["schemaVersion"]
            ),
            activationEligibility: SnapshotActivationEligibility(state: .eligible, reasons: [])
        )
    }

    private func standardRequiredFiles() -> [SnapshotRequiredFile] {
        [
            SnapshotRequiredFile(role: .manifest, relativePath: "manifest.json", checksumSHA256: "m", byteCount: 100, recordCount: nil),
            SnapshotRequiredFile(role: .nodes, relativePath: "nodes.json", checksumSHA256: "n", byteCount: 200, recordCount: 17),
            SnapshotRequiredFile(role: .flows, relativePath: "flows.jsonl", checksumSHA256: "f", byteCount: 300, recordCount: 100)
        ]
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
