import SwiftUI
import MapKit
import AppKit

/// Map overlay controls: match `MKCompassButton` / `MKZoomControl` footprint (circle diameter and slot width).
private enum MapFloatingChrome {
    static let controlDiameter: CGFloat = 38
    static let slotWidth: CGFloat = 38
}

private extension CLLocationCoordinate2D {
    func isEffectivelyEqual(to other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 1e-8 && abs(longitude - other.longitude) < 1e-8
    }
}

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
            tackInProgress: nmeaManager.isTackInProgress,
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
            tackInProgress: nmeaManager.isTackInProgress,
            topChromeInset: topChromeInset,
            trailingOverlayInset: trailingOverlayInset
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private weak var container: BoatMapContainerView?
        private var boatAnnotation = MKPointAnnotation()
        private let seamarkOverlay = MKTileOverlay(urlTemplate: "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png")
        private var hasPlacedInitialCamera = false
        private var lastBearingDegrees: Double = 0
        private var lastAppliedCameraHeading: CGFloat = .nan
        private var tackAnimationActive = false

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
            tackInProgress: Bool,
            topChromeInset: CGFloat,
            trailingOverlayInset: CGFloat
        ) {
            #if DEBUG
            HangProbe.tick(.mapUpdate)
            #endif
            let mapView = container.mapView
            guard mapView.bounds.width > 1, mapView.bounds.height > 1 else {
                #if DEBUG
                HangProbe.tick(.mapZero)
                #endif
                return
            }

            let coordinate = CLLocationCoordinate2D(latitude: gpsData.latitude, longitude: gpsData.longitude)

            if !mapView.annotations.contains(where: { $0 === boatAnnotation }) {
                boatAnnotation.coordinate = coordinate
                mapView.addAnnotation(boatAnnotation)
            } else if !boatAnnotation.coordinate.isEffectivelyEqual(to: coordinate) {
                boatAnnotation.coordinate = coordinate
            }

            let bearingChanged = abs(lastBearingDegrees - bearingDegrees) > 0.05
            tackAnimationActive = tackInProgress
            lastBearingDegrees = bearingDegrees
            if bearingChanged {
                applyBoatRotation(on: mapView)
            }

            container.updateControlInsets(top: topChromeInset, trailing: trailingOverlayInset)

            if !hasPlacedInitialCamera {
                hasPlacedInitialCamera = true
                centerMap(on: coordinate, in: mapView, animated: false)
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
            let previous = mapView.camera
            let distance = Self.resolvedCameraGroundDistance(previous)
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: distance,
                pitch: previous.pitch,
                heading: previous.heading
            )
            mapView.setCamera(camera, animated: animated)
        }

        /// Preserves zoom when recentering: use the current camera range instead of a fixed default.
        private static func resolvedCameraGroundDistance(_ camera: MKMapCamera) -> CLLocationDistance {
            let d = camera.centerCoordinateDistance
            if d > 1 { return d }
            let a = camera.altitude
            if a > 1 { return a }
            return 120_000
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation === boatAnnotation else {
                return nil
            }

            let identifier = "BoatAnnotation"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? BoatAnnotationView)
                ?? BoatAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.updateHeading(
                vesselDegrees: lastBearingDegrees,
                mapCameraHeadingDegrees: mapView.camera.heading,
                animated: false
            )
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            #if DEBUG
            HangProbe.tick(.mapRegion)
            #endif
            let heading = mapView.camera.heading
            guard !lastAppliedCameraHeading.isFinite || abs(lastAppliedCameraHeading - heading) > 0.05 else { return }
            lastAppliedCameraHeading = heading
            applyBoatRotation(on: mapView)
        }

        private func applyBoatRotation(on mapView: MKMapView) {
            guard let boatView = mapView.view(for: boatAnnotation) as? BoatAnnotationView else {
                return
            }
            boatView.updateHeading(
                vesselDegrees: lastBearingDegrees,
                mapCameraHeadingDegrees: mapView.camera.heading,
                animated: tackAnimationActive
            )
        }
    }
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

        let mapControlPointSize: CGFloat = 17
        let mapControlSymbolConfig = NSImage.SymbolConfiguration(pointSize: mapControlPointSize, weight: .semibold)
        if let base = NSImage(systemSymbolName: "location.viewfinder", accessibilityDescription: "Center on Boat") {
            recenterButton.image = base.withSymbolConfiguration(mapControlSymbolConfig)
        }
        recenterButton.imagePosition = .imageOnly
        recenterButton.imageScaling = .scaleProportionallyDown
        recenterButton.bezelStyle = .regularSquare
        recenterButton.isBordered = false
        recenterButton.toolTip = "Center on Boat"
        recenterButton.contentTintColor = .white
        recenterButton.setButtonType(.momentaryPushIn)
        recenterButton.focusRingType = .none
        recenterButton.wantsLayer = true
        if let layer = recenterButton.layer {
            layer.cornerRadius = MapFloatingChrome.controlDiameter / 2
            layer.masksToBounds = true
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        }

        compassSlot.embed(compassButton, fixedHeight: MapFloatingChrome.controlDiameter)
        recenterSlot.embed(recenterButton, fixedHeight: MapFloatingChrome.controlDiameter)
        zoomSlot.embed(zoomControl, fixedHeight: nil)

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

            compassSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth),
            compassSlot.heightAnchor.constraint(equalToConstant: MapFloatingChrome.controlDiameter),
            recenterSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth),
            recenterSlot.heightAnchor.constraint(equalToConstant: MapFloatingChrome.controlDiameter),
            zoomSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth)
        ])

        let topConstraint = controlStack.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        let trailingConstraint = controlStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        self.topConstraint = topConstraint
        self.trailingConstraint = trailingConstraint
        NSLayoutConstraint.activate([topConstraint, trailingConstraint])
    }
}

private final class CenteredControlSlot: NSView {
    /// When `fixedHeight` is set (compass / recenter), the slot does not stretch vertically—keeps circular controls round.
    func embed(_ view: NSView, fixedHeight: CGFloat?) {
        addSubview(view)

        var constraints: [NSLayoutConstraint] = [
            view.centerXAnchor.constraint(equalTo: centerXAnchor)
        ]
        if let h = fixedHeight {
            constraints.append(contentsOf: [
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: h),
                view.heightAnchor.constraint(equalToConstant: h)
            ])
        } else {
            constraints.append(contentsOf: [
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }
}

/// AppKit-only marker. Rotation is baked into a retina image around its center.
/// Do not assign `MKAnnotationView.image` — MapKit scales that and squashes the symbol.
private final class BoatAnnotationView: MKAnnotationView {
    private static let markerSize: CGFloat = 40
    private static let symbolFit: CGFloat = 28
    private static let baseSymbol: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: symbolFit, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(red: 0.72, green: 0.52, blue: 0.06, alpha: 1)]))
        return NSImage(systemSymbolName: "location.north.line.fill", accessibilityDescription: "Boat")?
            .withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: symbolFit, height: symbolFit))
    }()

    private let imageView = NSImageView()
    private var lastScreenDegrees: CGFloat = .nan

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// `vesselDegrees`: clockwise from geographic north. `mapCameraHeadingDegrees`: `MKMapCamera.heading` when the map is rotated.
    func updateHeading(vesselDegrees: Double, mapCameraHeadingDegrees: CGFloat, animated: Bool) {
        _ = animated
        guard vesselDegrees.isFinite, mapCameraHeadingDegrees.isFinite else { return }
        let screenDegrees = CGFloat(vesselDegrees) - mapCameraHeadingDegrees
        guard screenDegrees.isFinite else { return }
        if lastScreenDegrees.isFinite, abs(screenDegrees - lastScreenDegrees) < 0.05 { return }
        lastScreenDegrees = screenDegrees
        imageView.image = Self.makeImage(rotatedBy: screenDegrees)
    }

    private func setup() {
        let box = NSRect(x: 0, y: 0, width: Self.markerSize, height: Self.markerSize)
        frame = box
        bounds = box
        canShowCallout = false
        centerOffset = .zero
        collisionMode = .none
        displayPriority = .required

        imageView.imageScaling = .scaleNone
        imageView.frame = box
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        imageView.image = Self.makeImage(rotatedBy: 0)
    }

    private static func makeImage(rotatedBy degrees: CGFloat) -> NSImage {
        let points = markerSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int((points * scale).rounded()))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: points, height: points)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return NSImage(size: NSSize(width: points, height: points))
        }
        ctx.clear(CGRect(x: 0, y: 0, width: points, height: points))

        let intrinsic = baseSymbol.size
        let fit = min(symbolFit / max(intrinsic.width, 1), symbolFit / max(intrinsic.height, 1))
        let drawW = intrinsic.width * fit
        let drawH = intrinsic.height * fit

        ctx.translateBy(x: points / 2, y: points / 2)
        ctx.rotate(by: -degrees * .pi / 180)
        baseSymbol.draw(in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))

        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        return image
    }
}

#Preview {
    BoatMapView()
        .environment(NMEASimulator())
        .frame(minWidth: 480, minHeight: 360)
}
