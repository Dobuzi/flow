import Foundation
import MapKit

enum LODPolicy {
    static func spatialLevel(for region: MKCoordinateRegion) -> SpatialLevel {
        let delta = region.span.latitudeDelta
        if delta >= 2.5 { return .national }
        if delta >= 0.8 { return .province }
        if delta >= 0.15 { return .city }
        return .hub
    }
}
