import SwiftUI
import MapKit

struct MapContainerView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var segments: [RenderableFlowSegment]
    var selectedFlowID: String?
    var spatialLevel: SpatialLevel
    var animationPhase: Double
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelectFlow: (String?) -> Void
    var onMetric: (String, Double) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)
        context.coordinator.syncSegmentsIfNeeded(on: mapView, segments: segments, spatialLevel: spatialLevel)
        context.coordinator.updateAnimationPhase(animationPhase)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let current = mapView.region
        if abs(current.center.latitude - region.center.latitude) > 0.0001 ||
            abs(current.center.longitude - region.center.longitude) > 0.0001 ||
            abs(current.span.latitudeDelta - region.span.latitudeDelta) > 0.0001 ||
            abs(current.span.longitudeDelta - region.span.longitudeDelta) > 0.0001 {
            mapView.setRegion(region, animated: true)
        }

        context.coordinator.syncSegmentsIfNeeded(on: mapView, segments: segments, spatialLevel: spatialLevel)
        context.coordinator.updateSelectedFlowID(selectedFlowID)
        context.coordinator.updateAnimationPhase(animationPhase)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegionChange: onRegionChange, onSelectFlow: onSelectFlow, onMetric: onMetric)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onRegionChange: (MKCoordinateRegion) -> Void
        let onSelectFlow: (String?) -> Void
        let onMetric: (String, Double) -> Void
        private let mapRenderer = FlowMapRenderer()
        private var renderedSegmentIDs: [String] = []
        private var segmentsByID: [String: RenderableFlowSegment] = [:]
        private var overlaysByID: [String: MKPolyline] = [:]
        private var segmentsByOverlayID: [ObjectIdentifier: RenderableFlowSegment] = [:]
        private var renderersByID: [String: MKPolylineRenderer] = [:]
        private var currentSelectedFlowID: String?
        private var currentAnimationPhase: Double = 0

        init(
            onRegionChange: @escaping (MKCoordinateRegion) -> Void,
            onSelectFlow: @escaping (String?) -> Void,
            onMetric: @escaping (String, Double) -> Void
        ) {
            self.onRegionChange = onRegionChange
            self.onSelectFlow = onSelectFlow
            self.onMetric = onMetric
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async { [onRegionChange] in
                onRegionChange(mapView.region)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = mapRenderer.makeOverlayRenderer(for: overlay)
            if
                let polyline = overlay as? MKPolyline,
                let segment = segmentsByOverlayID[ObjectIdentifier(polyline)],
                let polylineRenderer = renderer as? MKPolylineRenderer
            {
                polylineRenderer.strokeColor = strokeColor(for: segment.mode)
                polylineRenderer.lineWidth = segment.lineWidth
                polylineRenderer.alpha = segment.opacity
                polylineRenderer.lineDashPattern = dashPattern(for: segment.mode)
                polylineRenderer.lineDashPhase = currentAnimationPhase
                renderersByID[segment.id] = polylineRenderer
            }
            return renderer
        }

        func syncSegmentsIfNeeded(on mapView: MKMapView, segments: [RenderableFlowSegment], spatialLevel: SpatialLevel) {
            let capped = mapRenderer.cappedSegments(for: spatialLevel, segments: segments)
            let ids = capped.map(\.id)
            guard ids != renderedSegmentIDs else {
                return
            }
            renderedSegmentIDs = ids
            segmentsByID = Dictionary(uniqueKeysWithValues: capped.map { ($0.id, $0) })
            applyOverlayDiff(on: mapView, segments: capped)
            if let selectedFlowID = currentSelectedFlowID, segmentsByID[selectedFlowID] == nil {
                currentSelectedFlowID = nil
                DispatchQueue.main.async { [onSelectFlow] in
                    onSelectFlow(nil)
                }
            }
        }

        func updateSelectedFlowID(_ selectedFlowID: String?) {
            currentSelectedFlowID = selectedFlowID
        }

        func updateAnimationPhase(_ phase: Double) {
            guard phase != currentAnimationPhase else { return }
            currentAnimationPhase = phase
            for renderer in renderersByID.values {
                renderer.lineDashPhase = phase
                renderer.setNeedsDisplay()
            }
        }

        @objc
        func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView else {
                return
            }

            let tapPoint = recognizer.location(in: mapView)
            var candidates: [(segment: RenderableFlowSegment, distance: Double)] = []

            for overlay in mapView.overlays {
                guard let flowPolyline = overlay as? MKPolyline else {
                    continue
                }
                guard let segment = segmentsByOverlayID[ObjectIdentifier(flowPolyline)] else {
                    continue
                }
                let distance = distanceToPolyline(flowPolyline, from: tapPoint, on: mapView)
                if distance <= 24.0 {
                    candidates.append((segment, distance))
                }
            }

            guard !candidates.isEmpty else {
                currentSelectedFlowID = nil
                onSelectFlow(nil)
                return
            }

            let selected = candidates.sorted { lhs, rhs in
                if lhs.segment.volume != rhs.segment.volume {
                    return lhs.segment.volume > rhs.segment.volume
                }
                if lhs.distance != rhs.distance {
                    return lhs.distance < rhs.distance
                }
                return lhs.segment.id < rhs.segment.id
            }.first?.segment.id

            currentSelectedFlowID = selected
            onSelectFlow(selected)
        }

        private func distanceToPolyline(_ polyline: MKPolyline, from point: CGPoint, on mapView: MKMapView) -> Double {
            let points = polyline.points()
            let count = polyline.pointCount
            guard count > 1 else {
                return Double.greatestFiniteMagnitude
            }

            var minDistance = Double.greatestFiniteMagnitude
            for idx in 0..<(count - 1) {
                let p1Coord = points[idx].coordinate
                let p2Coord = points[idx + 1].coordinate
                let p1 = mapView.convert(p1Coord, toPointTo: mapView)
                let p2 = mapView.convert(p2Coord, toPointTo: mapView)
                let distance = distanceFromPoint(point, toSegmentStart: p1, segmentEnd: p2)
                minDistance = min(minDistance, distance)
            }
            return minDistance
        }

        private func distanceFromPoint(_ p: CGPoint, toSegmentStart a: CGPoint, segmentEnd b: CGPoint) -> Double {
            let abx = b.x - a.x
            let aby = b.y - a.y
            let apx = p.x - a.x
            let apy = p.y - a.y
            let lengthSquared = abx * abx + aby * aby

            if lengthSquared == 0 {
                let dx = p.x - a.x
                let dy = p.y - a.y
                return sqrt(Double(dx * dx + dy * dy))
            }

            let t = max(0, min(1, (apx * abx + apy * aby) / lengthSquared))
            let closest = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
            let dx = p.x - closest.x
            let dy = p.y - closest.y
            return sqrt(Double(dx * dx + dy * dy))
        }

        private func applyOverlayDiff(on mapView: MKMapView, segments: [RenderableFlowSegment]) {
            let start = CFAbsoluteTimeGetCurrent()
            let newIDs = Set(segments.map(\.id))
            let oldIDs = Set(overlaysByID.keys)

            let removeIDs = oldIDs.subtracting(newIDs)
            if !removeIDs.isEmpty {
                let overlaysToRemove = removeIDs.compactMap { overlaysByID[$0] }
                mapView.removeOverlays(overlaysToRemove)
                removeIDs.forEach {
                    if let overlay = overlaysByID[$0] {
                        segmentsByOverlayID.removeValue(forKey: ObjectIdentifier(overlay))
                    }
                }
                removeIDs.forEach {
                    overlaysByID.removeValue(forKey: $0)
                    renderersByID.removeValue(forKey: $0)
                }
            }

            let addSegments = segments.filter { overlaysByID[$0.id] == nil }
            if !addSegments.isEmpty {
                let newOverlays = addSegments.map { segment in
                    (segment, mapRenderer.makePolyline(for: segment))
                }
                for (segment, overlay) in newOverlays {
                    overlaysByID[segment.id] = overlay
                    segmentsByOverlayID[ObjectIdentifier(overlay)] = segment
                }
                mapView.addOverlays(newOverlays.map(\.1))
            }

            // Replace overlays when style/geometry changed but ID stayed the same.
            let potentiallyChanged = segments.filter { overlaysByID[$0.id] != nil }
            for segment in potentiallyChanged {
                guard
                    let existing = overlaysByID[segment.id],
                    let existingSegment = segmentsByOverlayID[ObjectIdentifier(existing)],
                    existingSegment != segment
                else {
                    continue
                }
                mapView.removeOverlay(existing)
                segmentsByOverlayID.removeValue(forKey: ObjectIdentifier(existing))
                let updated = mapRenderer.makePolyline(for: segment)
                overlaysByID[segment.id] = updated
                segmentsByOverlayID[ObjectIdentifier(updated)] = segment
                mapView.addOverlay(updated)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            onMetric("overlay_diff_apply_ms", elapsed)
        }

        private func strokeColor(for mode: TransportMode) -> UIColor {
            switch mode {
            case .road:
                return UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)
            case .rail:
                return UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1.0)
            case .air:
                return UIColor(red: 0.031, green: 0.569, blue: 0.698, alpha: 1.0)
            case .maritime:
                return UIColor(red: 0.059, green: 0.463, blue: 0.431, alpha: 1.0)
            }
        }

        private func dashPattern(for mode: TransportMode) -> [NSNumber]? {
            switch mode {
            case .road:
                return nil
            case .rail:
                return [8, 4]
            case .air:
                return [2, 5]
            case .maritime:
                return [12, 6]
            }
        }
    }
}
