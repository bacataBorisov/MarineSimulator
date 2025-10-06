import SwiftUI
import MapKit
import CoreLocation

struct GPSMapSelectorView: View {
    
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 12) {
            MapWithRightClick(coordinate: $selectedCoordinate)
                .frame(height: 300)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
        }
        .padding(UIConstants.spacing)
    }
}
