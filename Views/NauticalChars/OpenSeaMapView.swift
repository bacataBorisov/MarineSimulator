//
//  OpenSeaMapView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 6.10.25.
//


import SwiftUI
import MapKit

struct OpenSeaMapView: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D
    @Binding var zoom: Double

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)

        // Disable Apple's base tiles
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll

        // Add OpenSeaMap overlay
        let seaOverlay = MKTileOverlay(urlTemplate: "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png")
        seaOverlay.canReplaceMapContent = false
        mapView.addOverlay(seaOverlay, level: .aboveLabels)

        // Set delegate to render overlay
        mapView.delegate = context.coordinator

        // Initial region
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: 100_000,
                                        longitudinalMeters: 100_000)
        mapView.setRegion(region, animated: false)
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        mapView.isScrollEnabled = true

        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: zoom,
                                        longitudinalMeters: zoom)
        mapView.setRegion(region, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
