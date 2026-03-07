import Foundation
import CoreLocation

struct LocationNode: Codable, Identifiable, Hashable {
    let id: String
    let nameKo: String
    let nameEn: String?
    let lat: Double
    let lon: Double
    let regionCode: String
    let regionType: String
    let importanceRank: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
