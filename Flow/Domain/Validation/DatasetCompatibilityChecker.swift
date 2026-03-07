import Foundation

struct DatasetCompatibilityResult: Hashable {
    let source: FlowDatasetSource
    let isCompatible: Bool
    let reasons: [String]
    let checkedFields: [String]
    let missingFields: [String]
}

protocol DatasetCompatibilityChecking {
    func evaluate(dataset: FlowDataset, source: FlowDatasetSource) -> DatasetCompatibilityResult
}

struct DatasetCompatibilityChecker: DatasetCompatibilityChecking {
    private let schemaValidator: DatasetSchemaValidating
    private let requiredFieldPolicy: RequiredFieldPolicy

    init(
        schemaValidator: DatasetSchemaValidating = DatasetSchemaValidator(),
        requiredFieldPolicy: RequiredFieldPolicy = .schemaV1Default
    ) {
        self.schemaValidator = schemaValidator
        self.requiredFieldPolicy = requiredFieldPolicy
    }

    func evaluate(dataset: FlowDataset, source: FlowDatasetSource) -> DatasetCompatibilityResult {
        let checkedFields = requiredFieldPolicy.requiredManifestFields
        let missingFields = requiredFieldPolicy.missingFields(in: dataset)

        var reasons: [String] = []
        let schemaValidation = schemaValidator.validate(dataset: dataset)
        if !schemaValidation.isCompatible {
            reasons.append("schema_version_unsupported")
        }
        if !missingFields.isEmpty {
            reasons.append("required_fields_missing")
        }

        return DatasetCompatibilityResult(
            source: source,
            isCompatible: reasons.isEmpty,
            reasons: reasons,
            checkedFields: checkedFields,
            missingFields: missingFields
        )
    }
}
