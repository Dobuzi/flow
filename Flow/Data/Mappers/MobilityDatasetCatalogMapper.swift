import Foundation

enum MobilityDatasetCatalogMapper {
    static func map(_ dto: MobilityDatasetCatalogDTO) -> MobilityDatasetCatalog {
        MobilityDatasetCatalog(
            version: dto.version,
            defaultSource: dto.defaultSource,
            datasets: dto.datasets.map(map)
        )
    }

    private static func map(_ dto: MobilityDatasetDescriptorDTO) -> MobilityDatasetDescriptor {
        MobilityDatasetDescriptor(
            id: dto.id,
            datasetID: dto.datasetID,
            source: dto.source,
            providerID: dto.providerID,
            displayName: dto.displayName,
            version: dto.version,
            schemaVersion: dto.schemaVersion,
            updatedAt: dto.updatedAt,
            availableModes: dto.availableModes,
            supportedSpatialLevels: dto.supportedSpatialLevels,
            supportedGranularities: dto.supportedGranularities,
            reliability: dto.reliability,
            spatialPrecision: dto.spatialPrecision,
            temporalPrecision: dto.temporalPrecision,
            qualityScore: dto.qualityScore
        )
    }
}
