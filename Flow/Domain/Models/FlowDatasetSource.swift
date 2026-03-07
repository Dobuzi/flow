import Foundation

enum FlowDatasetSource: String, CaseIterable, Codable, Hashable {
    case bundledSample = "bundled_sample"
    case seoulCapitalSnapshot = "seoul_capital_snapshot"
    case koreaNational = "korea_national"

    var title: String {
        switch self {
        case .bundledSample:
            return "Bundled Sample"
        case .seoulCapitalSnapshot:
            return "Seoul Capital Mobility"
        case .koreaNational:
            return "Korea National (Placeholder)"
        }
    }

    static func fromPersistedValue(_ value: String) -> FlowDatasetSource? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let exact = FlowDatasetSource(rawValue: normalized) {
            return exact
        }

        // Backward-compatible aliases for legacy persistence values.
        switch normalized {
        case "sample", "bundled", "bundledsample":
            return .bundledSample
        case "seoul", "seoulcapital", "seoul_capital":
            return .seoulCapitalSnapshot
        case "national", "korea", "koreanational":
            return .koreaNational
        default:
            return nil
        }
    }
}
