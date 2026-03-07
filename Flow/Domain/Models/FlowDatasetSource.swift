import Foundation

enum FlowDatasetSource: String, CaseIterable, Codable, Hashable {
    case bundledSample = "bundled_sample"
    case seoulCapitalSnapshot = "seoul_capital_snapshot"

    var title: String {
        switch self {
        case .bundledSample:
            return "Bundled Sample"
        case .seoulCapitalSnapshot:
            return "Seoul Capital Mobility"
        }
    }
}
