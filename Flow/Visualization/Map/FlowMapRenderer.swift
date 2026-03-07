import Foundation
import MapKit

final class FlowMapRenderer {
    func buildRenderableSegments(
        flows: [FlowRecord],
        nodes: [LocationNode]
    ) -> [RenderableFlowSegment] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let maxVolume = flows.map(\.volume).max() ?? 1.0

        let baseSegments: [RenderableFlowSegment] = flows.compactMap { flow in
            guard
                let originNode = nodesByID[flow.originNodeID],
                let destinationNode = nodesByID[flow.destinationNodeID]
            else {
                return nil
            }

            let normalized = maxVolume > 0 ? min(flow.volume / maxVolume, 1.0) : 0
            return RenderableFlowSegment(
                id: flow.id,
                origin: originNode.coordinate,
                destination: destinationNode.coordinate,
                mode: flow.transportMode,
                volume: flow.volume,
                normalizedIntensity: normalized,
                lineWidth: 1.0,
                opacity: 0.8
            )
        }

        return FlowScalePolicy.apply(to: baseSegments)
    }

    func syncOverlays(on mapView: MKMapView, segments: [RenderableFlowSegment]) {
        mapView.removeOverlays(mapView.overlays)
        let overlays = segments.map(makePolyline(for:))
        mapView.addOverlays(overlays)
    }

    func cappedSegments(for spatialLevel: SpatialLevel, segments: [RenderableFlowSegment]) -> [RenderableFlowSegment] {
        let cap: Int
        switch spatialLevel {
        case .national:
            cap = 1_200
        case .province:
            cap = 2_000
        case .city, .hub:
            cap = 3_000
        }

        if segments.count <= cap {
            return segments
        }
        return segments.sorted { $0.volume > $1.volume }.prefix(cap).map { $0 }
    }

    func makeOverlayRenderer(for overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor.systemBlue
        renderer.lineWidth = 2.0
        renderer.alpha = 0.8
        renderer.lineDashPattern = nil
        return renderer
    }

    func makePolyline(for segment: RenderableFlowSegment) -> MKPolyline {
        var coordinates = [segment.origin, segment.destination]
        return MKPolyline(coordinates: &coordinates, count: coordinates.count)
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
