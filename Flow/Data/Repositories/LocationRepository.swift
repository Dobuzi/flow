import Foundation

protocol LocationRepository {
    func fetchLocationNodes() async throws -> [LocationNode]
}
