import Foundation

enum NationalBaselineDataSourceError: Error {
    case incompatibleManifest([String])
    case invalidFlowSnapshotLine(Int)
}

protocol NationalBaselineMobilityDataSource: FlowDataSource {}

struct SafeNationalBaselineMobilityDataSource: NationalBaselineMobilityDataSource {
    private let wrapped: NationalBaselineMobilityDataSource

    init(wrapped: NationalBaselineMobilityDataSource = NationalBaselineSnapshotDataSource()) {
        self.wrapped = wrapped
    }

    func loadDatasetManifest() throws -> FlowDataset {
        do {
            return try wrapped.loadDatasetManifest()
        } catch {
            throw NationalBaselineRepositoryError.map(error)
        }
    }

    func loadNodes() throws -> [LocationNode] {
        do {
            return try wrapped.loadNodes()
        } catch {
            throw NationalBaselineRepositoryError.map(error)
        }
    }

    func loadFlows() throws -> [FlowRecord] {
        do {
            return try wrapped.loadFlows()
        } catch {
            throw NationalBaselineRepositoryError.map(error)
        }
    }
}

struct NationalBaselineSnapshotDataSource: NationalBaselineMobilityDataSource {
    let bundle: Bundle
    private let schemaValidator: DatasetSchemaValidator
    private let compatibilityChecker: DatasetCompatibilityChecker

    init(
        bundle: Bundle = .main,
        schemaValidator: DatasetSchemaValidator = DatasetSchemaValidator(),
        compatibilityChecker: DatasetCompatibilityChecker = DatasetCompatibilityChecker()
    ) {
        self.bundle = bundle
        self.schemaValidator = schemaValidator
        self.compatibilityChecker = compatibilityChecker
    }

    func loadDatasetManifest() throws -> FlowDataset {
        let data = try readFile(named: "korea_national_manifest", extension: "json")
        let dto = try JSONDecoder().decode(KoreaNationalDatasetManifestDTO.self, from: data)
        let flows = try loadFlows()
        let dataset = NationalBaselineMobilityMapper.map(manifest: dto, recordsCount: flows.count)

        try schemaValidator.validateOrThrow(dataset: dataset)
        let compatibility = compatibilityChecker.evaluate(dataset: dataset, source: .koreaNational)
        guard compatibility.isCompatible else {
            throw NationalBaselineDataSourceError.incompatibleManifest(compatibility.reasons)
        }
        return dataset
    }

    func loadNodes() throws -> [LocationNode] {
        let data = try readFile(named: "korea_national_nodes", extension: "json")
        let dto = try JSONDecoder().decode([KoreaNationalNodeDTO].self, from: data)
        return dto.map(NationalBaselineMobilityMapper.map(node:))
    }

    func loadFlows() throws -> [FlowRecord] {
        let data = try readFile(named: "korea_national_flows", extension: "jsonl")
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()

        return try text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, line in
                let dto = try decoder.decode(KoreaNationalFlowSnapshotDTO.self, from: Data(line.utf8))
                guard let mapped = NationalBaselineMobilityMapper.map(flow: dto) else {
                    throw NationalBaselineDataSourceError.invalidFlowSnapshotLine(index + 1)
                }
                return mapped
            }
    }

    private func readFile(named name: String, extension ext: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/KoreaNationalData")
                ?? bundle.url(forResource: name, withExtension: ext) else {
            throw DataSourceError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
