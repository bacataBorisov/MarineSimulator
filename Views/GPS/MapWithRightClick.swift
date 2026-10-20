import SwiftUI
import MapKit
import CoreLocation

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?

    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithRightClick
        let pin = MKPointAnnotation()

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
        context.coordinator.pin.coordinate = initial
        context.coordinator.pin.title = "Boat"
        mapView.addAnnotation(context.coordinator.pin)

        let rightClickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRightClick(_:))
        )
        rightClickRecognizer.buttonMask = 2
        mapView.addGestureRecognizer(rightClickRecognizer)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        guard let coord = coordinate else { return }

        let pin = context.coordinator.pin
        pin.subtitle = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
        if abs(pin.coordinate.latitude - coord.latitude) > 1e-8
            || abs(pin.coordinate.longitude - coord.longitude) > 1e-8 {
            pin.coordinate = coord
        }
        if !nsView.annotations.contains(where: { $0 === pin }) {
            nsView.addAnnotation(pin)
        }
    }
}
