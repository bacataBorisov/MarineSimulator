import SwiftUI
import MapKit
import CoreLocation

@MainActor
final class GPSSelectorMapResource {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)

    private final class MapDelegate: NSObject, MKMapViewDelegate {
        var onSelectCoordinate: ((CLLocationCoordinate2D) -> Void)?

        @objc func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            guard gestureRecognizer.buttonMask == 2,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                return
            }

            let location = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            onSelectCoordinate?(coordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "SelectedLocation"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }
            return view
        }
    }

    private(set) var mapView: MKMapView?
    private let pin = MKPointAnnotation()
    private let delegateProxy = MapDelegate()
    private var hasAppliedInitialState = false

    func attach(
        to container: NSView,
        initialCoordinate: CLLocationCoordinate2D?,
        onSelectCoordinate: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        delegateProxy.onSelectCoordinate = onSelectCoordinate

        let map: MKMapView
        if let existing = mapView {
            map = existing
        } else {
            let created = MKMapView()
            created.delegate = delegateProxy
            let rightClickRecognizer = NSClickGestureRecognizer(
                target: delegateProxy,
                action: #selector(MapDelegate.handleRightClick(_:))
            )
            rightClickRecognizer.buttonMask = 2
            created.addGestureRecognizer(rightClickRecognizer)
            mapView = created
            map = created

            let initial = initialCoordinate ?? CLLocationCoordinate2D(latitude: 43.2141, longitude: 27.9147)
            pin.coordinate = initial
            pin.title = "Boat"
            pin.subtitle = String(format: "%.5f, %.5f", initial.latitude, initial.longitude)
            let region = MKCoordinateRegion(center: initial, span: Self.defaultSpan)
            DispatchQueue.main.async { [weak self, weak created] in
                guard let self, let created, self.mapView === created, !self.hasAppliedInitialState else { return }
                self.hasAppliedInitialState = true
                created.setRegion(region, animated: false)
                if !created.annotations.contains(where: { $0 === self.pin }) {
                    created.addAnnotation(self.pin)
                }
            }
        }

        if map.superview !== container {
            map.removeFromSuperview()
            map.frame = container.bounds
            map.autoresizingMask = [.width, .height]
            container.addSubview(map)
        }
    }

    func update(
        coordinate: CLLocationCoordinate2D?,
        onSelectCoordinate: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        delegateProxy.onSelectCoordinate = onSelectCoordinate
        guard let coordinate else { return }

        pin.subtitle = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        if abs(pin.coordinate.latitude - coordinate.latitude) > 1e-8
            || abs(pin.coordinate.longitude - coordinate.longitude) > 1e-8 {
            pin.coordinate = coordinate
        }
        if hasAppliedInitialState, let mapView, !mapView.annotations.contains(where: { $0 === pin }) {
            mapView.addAnnotation(pin)
        }
    }

    func detach(from container: NSView) {
        delegateProxy.onSelectCoordinate = nil
        if let mapView, mapView.superview === container {
            mapView.removeFromSuperview()
        }
    }
}

private struct GPSMapResourceKey: EnvironmentKey {
    static let defaultValue: GPSSelectorMapResource? = nil
}

extension EnvironmentValues {
    var gpsMapResource: GPSSelectorMapResource? {
        get { self[GPSMapResourceKey.self] }
        set { self[GPSMapResourceKey.self] = newValue }
    }
}

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(\.gpsMapResource) private var sharedResource
    @State private var fallbackResource = GPSSelectorMapResource()

    private var activeResource: GPSSelectorMapResource {
        sharedResource ?? fallbackResource
    }

    final class Coordinator {
        var parent: MapWithRightClick
        weak var resource: GPSSelectorMapResource?

        init(parent: MapWithRightClick, resource: GPSSelectorMapResource) {
            self.parent = parent
            self.resource = resource
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, resource: activeResource)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let resource = activeResource
        context.coordinator.resource = resource
        let coordinator = context.coordinator
        resource.attach(to: container, initialCoordinate: coordinate) { selected in
            coordinator.parent.coordinate = selected
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        let resource = activeResource
        context.coordinator.resource = resource
        let coordinator = context.coordinator
        resource.attach(to: nsView, initialCoordinate: coordinate) { selected in
            coordinator.parent.coordinate = selected
        }
        resource.update(coordinate: coordinate) { selected in
            coordinator.parent.coordinate = selected
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.resource?.detach(from: nsView)
    }
}
