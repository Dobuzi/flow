import Foundation

struct RequiredFieldPolicy: Hashable {
    let requiredManifestFields: [String]

    static let schemaV1Default = RequiredFieldPolicy(
        requiredManifestFields: [
            "datasetID",
            "version",
            "source",
            "createdAt",
            "schemaVersion"
        ]
    )

    static let koreaNationalBaseline = RequiredFieldPolicy(
        requiredManifestFields: [
            "datasetID",
            "version",
            "source",
            "createdAt",
            "schemaVersion",
            "timeCoverage"
        ]
    )

    func missingFields(in dataset: FlowDataset) -> [String] {
        requiredManifestFields.filter { field in
            value(for: field, in: dataset).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func value(for field: String, in dataset: FlowDataset) -> String {
        switch field {
        case "datasetID": return dataset.datasetID
        case "version": return dataset.version
        case "source": return dataset.source
        case "createdAt": return dataset.createdAt
        case "schemaVersion": return dataset.schemaVersion
        case "timeCoverage": return dataset.timeCoverage
        default: return ""
        }
    }
}
