import SwiftUI
import MapKit

struct BoatMapPreview: View {
    @Bindable var nmeaManager: NMEASimulator

    // Changing string forces onChange when lat/lon update
    private var coordinateKey: String {
        "\(nmeaManager.gpsData.latitude),\(nmeaManager.gpsData.longitude)"
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var debugText: String = ""
    @State private var didSetInitialCamera = false

    var body: some View {
        // Current coordinate
        let coordinate = CLLocationCoordinate2D(
            latitude: nmeaManager.gpsData.latitude,
            longitude: nmeaManager.gpsData.longitude
        )

        GeometryReader { proxy in
            // Ensure non-zero size during layout
            let safeWidth = max(proxy.size.width, 1)
            let safeHeight = max(proxy.size.height, 1)

            ZStack(alignment: .topLeading) {
                Map(position: $mapPosition) {
                    Annotation("Boat", coordinate: coordinate) {
                        Image(systemName: "sailboat.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.tint)
                    }
                }
                .frame(width: safeWidth, height: safeHeight)               // prevent 0x0
                .clipShape(Rectangle())
                .allowsHitTesting(false)                                   // instead of .disabled(true)
                .onAppear {
                    // Defer camera set to after first layout pass
                    DispatchQueue.main.async {
                        if !didSetInitialCamera {
                            mapPosition = .camera(.init(centerCoordinate: coordinate, distance: 200_000))
                            debugText = formatted(coordinate)
                            didSetInitialCamera = true
                        }
                    }
                }
                .onChange(of: coordinateKey) {
                    // Update camera when boat moves
                    mapPosition = .camera(.init(centerCoordinate: coordinate, distance: 200_000))
                    debugText = formatted(coordinate)
                }
            }
        }
    }

    private func formatted(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "Lat: %.5f\nLon: %.5f", coord.latitude, coord.longitude)
    }
}
