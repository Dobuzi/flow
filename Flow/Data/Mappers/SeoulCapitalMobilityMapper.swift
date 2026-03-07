import Foundation

enum SeoulCapitalMobilityMapper {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func map(manifest dto: SeoulCapitalDatasetManifestDTO, recordsCount: Int) -> FlowDataset {
        FlowDataset(
            datasetID: dto.datasetId,
            version: dto.version,
            source: dto.source,
            createdAt: dto.generatedAt,
            spatialLevel: .city,
            timeCoverage: "\(dto.coverageStart)~\(dto.coverageEnd)",
            recordsCount: recordsCount,
            schemaVersion: dto.schemaVersion
        )
    }

    static func map(zone dto: SeoulCapitalZoneDTO) -> LocationNode {
        LocationNode(
            id: dto.zoneId,
            nameKo: dto.zoneNameKo,
            nameEn: dto.zoneNameEn,
            lat: dto.latitude,
            lon: dto.longitude,
            regionCode: dto.sidoCode,
            regionType: dto.regionType,
            importanceRank: dto.importanceRank
        )
    }

    static func map(flow dto: SeoulCapitalFlowSnapshotDTO) -> FlowRecord? {
        guard let date = dateFormatter.date(from: dto.date) else {
            return nil
        }

        let components = calendar.dateComponents([.year, .month], from: date)
        guard
            let year = components.year,
            let month = components.month,
            (0...23).contains(dto.hour)
        else {
            return nil
        }

        let bucketID = String(format: "H:%04d-%02d|%02d", year, month, dto.hour)
        let mappedMode = mapMode(dto.transportMode)
        let metadata = FlowRecord.Metadata(
            corridorName: nil,
            regionType: nil,
            isPassengerFlow: true,
            isFreightFlow: false,
            confidenceScore: dto.confidenceScore,
            dataSourceTag: dto.dataSourceTag ?? "seoul_open_data_plaza"
        )

        let id = "\(dto.date)|\(String(format: "%02d", dto.hour))|\(dto.originZoneId)|\(dto.destinationZoneId)|\(mappedMode.rawValue)"
        return FlowRecord(
            id: id,
            originNodeID: dto.originZoneId,
            destinationNodeID: dto.destinationZoneId,
            transportMode: mappedMode,
            timeBucketID: bucketID,
            volume: dto.movementCount,
            unitType: .passengers,
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

        // Seoul capital mobility snapshot has no maritime-first taxonomy.
        // Bus/walking/vehicle/other fall back to road to keep filters compatible.
        return .road
    }
}
