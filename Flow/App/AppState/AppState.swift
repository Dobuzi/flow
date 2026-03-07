import Foundation
import MapKit

struct AppState {
    var selectedYear: Int = 2025
    var selectedMonth: Int = 1
    var selectedHour: Int = 12
    var selectedDatasetSource: FlowDatasetSource = .bundledSample
    var selectedModes: Set<TransportMode> = Set(TransportMode.allCases)
    var mapRegion: MKCoordinateRegion = .southKoreaDefault
    var spatialLevel: SpatialLevel = .national
    var playbackState: PlaybackState = .stopped
    var animationPhase: Double = 0
    var selectedFlowID: String?

    enum PlaybackState: Hashable {
        case stopped
        case playing
        case paused
    }
}

extension MKCoordinateRegion {
    static let southKoreaDefault = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.5, longitude: 127.8),
        span: MKCoordinateSpan(latitudeDelta: 4.5, longitudeDelta: 4.5)
    )
}
