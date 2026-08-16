import SwiftUI
import MapKit
import CoreLocation

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?

    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithRightClick
        var lastCenteredCoordinate: CLLocationCoordinate2D?
        var pendingCenterWorkItem: DispatchWorkItem?

        init(parent: MapWithRightClick) {
            self.parent = parent
        }

        @objc func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            guard gestureRecognizer.buttonMask == 2,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                return
            }

            let location = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            parent.coordinate = coordinate
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

        func scheduleCenter(on coordinate: CLLocationCoordinate2D, mapView: MKMapView, animated: Bool) {
            pendingCenterWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let region = MKCoordinateRegion(center: coordinate, span: MapWithRightClick.defaultSpan)
                mapView.setRegion(region, animated: animated)
                self.lastCenteredCoordinate = coordinate
            }
            pendingCenterWorkItem = work
            // Defer out of NSHostingView / SwiftUI layout to avoid reentrant layout warnings.
            DispatchQueue.main.async(execute: work)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        let initial = coordinate
            ?? CLLocationCoordinate2D(latitude: 43.2141, longitude: 27.9147)
        let region = MKCoordinateRegion(center: initial, span: Self.defaultSpan)
        mapView.setRegion(region, animated: false)
        context.coordinator.lastCenteredCoordinate = initial

        let rightClickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRightClick(_:))
        )
        rightClickRecognizer.buttonMask = 2
        mapView.addGestureRecognizer(rightClickRecognizer)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.removeAnnotations(nsView.annotations)

        guard let coord = coordinate else { return }

        let annotation = MKPointAnnotation()
        annotation.coordinate = coord
        annotation.title = "Boat"
        annotation.subtitle = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
        nsView.addAnnotation(annotation)

        let last = context.coordinator.lastCenteredCoordinate
        let movedFar = last.map {
            abs($0.latitude - coord.latitude) > 0.0005 || abs($0.longitude - coord.longitude) > 0.0005
        } ?? true

        if movedFar {
            context.coordinator.scheduleCenter(on: coord, mapView: nsView, animated: true)
        }
    }
}
