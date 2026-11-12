import AppKit
import SwiftUI

#if DEBUG

extension Notification.Name {
    static let scrollTraceUpdated = Notification.Name("MarineSimulator.scrollTraceUpdated")
}

/// DEBUG-only record of the live clip view. Capture stays off until the inspector starts it.
final class ScrollRuntimeTrace: @unchecked Sendable {
    static let shared = ScrollRuntimeTrace()
    static let capacity = 800

    private let lock = NSLock()
    private var capturing = false
    private var sequence = 0
    private var lines: [String] = []
    private var active: [String: String] = [:]
    private var lastUINote: TimeInterval = 0
    private(set) var selection = "-"
    private(set) var consoleHeight: CGFloat = 0
    private(set) var dragging = false

    var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return capturing
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return lines.count
    }

    func start() {
        lock.lock()
        capturing = true
        lock.unlock()
        record(kind: "captureStarted", note: "buffer=\(Self.capacity)")
        publish(force: true)
    }

    func stop() {
        record(kind: "captureStopped", note: "")
        lock.lock()
        capturing = false
        lock.unlock()
        publish(force: true)
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        sequence = 0
        lock.unlock()
        publish(force: true)
    }

    func resetForTest() {
        lock.lock()
        capturing = false
        lines.removeAll()
        sequence = 0
        active.removeAll()
        selection = "-"
        consoleHeight = 0
        dragging = false
        lock.unlock()
    }

    func noteSelection(_ raw: String) {
        selection = raw
        record(kind: "selection", note: raw)
    }

    func noteMounted(_ raw: String) {
        record(kind: "mounted", frozenPage: raw, note: "page entered the detail column")
    }

    func noteRemoved(_ raw: String) {
        record(kind: "removed", frozenPage: raw, note: "page left the detail column")
    }

    func noteDrag(started: Bool, height: CGFloat) {
        dragging = started
        consoleHeight = height
        record(kind: started ? "dragStarted" : "dragEnded", note: "consoleHeight=\(Self.format(height))")
    }

    func noteConsoleHeight(_ height: CGFloat) {
        consoleHeight = height
        record(kind: "consoleHeight", note: "consoleHeight=\(Self.format(height))")
    }

    func bindAnchor(_ anchor: AnyObject, scrollView: NSScrollView?, clipView: NSView?, label: String) {
        let anchorID = Self.identity(anchor)
        let scrollID = Self.identity(scrollView)
        let clipID = Self.identity(clipView)
        lock.lock()
        active[anchorID] = "\(label) scroll=\(scrollID) clip=\(clipID)"
        lock.unlock()
    }

    func unbindAnchor(_ anchor: AnyObject) {
        let anchorID = Self.identity(anchor)
        lock.lock()
        active.removeValue(forKey: anchorID)
        lock.unlock()
    }

    func record(
        kind: String,
        selection overrideSelection: String? = nil,
        frozenPage: String = "-",
        slot: String = "-",
        anchor: AnyObject? = nil,
        scrollView: NSScrollView? = nil,
        clipView: NSView? = nil,
        documentHeight: CGFloat? = nil,
        viewportHeight: CGFloat? = nil,
        origin: CGFloat? = nil,
        stored: CGFloat? = nil,
        dragging overrideDragging: Bool? = nil,
        requested: CGFloat? = nil,
        observed: CGFloat? = nil,
        note: String = ""
    ) {
        lock.lock()
        guard capturing else {
            lock.unlock()
            return
        }
        sequence += 1
        let seq = sequence
        let selection = overrideSelection ?? self.selection
        let dragFlag = overrideDragging ?? dragging
        let console = consoleHeight
        if lines.count >= Self.capacity {
            lines.removeFirst(lines.count - Self.capacity + 1)
        }
        lock.unlock()

        let doc = documentHeight ?? 0
        let view = viewportHeight ?? 0
        let originY = origin ?? 0
        let maxOffset = max(0, doc - view)
        let gap = doc - view - originY
        let line = [
            "#\(seq)",
            "t=\(Self.format(ProcessInfo.processInfo.systemUptime))",
            "kind=\(kind)",
            "selection=\(selection)",
            "frozen=\(frozenPage)",
            "slot=\(slot)",
            "anchor=\(Self.identity(anchor))",
            "scroll=\(Self.identity(scrollView))",
            "clip=\(Self.identity(clipView))",
            "doc=\(Self.format(doc))",
            "view=\(Self.format(view))",
            "origin=\(Self.format(originY))",
            "max=\(Self.format(maxOffset))",
            "gap=\(Self.format(gap))",
            "stored=\(stored.map(Self.format) ?? "-")",
            "dragging=\(dragFlag)",
            "console=\(Self.format(console))",
            "requested=\(requested.map(Self.format) ?? "-")",
            "observed=\(observed.map(Self.format) ?? "-")",
            "note=\(note)"
        ].joined(separator: " ")

        lock.lock()
        lines.append(line)
        lock.unlock()
        publish(force: false)
    }

    func text() -> String {
        lock.lock()
        let body = lines.joined(separator: "\n")
        let anchors = active.values.sorted().joined(separator: "\n")
        lock.unlock()
        return Self.buildIdentity + "\nactive=\n\(anchors.isEmpty ? "-" : anchors)\n\n\(body)\n"
    }

    func activeSummary() -> String {
        lock.lock()
        let anchors = active.values.sorted().joined(separator: "\n")
        let page = selection
        lock.unlock()
        return "selection=\(page)\n\(anchors.isEmpty ? "no bound scroll view" : anchors)"
    }

    static func identity(_ object: AnyObject?) -> String {
        guard let object else { return "-" }
        return String(UInt(bitPattern: ObjectIdentifier(object)), radix: 16)
    }

    static var buildIdentity: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let path = bundle.executableURL?.path ?? "?"
        let modified: String
        if let url = bundle.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date {
            modified = ISO8601DateFormatter().string(from: date)
        } else {
            modified = "?"
        }
        let deployment = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "?"
        return """
        configuration=Debug
        version=\(version) (\(build))
        executable=\(path)
        executableModified=\(modified)
        pid=\(ProcessInfo.processInfo.processIdentifier)
        deploymentTarget=\(deployment)
        """
    }

    private func publish(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && now - lastUINote < 0.05 { return }
        lastUINote = now
        NotificationCenter.default.post(name: .scrollTraceUpdated, object: nil)
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }

    private static func format(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }
}

enum ScrollTraceWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: ScrollTracePanel())
        let window = NSWindow(contentViewController: host)
        window.title = "Scroll Trace"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 560))
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[MarineSim][scroll-trace] %@", ScrollRuntimeTrace.buildIdentity.replacingOccurrences(of: "\n", with: " | "))
    }
}

private struct ScrollTracePanel: View {
    @State private var bodyText = ""
    @State private var status = ""
    @State private var capturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ScrollRuntimeTrace.buildIdentity)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Text(status)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Start") {
                    ScrollRuntimeTrace.shared.start()
                    refresh()
                }
                .disabled(capturing)
                Button("Stop") {
                    ScrollRuntimeTrace.shared.stop()
                    refresh()
                }
                .disabled(!capturing)
                Button("Clear") {
                    ScrollRuntimeTrace.shared.clear()
                    refresh()
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ScrollRuntimeTrace.shared.text(), forType: .string)
                }
                Button("Refresh") { refresh() }
            }
            TextEditor(text: $bodyText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .scrollTraceUpdated)) { _ in
            refresh()
        }
    }

    private func refresh() {
        capturing = ScrollRuntimeTrace.shared.isCapturing
        status = (capturing ? "capturing" : "idle") + "\n" + ScrollRuntimeTrace.shared.activeSummary()
        bodyText = ScrollRuntimeTrace.shared.text()
    }
}

#endif
