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
    private let nationalRequiredFieldPolicy: RequiredFieldPolicy
    private let nationalSupportedSchemaVersions: Set<String>

    init(
        schemaValidator: DatasetSchemaValidating = DatasetSchemaValidator(),
        requiredFieldPolicy: RequiredFieldPolicy = .schemaV1Default,
        nationalRequiredFieldPolicy: RequiredFieldPolicy = .koreaNationalBaseline,
        nationalSupportedSchemaVersions: Set<String> = ["1.0.0"]
    ) {
        self.schemaValidator = schemaValidator
        self.requiredFieldPolicy = requiredFieldPolicy
        self.nationalRequiredFieldPolicy = nationalRequiredFieldPolicy
        self.nationalSupportedSchemaVersions = nationalSupportedSchemaVersions
    }

    func evaluate(dataset: FlowDataset, source: FlowDatasetSource) -> DatasetCompatibilityResult {
        let policy = requiredFieldPolicy(for: source)
        let checkedFields = policy.requiredManifestFields
        let missingFields = policy.missingFields(in: dataset)

        var reasons: [String] = []
        let schemaValidation = schemaValidator.validate(dataset: dataset)
        if !schemaValidation.isCompatible {
            reasons.append("schema_version_unsupported")
        }
        if source == .koreaNational && !nationalSupportedSchemaVersions.contains(dataset.schemaVersion) {
            reasons.append("national_schema_version_unsupported")
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

    private func requiredFieldPolicy(for source: FlowDatasetSource) -> RequiredFieldPolicy {
        if source == .koreaNational {
            return nationalRequiredFieldPolicy
        }
        return requiredFieldPolicy
    }
}
