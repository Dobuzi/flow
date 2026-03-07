import Foundation

enum NationalBaselineMobilityMapper {
    private static let timeSeriesEngine = TimeSeriesEngine()

    static func map(manifest dto: KoreaNationalDatasetManifestDTO, recordsCount: Int) -> FlowDataset {
        FlowDataset(
            datasetID: dto.datasetId,
            version: dto.version,
            source: dto.source,
            createdAt: dto.generatedAt,
            spatialLevel: dto.spatialLevel,
            timeCoverage: "\(dto.coverageStart)~\(dto.coverageEnd)",
            recordsCount: recordsCount,
            schemaVersion: dto.schemaVersion
        )
    }

    static func map(node dto: KoreaNationalNodeDTO) -> LocationNode {
        LocationNode(
            id: dto.nodeId,
            nameKo: dto.nameKo,
            nameEn: dto.nameEn,
            lat: dto.lat,
            lon: dto.lon,
            regionCode: dto.regionCode,
            regionType: dto.regionType,
            importanceRank: dto.importanceRank
        )
    }

    static func map(flow dto: KoreaNationalFlowSnapshotDTO) -> FlowRecord? {
        guard dto.volume >= 0 else {
            return nil
        }

        guard (try? timeSeriesEngine.parse(bucketID: dto.timeBucketId)) != nil else {
            return nil
        }

        let mode = mapMode(dto.transportMode)
        let metadata = dto.metadata.map { metadataDTO in
            FlowRecord.Metadata(
                corridorName: metadataDTO.corridorName,
                regionType: metadataDTO.regionType,
                isPassengerFlow: metadataDTO.isPassengerFlow,
                isFreightFlow: metadataDTO.isFreightFlow,
                confidenceScore: metadataDTO.confidenceScore,
                dataSourceTag: metadataDTO.dataSourceTag
            )
        }

        return FlowRecord(
            id: dto.id,
            originNodeID: dto.originNodeId,
            destinationNodeID: dto.destinationNodeId,
            transportMode: mode,
            timeBucketID: dto.timeBucketId,
            volume: dto.volume,
            unitType: dto.unitType,
            metadata: metadata
        )
    }

    static func mapMode(_ rawMode: String) -> TransportMode {
        let normalized = rawMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("air") || normalized.contains("항공") {
            return .air
        }

        if normalized.contains("rail")
            || normalized.contains("train")
            || normalized.contains("subway")
            || normalized.contains("철도")
            || normalized.contains("기차")
            || normalized.contains("지하철")
        {
            return .rail
        }

        if normalized.contains("ship")
            || normalized.contains("ferry")
            || normalized.contains("maritime")
            || normalized.contains("선박")
            || normalized.contains("해운")
            || normalized.contains("여객선")
        {
            return .maritime
        }

        return .road
    }
}
