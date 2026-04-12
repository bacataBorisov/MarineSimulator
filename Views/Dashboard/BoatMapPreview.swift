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
    private var gpsControlsDisabled: Bool { !nmeaManager.sensorToggles.hasGPS }

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: [.all]) {
                Annotation("Boat", coordinate: CLLocationCoordinate2D(latitude: nmeaManager.gpsData.latitude, longitude: nmeaManager.gpsData.longitude)) {
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

            VStack {
                mapToolbar

                Spacer()
            }
            .padding(.top, 20)
        }
    }

    private var mapToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Map Tools", systemImage: "map")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.88))

                if gpsControlsDisabled {
                    Text("GPS off")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppChrome.subtleFill, in: Capsule())
                }
            }

            HStack(spacing: 10) {
                MapActionButton(
                    systemImage: "arrow.left",
                    title: "Move West",
                    isDisabled: gpsControlsDisabled
                ) {
                    shiftLongitude(by: -0.05)
                }

                MapActionButton(
                    systemImage: "scope",
                    title: "Center on Boat",
                    isDisabled: gpsControlsDisabled
                ) {
                    centerOnBoat()
                }

                MapActionButton(
                    systemImage: "arrow.right",
                    title: "Move East",
                    isDisabled: gpsControlsDisabled
                ) {
                    shiftLongitude(by: 0.05)
                }
            }

            if gpsControlsDisabled {
                Text("Enable GPS in Configuration to reposition the boat.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private func shiftLongitude(by delta: Double) {
        withAnimation(.easeInOut(duration: 0.8)) {
            nmeaManager.gpsData.longitude += delta
            nmeaManager.persistLiveSettings()
        }
    }

    private func centerOnBoat() {
        withAnimation(.easeInOut) {
            position = .camera(
                .init(
                    centerCoordinate: CLLocationCoordinate2D(
                        latitude: nmeaManager.gpsData.latitude,
                        longitude: nmeaManager.gpsData.longitude
                    ),
                    distance: 120_000,
                    heading: 0,
                    pitch: 0
                )
            )
        }
    }
}

private struct MapActionButton: View {
    let systemImage: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    isDisabled ? AppChrome.subtleFill : AppChrome.raisedFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(isDisabled ? 0.06 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(title)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

#Preview {
    BoatMapView()
        .frame(width: 900, height: 600)
}
