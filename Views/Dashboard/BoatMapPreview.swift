import SwiftUI
import MapKit

struct BoatMapView: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.195, longitude: 27.896),
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    )
    @State private var autoCenter = false

    var body: some View {
        ZStack {
            // MARK: - Main Map
            Map(position: $position, interactionModes: [.all]) {
                // Boat annotation
                Annotation("Boat", coordinate: CLLocationCoordinate2D(latitude: nmeaManager.gpsData.latitude.magnitude, longitude: nmeaManager.gpsData.longitude)) {
                    Image(systemName: "location.north.line.fill")
                        .resizable()
                        .frame(width: 20, height: 40)
                        .foregroundStyle(.yellow)
                        .rotationEffect(.degrees(nmeaManager.heading.value ?? 0))
                        .animation(.easeInOut(duration: 0.6), value: (nmeaManager.heading.value ?? 0))
                        .shadow(radius: 2)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapZoomStepper()
            }

            // MARK: - Demo Controls (Optional)
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    // Move West
                    Button {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            nmeaManager.gpsData.longitude -= 0.05
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Move West")

                    // Move East
                    Button {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            nmeaManager.gpsData.longitude += 0.05
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Move East")

                    // Center on Boat
                    Button {
                        withAnimation(.easeInOut) {
                            position = .camera(
                                .init(centerCoordinate: CLLocationCoordinate2D(
                                    latitude: nmeaManager.gpsData.latitude,
                                    longitude: nmeaManager.gpsData.longitude
                                ),
                                distance: 120_000,
                                heading: 0,
                                pitch: 0)
                            )
                        }
                    } label: {
                        Image(systemName: "scope")
                            .symbolRenderingMode(.multicolor)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Center on Boat")
                }
                .padding(.bottom, 16)
            }
        }
    }
}

#Preview {
    BoatMapView()
        .frame(width: 900, height: 600)
}
