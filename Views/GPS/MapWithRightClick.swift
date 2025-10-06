import SwiftUI
import MapKit
import CoreLocation

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithRightClick

        init(parent: MapWithRightClick) {
            self.parent = parent
        }

        @objc func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            print("Right-click detected")

            guard gestureRecognizer.buttonMask == 2,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                print("Failed right-click guard")
                return
            }

            let location = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            print("Selected coordinate: \(coordinate)")
            parent.coordinate = coordinate
        }

        // ✅ This must be here inside Coordinator
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
        rightClickRecognizer.buttonMask = 2
        mapView.addGestureRecognizer(rightClickRecognizer)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.removeAnnotations(nsView.annotations)

        if let coord = coordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coord
            annotation.title = "Starting Point"
            annotation.subtitle = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
            nsView.addAnnotation(annotation)
            
            nsView.selectAnnotation(annotation, animated: true)
        }    }
}
