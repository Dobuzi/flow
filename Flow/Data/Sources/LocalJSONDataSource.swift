import Foundation

enum DataSourceError: Error {
    case missingResource(String)
    case invalidSchemaVersion(String)
}

struct LocalJSONDataSource: FlowDataSource {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadDatasetManifest() throws -> FlowDataset {
        let data = try readFile(named: "dataset_manifest", extension: "json")
        let manifest = try JSONDecoder().decode(FlowDataset.self, from: data)
        try Self.validateSchemaVersion(manifest)
        return manifest
    }

    func loadNodes() throws -> [LocationNode] {
        let data = try readFile(named: "nodes", extension: "json")
        return try JSONDecoder().decode([LocationNode].self, from: data)
    }

    static func validateSchemaVersion(_ dataset: FlowDataset) throws {
        guard dataset.schemaVersion == "1.0.0" else {
            throw DataSourceError.invalidSchemaVersion(dataset.schemaVersion)
        }
    }

    func loadFlows() throws -> [FlowRecord] {
        let data = try readFile(named: "flows", extension: "jsonl")
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let lineData = Data(line.utf8)
                return try decoder.decode(FlowRecord.self, from: lineData)
            }
    }

    private func readFile(named name: String, extension ext: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/SampleData")
                ?? bundle.url(forResource: name, withExtension: ext) else {
            throw DataSourceError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
