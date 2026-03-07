import Foundation

struct TimeBucket: Codable, Hashable {
    enum Granularity: String, Codable {
        case year
        case month
        case hourOfDay = "hour_of_day"
    }

    let id: String
    let year: Int
    let month: Int?
    let hour: Int?
    let granularity: Granularity
}
