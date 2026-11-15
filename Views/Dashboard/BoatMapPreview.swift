import SwiftUI
import MapKit
import AppKit

/// Map overlay controls: match `MKCompassButton` / `MKZoomControl` footprint (circle diameter and slot width).
private enum MapFloatingChrome {
    static let controlDiameter: CGFloat = 34
    static let slotWidth: CGFloat = 38
}

private extension CLLocationCoordinate2D {
    func isEffectivelyEqual(to other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 1e-8 && abs(longitude - other.longitude) < 1e-8
    }

    func isVisuallyEqual(to other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 1e-5 && abs(longitude - other.longitude) < 1e-5
    }
}

private struct PersistedMapCamera: Codable {
    var latitude: Double
    var longitude: Double
    var distance: Double
    var pitch: Double
    var heading: Double

    init(_ camera: MKMapCamera) {
        latitude = camera.centerCoordinate.latitude
        longitude = camera.centerCoordinate.longitude
        distance = camera.centerCoordinateDistance > 1 ? camera.centerCoordinateDistance : max(camera.altitude, 1_000)
        pitch = camera.pitch
        heading = camera.heading
    }

    var mkCamera: MKMapCamera {
        MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            fromDistance: distance,
            pitch: pitch,
            heading: heading
        )
    }

    static func load(from data: Data) -> MKMapCamera? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.latitude.isFinite,
              decoded.longitude.isFinite,
              decoded.distance.isFinite,
              decoded.distance > 1 else {
            return nil
        }
        return decoded.mkCamera
    }

    static func encode(_ camera: MKMapCamera) -> Data? {
        guard camera.centerCoordinate.latitude.isFinite,
              camera.centerCoordinate.longitude.isFinite else {
            return nil
        }
        return try? JSONEncoder().encode(Self(camera))
    }
}

struct BoatMapView: NSViewRepresentable {
    @Environment(NMEASimulator.self) private var nmeaManager
    @AppStorage("dashboard.map_camera") private var savedCameraData: Data = Data()

    var isActive: Bool = true
    var topChromeInset: CGFloat = 0
    var trailingOverlayInset: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BoatMapContainerView {
        let container = BoatMapContainerView()
        container.mapView.delegate = context.coordinator
        context.coordinator.initialSavedCameraData = savedCameraData
        context.coordinator.onSaveCamera = { [weak container] camera in
            guard container != nil, let data = PersistedMapCamera.encode(camera) else { return }
            savedCameraData = data
        }
        context.coordinator.attach(to: container)
        return container
    }

    func updateNSView(_ nsView: BoatMapContainerView, context: Context) {
        nsView.syncMapAttachment()
        let becameActive = isActive && !context.coordinator.wasActive
        context.coordinator.wasActive = isActive
        if becameActive {
            context.coordinator.resetApplyThrottle()
        }
        guard isActive || !context.coordinator.hasPlacedInitialCamera else { return }
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
        private(set) var hasPlacedInitialCamera = false
        var wasActive = false
        var initialSavedCameraData: Data = Data()
        var onSaveCamera: ((MKMapCamera) -> Void)?
        private var cameraSaveWorkItem: DispatchWorkItem?
        private var lastBearingDegrees: Double = 0
        private var lastAppliedCameraHeading: CGFloat = .nan
        private var lastMapApplyTime: CFAbsoluteTime = 0
        private var tackAnimationActive = false
        private var isApplyingMap = false
        private var applyScheduled = false
        private var pendingGPS: GPSData?
        private var pendingBearing: Double = 0
        private var pendingTack = false

        func resetApplyThrottle() {
            lastMapApplyTime = 0
        }

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
            HangProbe.enter("map.update")
            defer { HangProbe.leave("map.update") }
            #endif
            container.updateControlInsets(top: topChromeInset, trailing: trailingOverlayInset)
            guard container.mapView.bounds.width > 1, container.mapView.bounds.height > 1 else {
                #if DEBUG
                HangProbe.tick(.mapZero)
                #endif
                return
            }
            pendingGPS = gpsData
            pendingBearing = bearingDegrees
            pendingTack = tackInProgress
            guard !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingMapApply()
            }
        }

        private func flushPendingMapApply() {
            applyScheduled = false
            guard let container, let gpsData = pendingGPS else { return }
            let mapView = container.mapView
            guard mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }
            guard !isApplyingMap else { return }

            let now = CFAbsoluteTimeGetCurrent()
            if hasPlacedInitialCamera, !pendingTack, now - lastMapApplyTime < 0.25 {
                return
            }
            lastMapApplyTime = now

            #if DEBUG
            HangProbe.enter("map.apply")
            defer { HangProbe.leave("map.apply") }
            #endif
            isApplyingMap = true
            defer { isApplyingMap = false }

            let coordinate = CLLocationCoordinate2D(latitude: gpsData.latitude, longitude: gpsData.longitude)
            if mapView.annotations.contains(where: { $0 === boatAnnotation }) {
                if !boatAnnotation.coordinate.isVisuallyEqual(to: coordinate) {
                    boatAnnotation.coordinate = coordinate
                }
            } else {
                boatAnnotation.coordinate = coordinate
                mapView.addAnnotation(boatAnnotation)
            }

            let bearingChanged = abs(lastBearingDegrees - pendingBearing) > (pendingTack ? 0.5 : 2)
            tackAnimationActive = pendingTack
            lastBearingDegrees = pendingBearing
            if bearingChanged {
                applyBoatRotation(on: mapView)
            }

            if !hasPlacedInitialCamera {
                hasPlacedInitialCamera = true
                let restored = PersistedMapCamera.load(from: initialSavedCameraData)
                let camera = restored ?? MKMapCamera(
                    lookingAtCenter: coordinate,
                    fromDistance: 120_000,
                    pitch: 0,
                    heading: 0
                )
                isApplyingMap = true
                mapView.setCamera(camera, animated: false)
                isApplyingMap = false
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
            HangProbe.enter("map.region")
            defer { HangProbe.leave("map.region") }
            #endif
            guard !isApplyingMap else { return }
            if hasPlacedInitialCamera {
                scheduleCameraPersist(mapView.camera)
            }
            let heading = mapView.camera.heading
            guard !lastAppliedCameraHeading.isFinite || abs(lastAppliedCameraHeading - heading) > 0.05 else { return }
            lastAppliedCameraHeading = heading
            applyBoatRotation(on: mapView)
        }

        private func scheduleCameraPersist(_ camera: MKMapCamera) {
            guard let snapshot = camera.copy() as? MKMapCamera else { return }
            cameraSaveWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onSaveCamera?(snapshot)
            }
            cameraSaveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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
    private let recenterGlassView = NSGlassEffectView()
    private let controlStack = NSStackView()
    private let compassSlot = CenteredControlSlot()
    private let recenterSlot = CenteredControlSlot()
    private let zoomSlot = CenteredControlSlot()

    private var topConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var hierarchyConstraints: [NSLayoutConstraint] = []
    private var isAdjustingHierarchy = false

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
        recenterGlassView.translatesAutoresizingMaskIntoConstraints = false
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        compassSlot.translatesAutoresizingMaskIntoConstraints = false
        recenterSlot.translatesAutoresizingMaskIntoConstraints = false
        zoomSlot.translatesAutoresizingMaskIntoConstraints = false

        compassButton.mapView = mapView
        compassButton.compassVisibility = .visible
        zoomControl.mapView = mapView

        let mapControlPointSize: CGFloat = 15
        let mapControlSymbolConfig = NSImage.SymbolConfiguration(pointSize: mapControlPointSize, weight: .medium)
        if let base = NSImage(systemSymbolName: "location", accessibilityDescription: "Center on Boat") {
            recenterButton.image = base.withSymbolConfiguration(mapControlSymbolConfig)
        }
        recenterButton.imagePosition = .imageOnly
        recenterButton.imageScaling = .scaleProportionallyDown
        recenterButton.bezelStyle = .regularSquare
        recenterButton.isBordered = false
        recenterButton.toolTip = "Center on Boat"
        recenterButton.contentTintColor = .labelColor
        recenterButton.setButtonType(.momentaryPushIn)
        recenterButton.focusRingType = .none

        recenterGlassView.style = .regular
        recenterGlassView.cornerRadius = MapFloatingChrome.controlDiameter / 2
        recenterGlassView.contentView = recenterButton

        compassSlot.embed(compassButton, fixedHeight: MapFloatingChrome.controlDiameter)
        recenterSlot.embed(recenterGlassView, fixedHeight: MapFloatingChrome.controlDiameter)
        zoomSlot.embed(zoomControl, fixedHeight: nil)

        controlStack.orientation = .vertical
        controlStack.alignment = .centerX
        controlStack.spacing = 8
        controlStack.detachesHiddenViews = true
        controlStack.addArrangedSubview(compassSlot)
        controlStack.addArrangedSubview(recenterSlot)
        controlStack.addArrangedSubview(zoomSlot)

        // MapKit stays out of the window until the container is large enough.
        // A retained 0×0 MKMapView rejects its drawable and invalidates safe area
        // on every constraint pass, which loops when the console height changes.
        let topConstraint = controlStack.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        let trailingConstraint = controlStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        self.topConstraint = topConstraint
        self.trailingConstraint = trailingConstraint
        hierarchyConstraints = [
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            compassSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth),
            compassSlot.heightAnchor.constraint(equalToConstant: MapFloatingChrome.controlDiameter),
            recenterSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth),
            recenterSlot.heightAnchor.constraint(equalToConstant: MapFloatingChrome.controlDiameter),
            zoomSlot.widthAnchor.constraint(equalToConstant: MapFloatingChrome.slotWidth),
            topConstraint,
            trailingConstraint,
        ]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncMapAttachment()
    }

    override func setFrameSize(_ newSize: NSSize) {
        if !isAdjustingHierarchy, newSize.width <= 1 || newSize.height <= 1 {
            detachMapFromWindow()
        }
        super.setFrameSize(newSize)
        if !isAdjustingHierarchy {
            syncMapAttachment()
        }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        if !isAdjustingHierarchy, newSize.width <= 1 || newSize.height <= 1 {
            detachMapFromWindow()
        }
        super.setBoundsSize(newSize)
    }

    override func layout() {
        if !isAdjustingHierarchy {
            syncMapAttachment()
        }
        super.layout()
    }

    /// Inserts the same `MKMapView` only while this container can give it a real size.
    func syncMapAttachment() {
        if bounds.width > 1, bounds.height > 1 {
            attachMapIfNeeded()
        } else {
            detachMapFromWindow()
        }
    }

    private func attachMapIfNeeded() {
        guard mapView.superview !== self, !isAdjustingHierarchy else { return }
        isAdjustingHierarchy = true
        defer { isAdjustingHierarchy = false }
        addSubview(mapView)
        addSubview(controlStack)
        NSLayoutConstraint.activate(hierarchyConstraints)
        invalidateIntrinsicContentSize()
    }

    private func detachMapFromWindow() {
        guard mapView.superview === self, !isAdjustingHierarchy else { return }
        isAdjustingHierarchy = true
        defer { isAdjustingHierarchy = false }
        NSLayoutConstraint.deactivate(hierarchyConstraints)
        controlStack.removeFromSuperview()
        mapView.removeFromSuperview()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard mapView.superview === self else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return super.intrinsicContentSize
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
        imageView.image = Self.cachedImage(rotatedBy: screenDegrees)
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
        imageView.image = Self.cachedImage(rotatedBy: 0)
    }

    private static var imageCache: [Int: NSImage] = [:]

    private static func cachedImage(rotatedBy degrees: CGFloat) -> NSImage {
        let key = Int((degrees / 2).rounded()) * 2
        if let cached = imageCache[key] { return cached }
        #if DEBUG
        HangProbe.enter("map.image")
        defer { HangProbe.leave("map.image") }
        #endif
        let image = makeImage(rotatedBy: CGFloat(key))
        imageCache[key] = image
        return image
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
