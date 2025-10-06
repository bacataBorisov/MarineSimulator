import SwiftUI
import MapKit

struct BoatMapPreview: View {
    @Bindable var nmeaManager: NMEASimulator

    var coordinateKey: String {
        "\(nmeaManager.gpsData.latitude),\(nmeaManager.gpsData.longitude)"
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var debugText: String = ""

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: nmeaManager.gpsData.latitude,
                                                longitude: nmeaManager.gpsData.longitude)
        
        ZStack(alignment: .topLeading) {
            Map(position: $mapPosition) {
                Annotation("Boat", coordinate: coordinate) {
                    Image(systemName: "sailboat.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.blue)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(true)
            .onAppear {
                mapPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: 200000))
                debugText = formattedCoordinates(coordinate)
            }
            .onChange(of: coordinateKey) {
                mapPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: 200000))
                debugText = formattedCoordinates(coordinate)
            }

            Text(debugText)
                .font(.caption2)
                .padding(6)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding(8)
        }
    }

    private func formattedCoordinates(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "Lat: %.5f\nLon: %.5f", coord.latitude, coord.longitude)
    }
}

#Preview {
    BoatMapPreview(nmeaManager: NMEASimulator())
}
