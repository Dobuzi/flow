import Foundation

struct LocalMobilityCatalogDataSource: MobilityCatalogDataSource {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadCatalog() throws -> MobilityDatasetCatalog {
        let data = try readFile(named: "dataset_catalog", extension: "json")
        let dto = try JSONDecoder().decode(MobilityDatasetCatalogDTO.self, from: data)
        return MobilityDatasetCatalogMapper.map(dto)
    }

    private func readFile(named name: String, extension ext: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/DatasetCatalog")
                ?? bundle.url(forResource: name, withExtension: ext) else {
            throw DataSourceError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
