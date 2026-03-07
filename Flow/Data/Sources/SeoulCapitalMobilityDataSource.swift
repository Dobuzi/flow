import Foundation

struct SeoulCapitalMobilityDataSource: FlowDataSource {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadDatasetManifest() throws -> FlowDataset {
        let manifestData = try readFile(named: "seoul_capital_manifest", extension: "json")
        let manifestDTO = try JSONDecoder().decode(SeoulCapitalDatasetManifestDTO.self, from: manifestData)
        let flows = try loadFlows()
        let mapped = SeoulCapitalMobilityMapper.map(manifest: manifestDTO, recordsCount: flows.count)
        try LocalJSONDataSource.validateSchemaVersion(mapped)
        return mapped
    }

    func loadNodes() throws -> [LocationNode] {
        let data = try readFile(named: "seoul_capital_nodes", extension: "json")
        let dto = try JSONDecoder().decode([SeoulCapitalZoneDTO].self, from: data)
        return dto.map(SeoulCapitalMobilityMapper.map(zone:))
    }

    func loadFlows() throws -> [FlowRecord] {
        let data = try readFile(named: "seoul_capital_flows", extension: "jsonl")
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { line in
                let dto = try decoder.decode(SeoulCapitalFlowSnapshotDTO.self, from: Data(line.utf8))
                return SeoulCapitalMobilityMapper.map(flow: dto)
            }
    }

    private func readFile(named name: String, extension ext: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/SeoulCapitalData")
                ?? bundle.url(forResource: name, withExtension: ext) else {
            throw DataSourceError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
