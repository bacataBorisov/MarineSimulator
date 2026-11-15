import SwiftUI
import MapKit
import CoreLocation

struct GPSMapSelectorView: View {
    
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    var body: some View {
        MapWithRightClick(coordinate: $selectedCoordinate)
            .frame(height: 440)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.status, style: .continuous)
                    .stroke(DesignToken.Separator.standard.opacity(0.6))
            )
    }
}
