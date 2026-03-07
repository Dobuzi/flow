import Foundation

struct DatasetSchemaValidationResult: Hashable {
    let schemaVersion: String
    let supportedVersions: [String]
    let isCompatible: Bool
    let reason: String?
}

protocol DatasetSchemaValidating {
    func validate(dataset: FlowDataset) -> DatasetSchemaValidationResult
}

struct DatasetSchemaValidator: DatasetSchemaValidating {
    let supportedVersions: Set<String>

    init(supportedVersions: Set<String> = ["1.0.0"]) {
        self.supportedVersions = supportedVersions
    }

    func validate(dataset: FlowDataset) -> DatasetSchemaValidationResult {
        let isCompatible = supportedVersions.contains(dataset.schemaVersion)
        return DatasetSchemaValidationResult(
            schemaVersion: dataset.schemaVersion,
            supportedVersions: supportedVersions.sorted(),
            isCompatible: isCompatible,
            reason: isCompatible ? nil : "Unsupported schema version"
        )
    }

    func validateOrThrow(dataset: FlowDataset) throws {
        let result = validate(dataset: dataset)
        guard result.isCompatible else {
            throw DataSourceError.invalidSchemaVersion(result.schemaVersion)
        }
    }
}
