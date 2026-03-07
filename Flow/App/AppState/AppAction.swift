import Foundation
import MapKit

enum AppAction {
    case setYear(Int)
    case setMonth(Int)
    case setHour(Int)
    case toggleMode(TransportMode)
    case setModes(Set<TransportMode>)
    case setRegion(MKCoordinateRegion)
    case setSpatialLevel(SpatialLevel)
    case setPlayback(AppState.PlaybackState)
    case setAnimationPhase(Double)
    case setSelectedFlowID(String?)
}
