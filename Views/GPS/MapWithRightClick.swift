import SwiftUI
import MapKit
import CoreLocation

@MainActor
final class GPSSelectorMapResource {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)

    private final class MapDelegate: NSObject, MKMapViewDelegate {
        var onSelectCoordinate: ((CLLocationCoordinate2D) -> Void)?
        var onCameraChanged: ((MKMapCamera) -> Void)?
        var isApplyingCamera = false

        @objc func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            guard gestureRecognizer.buttonMask == 2,
                  let mapView = gestureRecognizer.view as? MKMapView else {
                return
            }

            let location = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            onSelectCoordinate?(coordinate)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard !isApplyingCamera,
                  let snapshot = mapView.camera.copy() as? MKMapCamera else { return }
            onCameraChanged?(snapshot)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "SelectedLocation"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }
            return view
        }
    }

    final class SelectorMKMapView: MKMapView {
        override func scrollWheel(with event: NSEvent) {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                super.scrollWheel(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
        }
    }

    final class ContainerView: NSView {
        weak var resource: GPSSelectorMapResource?
        var initialCoordinate: CLLocationCoordinate2D?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 8
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleSync()
        }

        override func viewDidHide() {
            super.viewDidHide()
            resource?.detach(from: self)
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            scheduleSync()
        }

        override func setFrameSize(_ newSize: NSSize) {
            if newSize.width <= 1 || newSize.height <= 1 {
                layer?.masksToBounds = false
                resource?.detach(from: self)
            }
            super.setFrameSize(newSize)
            if newSize.width > 10, newSize.height > 10 {
                layer?.masksToBounds = true
                scheduleSync()
            }
        }

        override func layout() {
            super.layout()
            if bounds.width > 10, bounds.height > 10 {
                layer?.masksToBounds = true
                scheduleSync()
            }
        }

        private func scheduleSync() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resource?.syncAttachment(in: self, initialCoordinate: self.initialCoordinate)
            }
        }
    }

    private(set) var mapView: SelectorMKMapView?
    private var zoomControl: MKZoomControl?
    private let pin = MKPointAnnotation()
    private let delegateProxy = MapDelegate()
    private var hasAppliedInitialState = false
    private var hasCommittedInitialCamera = false
    private var pendingInitialCoordinate: CLLocationCoordinate2D?
    private var savedCamera: MKMapCamera?
    private var cameraSaveWorkItem: DispatchWorkItem?
    var onPersistCamera: ((MKMapCamera) -> Void)?
    private var isAdjustingHierarchy = false

    func restoreSavedCameraIfNeeded(from data: Data) {
        guard savedCamera == nil,
              let restored = GPSPersistedCamera.load(from: data) else { return }
        savedCamera = restored
    }

    func syncAttachment(in container: ContainerView, initialCoordinate: CLLocationCoordinate2D?) {
        if let initialCoordinate {
            pendingInitialCoordinate = initialCoordinate
        }
        guard !isAdjustingHierarchy else { return }
        guard container.window != nil,
              !container.isHiddenOrHasHiddenAncestor,
              hasNonZeroAncestorChain(for: container),
              container.bounds.width > 10,
              container.bounds.height > 10 else {
            detach(from: container)
            return
        }

        let map = ensureMapView(initialFrame: container.bounds)
        let movedContainers = map.superview !== container
        if movedContainers {
            isAdjustingHierarchy = true
            zoomControl?.removeFromSuperview()
            map.removeFromSuperview()
            map.frame = container.bounds
            map.autoresizingMask = [.width, .height]
            container.addSubview(map)
            attachZoomControl(in: container, map: map)
            isAdjustingHierarchy = false
        } else if map.frame != container.bounds {
            map.frame = container.bounds
        }

        if !hasAppliedInitialState {
            let initial = pendingInitialCoordinate ?? CLLocationCoordinate2D(latitude: 43.2141, longitude: 27.9147)
            pin.coordinate = initial
            pin.title = "Boat"
            pin.subtitle = String(format: "%.5f, %.5f", initial.latitude, initial.longitude)
            let region = MKCoordinateRegion(center: initial, span: Self.defaultSpan)
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, self.mapView === map, !self.hasAppliedInitialState,
                      !map.isHiddenOrHasHiddenAncestor, map.bounds.width > 10, map.bounds.height > 10 else { return }
                self.hasAppliedInitialState = true
                self.delegateProxy.isApplyingCamera = true
                if let savedCamera = self.savedCamera {
                    map.setCamera(savedCamera, animated: false)
                } else {
                    map.setRegion(region, animated: false)
                }
                self.delegateProxy.isApplyingCamera = false
                self.hasCommittedInitialCamera = true
                if !map.annotations.contains(where: { $0 === self.pin }) {
                    map.addAnnotation(self.pin)
                }
            }
        } else if movedContainers, hasCommittedInitialCamera, let savedCamera {
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, self.mapView === map, map.bounds.width > 10, map.bounds.height > 10 else { return }
                self.delegateProxy.isApplyingCamera = true
                map.setCamera(savedCamera, animated: false)
                self.delegateProxy.isApplyingCamera = false
            }
        }
    }

    private func attachZoomControl(in container: NSView, map: MKMapView) {
        let control = zoomControl ?? MKZoomControl(mapView: map)
        control.translatesAutoresizingMaskIntoConstraints = false
        zoomControl = control
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10)
        ])
    }

    private func hasNonZeroAncestorChain(for view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node.bounds.width <= 1 || node.bounds.height <= 1 {
                return false
            }
            if node is RetainedDestinationHosting {
                return true
            }
            current = node.superview
        }
        return true
    }

    func update(
        in container: ContainerView,
        coordinate: CLLocationCoordinate2D?,
        onSelectCoordinate: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        delegateProxy.onSelectCoordinate = onSelectCoordinate
        delegateProxy.onCameraChanged = { [weak self] camera in
            guard let self, self.hasCommittedInitialCamera else { return }
            self.savedCamera = camera
            self.scheduleCameraPersist(camera)
        }
        container.initialCoordinate = coordinate
        DispatchQueue.main.async { [weak self, weak container] in
            guard let self, let container else { return }
            self.syncAttachment(in: container, initialCoordinate: coordinate)
        }

        guard let coordinate else { return }
        if abs(pin.coordinate.latitude - coordinate.latitude) > 1e-6
            || abs(pin.coordinate.longitude - coordinate.longitude) > 1e-6 {
            pin.coordinate = coordinate
            pin.subtitle = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }
        if hasAppliedInitialState, let mapView, !mapView.annotations.contains(where: { $0 === pin }) {
            mapView.addAnnotation(pin)
        }
    }

    func detach(from container: NSView) {
        if let mapView, mapView.superview === container {
            if hasCommittedInitialCamera, let snapshot = mapView.camera.copy() as? MKMapCamera {
                savedCamera = snapshot
                cameraSaveWorkItem?.cancel()
                onPersistCamera?(snapshot)
            }
            zoomControl?.removeFromSuperview()
            mapView.removeFromSuperview()
        }
    }

    private func scheduleCameraPersist(_ camera: MKMapCamera) {
        cameraSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onPersistCamera?(camera)
        }
        cameraSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func ensureMapView(initialFrame: NSRect) -> SelectorMKMapView {
        if let mapView {
            return mapView
        }
        let created = SelectorMKMapView(frame: initialFrame)
        created.delegate = delegateProxy
        let rightClickRecognizer = NSClickGestureRecognizer(
            target: delegateProxy,
            action: #selector(MapDelegate.handleRightClick(_:))
        )
        rightClickRecognizer.buttonMask = 2
        created.addGestureRecognizer(rightClickRecognizer)
        mapView = created
        return created
    }
}

private struct GPSMapResourceKey: EnvironmentKey {
    static let defaultValue: GPSSelectorMapResource? = nil
}

extension EnvironmentValues {
    var gpsMapResource: GPSSelectorMapResource? {
        get { self[GPSMapResourceKey.self] }
        set { self[GPSMapResourceKey.self] = newValue }
    }
}

private struct GPSPersistedCamera: Codable {
    var latitude: Double
    var longitude: Double
    var distance: Double
    var pitch: Double
    var heading: Double

    static func load(from data: Data) -> MKMapCamera? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.latitude.isFinite,
              decoded.longitude.isFinite,
              decoded.distance.isFinite,
              decoded.distance > 1 else {
            return nil
        }
        return MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: decoded.latitude, longitude: decoded.longitude),
            fromDistance: decoded.distance,
            pitch: decoded.pitch,
            heading: decoded.heading
        )
    }

    static func encode(_ camera: MKMapCamera) -> Data? {
        guard camera.centerCoordinate.latitude.isFinite,
              camera.centerCoordinate.longitude.isFinite else {
            return nil
        }
        let distance = camera.centerCoordinateDistance > 1 ? camera.centerCoordinateDistance : max(camera.altitude, 1_000)
        return try? JSONEncoder().encode(Self(
            latitude: camera.centerCoordinate.latitude,
            longitude: camera.centerCoordinate.longitude,
            distance: distance,
            pitch: camera.pitch,
            heading: camera.heading
        ))
    }
}

struct MapWithRightClick: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(\.gpsMapResource) private var sharedResource
    @State private var fallbackResource = GPSSelectorMapResource()
    @AppStorage("gps.map_camera") private var savedCameraData: Data = Data()

    private var activeResource: GPSSelectorMapResource {
        sharedResource ?? fallbackResource
    }

    final class Coordinator {
        var parent: MapWithRightClick
        weak var resource: GPSSelectorMapResource?

        init(parent: MapWithRightClick, resource: GPSSelectorMapResource) {
            self.parent = parent
            self.resource = resource
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, resource: activeResource)
    }

    func makeNSView(context: Context) -> GPSSelectorMapResource.ContainerView {
        let container = GPSSelectorMapResource.ContainerView()
        let resource = activeResource
        resource.restoreSavedCameraIfNeeded(from: savedCameraData)
        resource.onPersistCamera = { camera in
            if let data = GPSPersistedCamera.encode(camera) {
                savedCameraData = data
            }
        }
        context.coordinator.resource = resource
        let coordinator = context.coordinator
        container.resource = resource
        container.initialCoordinate = coordinate
        resource.update(in: container, coordinate: coordinate) { selected in
            coordinator.parent.coordinate = selected
        }
        return container
    }

    func updateNSView(_ nsView: GPSSelectorMapResource.ContainerView, context: Context) {
        context.coordinator.parent = self
        let resource = activeResource
        resource.onPersistCamera = { camera in
            if let data = GPSPersistedCamera.encode(camera) {
                savedCameraData = data
            }
        }
        context.coordinator.resource = resource
        let coordinator = context.coordinator
        nsView.resource = resource
        resource.update(in: nsView, coordinate: coordinate) { selected in
            coordinator.parent.coordinate = selected
        }
    }

    static func dismantleNSView(_ nsView: GPSSelectorMapResource.ContainerView, coordinator: Coordinator) {
        coordinator.resource?.detach(from: nsView)
    }
}
