import Foundation
import CoreLocation

struct RenderableFlowSegment: Identifiable, Hashable {
    let id: String
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let mode: TransportMode
    let volume: Double
    let normalizedIntensity: Double
    let lineWidth: Double
    let opacity: Double

    static func == (lhs: RenderableFlowSegment, rhs: RenderableFlowSegment) -> Bool {
        lhs.id == rhs.id &&
        lhs.origin.latitude == rhs.origin.latitude &&
        lhs.origin.longitude == rhs.origin.longitude &&
        lhs.destination.latitude == rhs.destination.latitude &&
        lhs.destination.longitude == rhs.destination.longitude &&
        lhs.mode == rhs.mode &&
        lhs.volume == rhs.volume &&
        lhs.normalizedIntensity == rhs.normalizedIntensity &&
        lhs.lineWidth == rhs.lineWidth &&
        lhs.opacity == rhs.opacity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(origin.latitude)
        hasher.combine(origin.longitude)
        hasher.combine(destination.latitude)
        hasher.combine(destination.longitude)
        hasher.combine(mode)
        hasher.combine(volume)
        hasher.combine(normalizedIntensity)
        hasher.combine(lineWidth)
        hasher.combine(opacity)
    }
}
