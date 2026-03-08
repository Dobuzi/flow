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
        let compatibilityPassed: Bool
    }

    let status: Status
    let contract: MaterializedSnapshotContract?
    let materializationWarnings: [String]
    let stepStatus: StepStatus
}

enum IngestionPipelineError: Error, Equatable {
    case adapterFailure(ExternalDatasetAdapterError)
    case payloadValidationFailed([String])
    case materializationFailed(String)
    case materializationRejected([String])
    case contractValidationFailed([String])
    case integrityFailed([String])
    case compatibilityFailed([String])
}

protocol IngestionPipelineCoordinating {
    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult
}

struct DefaultIngestionPipelineCoordinator: IngestionPipelineCoordinating {
    private let adapter: ExternalDatasetAdapting
    private let materializer: SnapshotMaterializing
    private let integrityChecker: SnapshotIntegrityChecking

    init(
        adapter: ExternalDatasetAdapting,
        materializer: SnapshotMaterializing,
        integrityChecker: SnapshotIntegrityChecking = DefaultSnapshotIntegrityChecker()
    ) {
        self.adapter = adapter
        self.materializer = materializer
        self.integrityChecker = integrityChecker
    }

    func ingest(request: IngestionPipelineRequest) async throws -> IngestionPipelineResult {
        var status = IngestionPipelineResult.StepStatus(
            adapterFetched: false,
            payloadValidated: false,
            materializerInvoked: false,
            contractValidated: false,
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
            compatibilityPassed: status.compatibilityPassed
        )

        guard contract.compatibility.isSchemaCompatible,
              contract.compatibility.isCompatibilityCheckPassed,
              contract.activationEligibility.state != .ineligible else {
            let reasons = contract.compatibility.compatibilityReasons + contract.activationEligibility.reasons
            throw IngestionPipelineError.compatibilityFailed(reasons)
        }

        status = IngestionPipelineResult.StepStatus(
            adapterFetched: status.adapterFetched,
            payloadValidated: status.payloadValidated,
            materializerInvoked: status.materializerInvoked,
            contractValidated: status.contractValidated,
            compatibilityPassed: true
        )

        return IngestionPipelineResult(
            status: .succeeded,
            contract: contract,
            materializationWarnings: materialization.warnings,
            stepStatus: status
        )
    }
}
