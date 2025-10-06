import SwiftUI
import MapKit

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithRightClick

        init(parent: MapWithRightClick) {
            self.parent = parent
        }

        @objc func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            guard gestureRecognizer.buttonMask.contains(.init(2)), // right-click
                  let mapView = gestureRecognizer.view as? MKMapView else { return }

            let location = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            parent.coordinate = coordinate
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        // Default to Varna
        let defaultLocation = CLLocationCoordinate2D(latitude: 43.2141, longitude: 27.9147)
        let region = MKCoordinateRegion(center: defaultLocation,
                                        span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        mapView.setRegion(region, animated: false)
        mapView.delegate = context.coordinator

        let rightClickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRightClick(_:))
        )
        rightClickRecognizer.buttonMask = 0x2 // right mouse button
        mapView.addGestureRecognizer(rightClickRecognizer)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.removeAnnotations(nsView.annotations)

        if let coord = coordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coord
            annotation.title = "Selected"
            nsView.addAnnotation(annotation)
        }
    }
}