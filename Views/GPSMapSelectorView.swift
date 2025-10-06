import SwiftUI
import MapKit

struct GPSMapSelectorView: View {
    @Binding var latitude: Double
    @Binding var longitude: Double
    
    @State private var region: MKCoordinateRegion
    @State private var selectedLocation: CLLocationCoordinate2D?

    init(latitude: Binding<Double>, longitude: Binding<Double>) {
        _latitude = latitude
        _longitude = longitude
        
        let center = CLLocationCoordinate2D(latitude: latitude.wrappedValue, longitude: longitude.wrappedValue)
        _region = State(initialValue: MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
        _selectedLocation = State(initialValue: center)
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: selectedLocation.map { [$0] } ?? []) { location in
            MapMarker(coordinate: location, tint: .blue)
        }
        .onTapGesture { location in
            let geo = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            latitude = geo.latitude
            longitude = geo.longitude
            selectedLocation = geo
        }
        .overlay(alignment: .top) {
            Text("Tap on the map to set starting coordinates")
                .font(.caption)
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.top, 8)
        }
    }
}