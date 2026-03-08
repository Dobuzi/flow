import Foundation

enum DatasetRefreshTrigger: String, Codable, Hashable {
    case manual
    case periodic
}

enum IngestionCompatibilityClassification: String, Codable, Hashable {
    case compatible
    case partiallyCompatible
    case incompatible
}
