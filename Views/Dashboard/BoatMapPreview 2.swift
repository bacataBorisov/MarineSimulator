//
//  BoatMapPreview 2.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 6.10.25.
//


import SwiftUI
import MapKit

struct BoatMapPreview: View {
    @Bindable var nmeaManager: NMEASimulator

    // change key when coords change
    private var coordKey: String {
        "\(nmeaManager.gpsData.latitude),\(nmeaManager.gpsData.longitude)"
    }

    @State private var position: MapCameraPosition = .automatic
    @State private var didSetInitialCamera = false
    @State private var followBoat = true          // auto-recenter while true

    var body: some View {
        let coord = CLLocationCoordinate2D(
            latitude: nmeaManager.gpsData.latitude,
            longitude: nmeaManager.gpsData.longitude
        )

        GeometryReader { proxy in
            let safeWidth = max(proxy.size.width, 1)
            let safeHeight = max(proxy.size.height, 1)

            ZStack(alignment: .topLeading) {
                Map(position: $position)
                    .frame(width: safeWidth, height: safeHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .mapStyle(.standard(elevation: .realistic))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapPitchButton()
                        MapZoomStepper()
                    }
                    // if user pans/zooms, stop following
                    .onMapCameraChange { _ in
                        if didSetInitialCamera { followBoat = false }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            guard !didSetInitialCamera else { return }
                            position = .camera(.init(centerCoordinate: coord, distance: 200_000))
                            didSetInitialCamera = true
                        }
                    }
                    .onChange(of: coordKey) {
                        guard followBoat else { return }
                        position = .camera(.init(centerCoordinate: coord, distance: 200_000))
                    }

                // Overlay: coords + follow/recenter controls
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "Lat: %.5f  Lon: %.5f", coord.latitude, coord.longitude))
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Toggle("Follow boat", isOn: $followBoat)
                            .toggleStyle(.switch)
                            .font(.caption)

                        Button {
                            followBoat = true
                            position = .camera(.init(centerCoordinate: coord, distance: 200_000))
                        } label: {
                            Label("Recenter", systemImage: "location.north.line")
                                .labelStyle(.iconOnly)
                                .padding(6)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
    }
}