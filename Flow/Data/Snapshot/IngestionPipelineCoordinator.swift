import Foundation

struct IngestionPipelineRequest: Hashable {
    let fetchRequest: ExternalDatasetFetchRequest
}

struct IngestionPipelineResult: Hashable {
    enum Status: String, Hashable {
        case succeeded
        case failed
    }

    struct StepStatus: Hashable {
        let adapterFetched: Bool
        let payloadValidated: Bool
        let materializerInvoked: Bool
        let contractValidated: Bool
        let schemaValidated: Bool
        let compatibilityEvaluated: Bool
        let compatibilityPassed: Bool
    }

    struct CompatibilityGate: Hashable {
        let classification: IngestionCompatibilityClassification
        let result: DatasetCompatibilityResult
    }

    let status: Status
    let contract: MaterializedSnapshotContract?
    let materializationWarnings: [String]
    let schemaValidation: DatasetSchemaValidationResult?
    let compatibilityGate: CompatibilityGate?
    let stepStatus: StepStatus
}

enum IngestionPipelineError: Error, Equatable {
    case adapterFailure(ExternalDatasetAdapterError)
    case payloadValidationFailed([String])
    case materializationFailed(String)
    case materializationRejected([String])
    case contractValidationFailed([String])
    case integrityFailed([String])
    case schemaValidationFailed(DatasetSchemaValidationResult)
    case compatibilityFailed(IngestionCompatibilityClassification, DatasetCompatibilityResult)
}

protocol IngestionPipelineCoordinating {
    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult
}

struct DefaultIngestionPipelineCoordinator: IngestionPipelineCoordinating {
    private let adapter: ExternalDatasetAdapting
    private let materializer: SnapshotMaterializing
    private let integrityChecker: SnapshotIntegrityChecking
    private let schemaValidator: DatasetSchemaValidating
    private let compatibilityChecker: DatasetCompatibilityChecking
    private let datasetVersionStore: DatasetVersionStoring?

    init(
        adapter: ExternalDatasetAdapting,
        materializer: SnapshotMaterializing,
        integrityChecker: SnapshotIntegrityChecking = DefaultSnapshotIntegrityChecker(),
        schemaValidator: DatasetSchemaValidating = DatasetSchemaValidator(),
        compatibilityChecker: DatasetCompatibilityChecking? = nil,
        datasetVersionStore: DatasetVersionStoring? = nil
    ) {
        self.adapter = adapter
        self.materializer = materializer
        self.integrityChecker = integrityChecker
        self.schemaValidator = schemaValidator
        self.compatibilityChecker = compatibilityChecker
            ?? DatasetCompatibilityChecker(schemaValidator: schemaValidator)
        self.datasetVersionStore = datasetVersionStore
    }

    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult {
        var status = IngestionPipelineResult.StepStatus(
            adapterFetched: false,
            payloadValidated: false,
            materializerInvoked: false,
            contractValidated: false,
            schemaValidated: false,
            compatibilityEvaluated: false,
            compatibilityPassed: false
        )

        let payload: ExternalDatasetPayload
        do {
            payload = try await adapter.fetch(request: request.fetchRequest)
            status = IngestionPipelineResult.StepStatus(
                adapterFetched: true,
                payloadValidated: status.payloadValidated,
                materializerInvoked: status.materializerInvoked,
                contractValidated: status.contractValidated,
                schemaValidated: status.schemaValidated,
                compatibilityEvaluated: status.compatibilityEvaluated,
                compatibilityPassed: status.compatibilityPassed
            )
        } catch let error as ExternalDatasetAdapterError {
            throw IngestionPipelineError.adapterFailure(error)
        } catch {
            throw IngestionPipelineError.materializationFailed(String(describing: error))
        }

        let payloadValidation = payload.validateStructure()
        guard payloadValidation.isValid else {
            throw IngestionPipelineError.payloadValidationFailed(payloadValidation.reasons)
        }
        status = IngestionPipelineResult.StepStatus(
            adapterFetched: status.adapterFetched,
            payloadValidated: true,
            materializerInvoked: status.materializerInvoked,
            contractValidated: status.contractValidated,
            schemaValidated: status.schemaValidated,
            compatibilityEvaluated: status.compatibilityEvaluated,
            compatibilityPassed: status.compatibilityPassed
        )

        let materializationInput = payload.toMaterializationInput(
            rawPayloadFingerprint: payload.metadata["payload_fingerprint"]
        )

        let materialization: SnapshotMaterializationResult
        do {
            materialization = try await materializer.materialize(
                input: materializationInput
            )
            status = IngestionPipelineResult.StepStatus(
                adapterFetched: status.adapterFetched,
                payloadValidated: status.payloadValidated,
                materializerInvoked: true,
                contractValidated: status.contractValidated,
                schemaValidated: status.schemaValidated,
                compatibilityEvaluated: status.compatibilityEvaluated,
                compatibilityPassed: status.compatibilityPassed
            )
        } catch {
            throw IngestionPipelineError.materializationFailed(String(describing: error))
        }

        if materialization.status == .rejected {
            throw IngestionPipelineError.materializationRejected(materialization.warnings)
        }

        guard let contract = materialization.contract else {
            throw IngestionPipelineError.materializationFailed("materialized_contract_missing")
        }

        let contractValidation = contract.validateStructure()
        guard contractValidation.isValid else {
            throw IngestionPipelineError.contractValidationFailed(contractValidation.reasons)
        }

        let integrityResult = integrityChecker.check(
            contract: contract,
            files: materializationInput.files
        )
        guard integrityResult.isValid else {
            throw IngestionPipelineError.integrityFailed(integrityResult.issues.map(\.code))
        }

        status = IngestionPipelineResult.StepStatus(
            adapterFetched: status.adapterFetched,
            payloadValidated: status.payloadValidated,
            materializerInvoked: status.materializerInvoked,
            contractValidated: true,
            schemaValidated: status.schemaValidated,
            compatibilityEvaluated: status.compatibilityEvaluated,
            compatibilityPassed: status.compatibilityPassed
        )

        let datasetCandidate = flowDataset(from: contract)
        let schemaValidation = schemaValidator.validate(dataset: datasetCandidate)
        guard schemaValidation.isCompatible else {
            throw IngestionPipelineError.schemaValidationFailed(schemaValidation)
        }

        status = IngestionPipelineResult.StepStatus(
            adapterFetched: status.adapterFetched,
            payloadValidated: status.payloadValidated,
            materializerInvoked: status.materializerInvoked,
            contractValidated: status.contractValidated,
            schemaValidated: true,
            compatibilityEvaluated: status.compatibilityEvaluated,
            compatibilityPassed: status.compatibilityPassed
        )

        var compatibilityResult = compatibilityChecker.evaluate(
            dataset: datasetCandidate,
            source: contract.source
        )
        let contractCompatibilityIssues = contract.compatibility.compatibilityReasons + contract.activationEligibility.reasons
        if !contractCompatibilityIssues.isEmpty {
            compatibilityResult = DatasetCompatibilityResult(
                source: compatibilityResult.source,
                isCompatible: false,
                reasons: compatibilityResult.reasons + contractCompatibilityIssues,
                checkedFields: compatibilityResult.checkedFields,
                missingFields: compatibilityResult.missingFields
            )
        }

        let compatibilityClassification = classifyCompatibility(compatibilityResult)
        guard compatibilityClassification == .compatible else {
            throw IngestionPipelineError.compatibilityFailed(compatibilityClassification, compatibilityResult)
        }

        status = IngestionPipelineResult.StepStatus(
            adapterFetched: status.adapterFetched,
            payloadValidated: status.payloadValidated,
            materializerInvoked: status.materializerInvoked,
            contractValidated: status.contractValidated,
            schemaValidated: status.schemaValidated,
            compatibilityEvaluated: true,
            compatibilityPassed: true
        )

        if let datasetVersionStore {
            await datasetVersionStore.upsert(
                contract: contract,
                compatibilityClassification: compatibilityClassification,
                isIngestionCandidate: true,
                indexedAt: ISO8601DateFormatter().string(from: Date())
            )
        }

        return IngestionPipelineResult(
            status: .succeeded,
            contract: contract,
            materializationWarnings: materialization.warnings,
            schemaValidation: schemaValidation,
            compatibilityGate: .init(
                classification: compatibilityClassification,
                result: compatibilityResult
            ),
            stepStatus: status
        )
    }

    private func flowDataset(from contract: MaterializedSnapshotContract) -> FlowDataset {
        FlowDataset(
            datasetID: contract.snapshotID,
            version: contract.datasetVersion,
            source: contract.source.rawValue,
            createdAt: contract.generatedAt,
            spatialLevel: contract.spatialCoverage,
            timeCoverage: contract.timeCoverage,
            recordsCount: contract.recordsCount,
            schemaVersion: contract.schemaVersion
        )
    }

    private func classifyCompatibility(_ result: DatasetCompatibilityResult) -> IngestionCompatibilityClassification {
        if result.isCompatible {
            return .compatible
        }
        if !result.reasons.isEmpty,
           result.reasons.allSatisfy({ $0 == "required_fields_missing" }) {
            return .partiallyCompatible
        }
        return .incompatible
    }
}
