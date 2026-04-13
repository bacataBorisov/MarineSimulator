import SwiftUI
import MapKit
import AppKit

struct BoatMapView: NSViewRepresentable {
    @Environment(NMEASimulator.self) private var nmeaManager

    var topChromeInset: CGFloat = 0
    var trailingOverlayInset: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BoatMapContainerView {
        let container = BoatMapContainerView()
        container.mapView.delegate = context.coordinator
        context.coordinator.attach(to: container)
        context.coordinator.update(
            container: container,
            gpsData: nmeaManager.gpsData,
            bearingDegrees: nmeaManager.geographicBearingDegreesForMap,
            topChromeInset: topChromeInset,
            trailingOverlayInset: trailingOverlayInset
        )
        return container
    }

    func updateNSView(_ nsView: BoatMapContainerView, context: Context) {
        context.coordinator.update(
            container: nsView,
            gpsData: nmeaManager.gpsData,
            bearingDegrees: nmeaManager.geographicBearingDegreesForMap,
            topChromeInset: topChromeInset,
            trailingOverlayInset: trailingOverlayInset
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private weak var container: BoatMapContainerView?
        private var boatAnnotation = MKPointAnnotation()
        private let seamarkOverlay = MKTileOverlay(urlTemplate: "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png")
        private var headingLegOverlay: MKPolyline?
        private var hasPlacedInitialCamera = false
        private var lastBearingDegrees: Double = 0

        func attach(to container: BoatMapContainerView) {
            self.container = container
            container.recenterButton.target = self
            container.recenterButton.action = #selector(centerOnBoat)
            configureMap(container.mapView)
        }

        func update(
            container: BoatMapContainerView,
            gpsData: GPSData,
            bearingDegrees: Double,
            topChromeInset: CGFloat,
            trailingOverlayInset: CGFloat
        ) {
            let coordinate = CLLocationCoordinate2D(latitude: gpsData.latitude, longitude: gpsData.longitude)

            if !container.mapView.annotations.contains(where: { $0 === boatAnnotation }) {
                boatAnnotation.coordinate = coordinate
                container.mapView.addAnnotation(boatAnnotation)
            } else {
                boatAnnotation.coordinate = coordinate
            }

            lastBearingDegrees = bearingDegrees
            applyBoatRotation(on: container.mapView)
            syncHeadingLegOverlay(on: container.mapView, origin: coordinate, bearingDegrees: bearingDegrees)

            container.updateControlInsets(top: topChromeInset, trailing: trailingOverlayInset)

            if !hasPlacedInitialCamera {
                centerMap(on: coordinate, in: container.mapView, animated: false)
                hasPlacedInitialCamera = true
            }
        }

        private func configureMap(_ mapView: MKMapView) {
            mapView.mapType = .standard
            mapView.pointOfInterestFilter = .excludingAll
            mapView.showsScale = true
            mapView.showsCompass = false
            mapView.showsZoomControls = false
            mapView.showsPitchControl = false
            mapView.isZoomEnabled = true
            mapView.isRotateEnabled = true
            mapView.isPitchEnabled = true
            mapView.isScrollEnabled = true
            mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 200, maxCenterCoordinateDistance: 5_000_000)
            seamarkOverlay.canReplaceMapContent = false
            mapView.addOverlay(seamarkOverlay, level: .aboveLabels)
        }

        @objc
        private func centerOnBoat() {
            guard
                let container,
                boatAnnotation.coordinate.latitude.isFinite,
                boatAnnotation.coordinate.longitude.isFinite
            else {
                return
            }

            centerMap(on: boatAnnotation.coordinate, in: container.mapView, animated: true)
        }

        private func centerMap(on coordinate: CLLocationCoordinate2D, in mapView: MKMapView, animated: Bool) {
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: 120_000,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: animated)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation === boatAnnotation else {
                return nil
            }

            let identifier = "BoatAnnotation"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? BoatAnnotationView)
                ?? BoatAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.updateHeading(vesselDegrees: lastBearingDegrees, mapCameraHeadingDegrees: mapView.camera.heading)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = NSColor(srgbRed: 0.72, green: 0.52, blue: 0.06, alpha: 0.92)
                renderer.lineWidth = 3
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            applyBoatRotation(on: mapView)
            let coord = boatAnnotation.coordinate
            if coord.latitude.isFinite, coord.longitude.isFinite {
                syncHeadingLegOverlay(on: mapView, origin: coord, bearingDegrees: lastBearingDegrees)
            }
        }

        private func applyBoatRotation(on mapView: MKMapView) {
            guard let boatView = mapView.view(for: boatAnnotation) as? BoatAnnotationView else {
                return
            }
            boatView.updateHeading(vesselDegrees: lastBearingDegrees, mapCameraHeadingDegrees: mapView.camera.heading)
        }

        private func syncHeadingLegOverlay(on mapView: MKMapView, origin: CLLocationCoordinate2D, bearingDegrees: Double) {
            guard origin.latitude.isFinite, origin.longitude.isFinite else {
                return
            }

            if let old = headingLegOverlay {
                mapView.removeOverlay(old)
                headingLegOverlay = nil
            }

            let spanNM = approximateVisibleWidthNauticalMiles(mapView)
            let legNM = min(max(spanNM * 0.14, 0.4), 6.0)
            let tip = destinationCoordinate(from: origin, bearingDegrees: bearingDegrees, distanceNM: legNM)
            var coords = [origin, tip]
            let poly = MKPolyline(coordinates: &coords, count: 2)
            headingLegOverlay = poly
            mapView.addOverlay(poly, level: .aboveLabels)
        }

        private func approximateVisibleWidthNauticalMiles(_ mapView: MKMapView) -> Double {
            let rect = mapView.visibleMapRect
            let midY = rect.origin.y + rect.size.height * 0.5
            let west = MKMapPoint(x: rect.origin.x, y: midY)
            let east = MKMapPoint(x: rect.origin.x + rect.size.width, y: midY)
            let meters = west.distance(to: east)
            return max(meters / 1852.0, 0.15)
        }

    }
}

/// End point of a short great-circle segment (spherical Earth), bearing clockwise from true north, `distanceNM` in nautical miles.
private func destinationCoordinate(from origin: CLLocationCoordinate2D, bearingDegrees: Double, distanceNM: Double) -> CLLocationCoordinate2D {
    let distanceMeters = distanceNM * 1852.0
    let earthRadius = 6_371_000.0
    let bearingRad = toRadians(bearingDegrees)
    let lat1 = toRadians(origin.latitude)
    let lon1 = toRadians(origin.longitude)
    let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius)
        + cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearingRad))
    let lon2 = lon1 + atan2(
        sin(bearingRad) * sin(distanceMeters / earthRadius) * cos(lat1),
        cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2)
    )
    return CLLocationCoordinate2D(latitude: toDegrees(lat2), longitude: toDegrees(lon2))
}

final class BoatMapContainerView: NSView {
    let mapView = MKMapView()
    let compassButton = MKCompassButton(mapView: nil)
    let zoomControl = MKZoomControl(mapView: nil)
    let recenterButton = NSButton()
    private let controlStack = NSStackView()
    private let compassSlot = CenteredControlSlot()
    private let recenterSlot = CenteredControlSlot()
    private let zoomSlot = CenteredControlSlot()

    private var topConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func updateControlInsets(top: CGFloat, trailing: CGFloat) {
        topConstraint?.constant = 12 + top
        trailingConstraint?.constant = -(12 + trailing)
    }

    private func setup() {
        wantsLayer = true

        mapView.translatesAutoresizingMaskIntoConstraints = false
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        zoomControl.translatesAutoresizingMaskIntoConstraints = false
        recenterButton.translatesAutoresizingMaskIntoConstraints = false
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        compassSlot.translatesAutoresizingMaskIntoConstraints = false
        recenterSlot.translatesAutoresizingMaskIntoConstraints = false
        zoomSlot.translatesAutoresizingMaskIntoConstraints = false

        compassButton.mapView = mapView
        compassButton.compassVisibility = .visible
        zoomControl.mapView = mapView

        if let image = NSImage(systemSymbolName: "location.viewfinder", accessibilityDescription: "Center on Boat") {
            recenterButton.image = image
        }
        recenterButton.imagePosition = .imageOnly
        recenterButton.bezelStyle = .circular
        recenterButton.isBordered = true
        recenterButton.controlSize = .large
        recenterButton.toolTip = "Center on Boat"
        recenterButton.contentTintColor = .labelColor
        recenterButton.setButtonType(.momentaryPushIn)

        compassSlot.embed(compassButton)
        recenterSlot.embed(recenterButton)
        zoomSlot.embed(zoomControl)

        controlStack.orientation = .vertical
        controlStack.alignment = .centerX
        controlStack.spacing = 8
        controlStack.detachesHiddenViews = true
        controlStack.addArrangedSubview(compassSlot)
        controlStack.addArrangedSubview(recenterSlot)
        controlStack.addArrangedSubview(zoomSlot)

        addSubview(mapView)
        addSubview(controlStack)

        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),

            compassSlot.widthAnchor.constraint(equalToConstant: 38),
            recenterSlot.widthAnchor.constraint(equalToConstant: 38),
            zoomSlot.widthAnchor.constraint(equalToConstant: 38),
            recenterButton.widthAnchor.constraint(equalToConstant: 32),
            recenterButton.heightAnchor.constraint(equalToConstant: 32),
            compassButton.widthAnchor.constraint(equalToConstant: 32),
            compassButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        let topConstraint = controlStack.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        let trailingConstraint = controlStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        self.topConstraint = topConstraint
        self.trailingConstraint = trailingConstraint
        NSLayoutConstraint.activate([topConstraint, trailingConstraint])
    }
}

private final class CenteredControlSlot: NSView {
    func embed(_ view: NSView) {
        addSubview(view)

        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private final class BoatAnnotationView: MKAnnotationView {

    private let imageView = NSImageView()
    private var baseSymbolImage: NSImage?
    private var lastRenderedRadians: CGFloat?

    /// Canvas and layout size (points). MapKit scales this view on zoom; no layer transforms so the anchor stays on the coordinate.
    private let markerSize: CGFloat = 44
    private let symbolDrawSize: CGFloat = 40

    /// In top-left–origin drawing coords, shift the glyph up so the triangle centroid sits on the rotation center.
    private let symbolCentroidVerticalNudge: CGFloat = 5.5

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// `vesselDegrees`: clockwise from geographic north. `mapCameraHeadingDegrees`: `MKMapCamera.heading` when the map is rotated.
    func updateHeading(vesselDegrees: Double, mapCameraHeadingDegrees: CGFloat) {
        let screenDegrees = CGFloat(vesselDegrees) - mapCameraHeadingDegrees
        let radians = screenDegrees * (.pi / 180)
        if let last = lastRenderedRadians, abs(last - radians) < 0.0001 {
            return
        }
        lastRenderedRadians = radians
        imageView.image = renderHeadingImage(radians: radians)
    }

    private func setup() {
        frame = NSRect(x: 0, y: 0, width: markerSize, height: markerSize)
        canShowCallout = false
        centerOffset = .zero

        let darkYellow = NSColor(srgbRed: 0.72, green: 0.52, blue: 0.06, alpha: 1)
        let pointConfig = NSImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        if let raw = NSImage(systemSymbolName: "arrowtriangle.up.fill", accessibilityDescription: "Heading")?
            .withSymbolConfiguration(pointConfig) {
            let w = symbolDrawSize
            let h = symbolDrawSize
            let fromSize = raw.size.width > 1 && raw.size.height > 1 ? raw.size : NSSize(width: w, height: h)
            baseSymbolImage = NSImage(size: NSSize(width: w, height: h), flipped: true) { dst in
                darkYellow.set()
                NSBezierPath(rect: dst).fill()
                let template = (raw.copy() as! NSImage)
                template.isTemplate = true
                template.draw(
                    in: dst,
                    from: NSRect(origin: .zero, size: fromSize),
                    operation: .destinationIn,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                return true
            }
        }

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        imageView.layer?.shadowRadius = 1.5
        imageView.layer?.shadowOffset = CGSize(width: 0, height: 0.5)
        imageView.layer?.shadowOpacity = 1

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func renderHeadingImage(radians: CGFloat) -> NSImage? {
        guard let base = baseSymbolImage else {
            return nil
        }

        let dim = markerSize
        let sym = symbolDrawSize
        let nudge = symbolCentroidVerticalNudge

        return NSImage(size: NSSize(width: dim, height: dim), flipped: true) { _ in
            NSColor.clear.set()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: dim, height: dim)).fill()

            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: dim / 2, yBy: dim / 2)
            transform.rotate(byRadians: radians)
            transform.translateX(by: -dim / 2, yBy: -dim / 2)
            transform.concat()

            let originX = (dim - sym) / 2
            let originY = (dim - sym) / 2 - nudge
            let fromRect = NSRect(origin: .zero, size: base.size)
            let drawRect = NSRect(x: originX, y: originY, width: sym, height: sym)
            base.draw(
                in: drawRect,
                from: fromRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}

#Preview {
    BoatMapView()
        .frame(width: 900, height: 600)
}
