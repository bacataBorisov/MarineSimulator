//
//  ConsoleView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 15.06.25.
//

import SwiftUI
import AppKit

struct ConsoleView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case nmea = "NMEA"
        case transport = "Transport"

        var id: String { rawValue }
    }

    @Bindable var nmeaManager: NMEASimulator
    let mode: Mode
    /// When false, skip live timers / generation observation (panel collapsed).
    var isActive: Bool = true

    var body: some View {
        let generation = isActive ? nmeaManager.consoleDisplayGeneration : 0

        ConsoleLogRepresentable(
            mode: mode,
            generation: generation,
            isActive: isActive,
            simulator: nmeaManager
        )
        .background {
            LinearGradient(
                colors: [
                    AppColors.consoleBackgroundStart,
                    AppColors.consoleBackgroundMid,
                    AppColors.consoleBackgroundEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// AppKit log view — SwiftUI `ForEach` + `scrollTo` on hundreds of rows is what froze long runs.
private struct ConsoleLogRepresentable: NSViewRepresentable {
    var mode: ConsoleView.Mode
    var generation: UInt64
    var isActive: Bool
    var simulator: NMEASimulator

    func makeNSView(context: Context) -> ConsoleLogHost {
        let host = ConsoleLogHost()
        if isActive {
            host.scheduleSync(mode: mode, generation: generation, simulator: simulator)
        }
        return host
    }

    func updateNSView(_ host: ConsoleLogHost, context: Context) {
        if isActive {
            host.scheduleSync(mode: mode, generation: generation, simulator: simulator)
        }
    }
}

final class ConsoleLogHost: NSView {
    private static let visibleLineCap = 200

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var lastMode: ConsoleView.Mode?
    private var lastSyncedGeneration: UInt64?
    private var lastRecordID: UUID?
    private var lastEventID: UUID?
    private var lineCount = 0
    private var syncQueued = false
    private var isSyncing = false
    private var pendingSyncRequest: (mode: ConsoleView.Mode, generation: UInt64, simulator: NMEASimulator)?
    private var lastLaidOutWidth: CGFloat = 0
    private var lastLaidOutHeight: CGFloat = 0
    /// Fresh / empty log follows the tail until the user scrolls away from the bottom.
    private var followTail = true
    private var isProgrammaticScroll = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 800,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        lastLaidOutWidth = 0
        lastLaidOutHeight = 0
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else {
            lastLaidOutWidth = 0
            lastLaidOutHeight = 0
            return
        }
        scrollView.layoutSubtreeIfNeeded()
        let contentWidth = scrollView.contentView.bounds.width
        let contentHeight = scrollView.contentView.bounds.height
        guard contentWidth > 1, contentHeight > 1 else {
            lastLaidOutWidth = 0
            lastLaidOutHeight = 0
            return
        }
        let widthChanged = abs(lastLaidOutWidth - contentWidth) > 0.5
        let heightChanged = abs(lastLaidOutHeight - contentHeight) > 0.5
        if widthChanged {
            lastLaidOutWidth = contentWidth
            var frame = textView.frame
            frame.size.width = contentWidth
            textView.frame = frame
            textView.textContainer?.containerSize = NSSize(
                width: contentWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        if heightChanged {
            lastLaidOutHeight = contentHeight
        }
        if let pending = pendingSyncRequest {
            pendingSyncRequest = nil
            scheduleSync(mode: pending.mode, generation: pending.generation, simulator: pending.simulator)
        }
        if (widthChanged || heightChanged), lineCount > 0 {
            if followTail {
                scrollToEnd()
            } else {
                updateTextViewHeight()
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    func scheduleSync(mode: ConsoleView.Mode, generation: UInt64, simulator: NMEASimulator) {
        guard bounds.width > 1, bounds.height > 1 else {
            pendingSyncRequest = (mode, generation, simulator)
            return
        }
        pendingSyncRequest = nil
        if lastMode == mode && lastSyncedGeneration == generation {
            let needsInitialSync = mode == .nmea
                ? (lastRecordID == nil && !simulator.outputMessageRecords.isEmpty)
                : (lastEventID == nil && !simulator.transportHistory.isEmpty)
            if !needsInitialSync {
                return
            }
        }
        lastSyncedGeneration = generation

        // Populate immediately on first render or mode switch so the console never flashes blank.
        let needsImmediateSync = lastMode != mode
            || (mode == .nmea && lastRecordID == nil && !simulator.outputMessageRecords.isEmpty)
            || (mode == .transport && lastEventID == nil && !simulator.transportHistory.isEmpty)
        if needsImmediateSync {
            sync(
                mode: mode,
                records: simulator.outputMessageRecords,
                events: simulator.transportHistory
            )
            return
        }

        #if DEBUG
        HangProbe.tick(.consoleSync)
        #endif
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.syncQueued = false
            #if DEBUG
            HangProbe.enter("console.sync")
            defer { HangProbe.leave("console.sync") }
            #endif
            self.sync(
                mode: mode,
                records: simulator.outputMessageRecords,
                events: simulator.transportHistory
            )
        }
    }

    func sync(mode: ConsoleView.Mode, records: [NMEASimulator.OutputMessageRecord], events: [TransportHistoryEvent]) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if lastMode != mode {
            reset()
            lastMode = mode
        }

        switch mode {
        case .nmea:
            syncRecords(records)
        case .transport:
            syncEvents(events)
        }
    }

    private func syncRecords(_ records: [NMEASimulator.OutputMessageRecord]) {
        if records.isEmpty {
            reset()
            return
        }
        let previousID = lastRecordID
        lastRecordID = records.last?.id
        if let previousID, let index = records.firstIndex(where: { $0.id == previousID }) {
            append(records: Array(records[(index + 1)...]), startingAt: lineCount)
        } else if previousID == nil || !records.contains(where: { $0.id == previousID }) {
            #if DEBUG
            HangProbe.note(.consoleReset, "records=\(records.count) prev=\(previousID?.uuidString ?? "nil")")
            #endif
            reset()
            lastRecordID = records.last?.id
            append(records: records, startingAt: 0)
        }
    }

    private func syncEvents(_ events: [TransportHistoryEvent]) {
        if events.isEmpty {
            reset()
            return
        }
        let previousID = lastEventID
        lastEventID = events.last?.id
        if let previousID, let index = events.firstIndex(where: { $0.id == previousID }) {
            append(events: Array(events[(index + 1)...]), startingAt: lineCount)
        } else if previousID == nil || !events.contains(where: { $0.id == previousID }) {
            reset()
            lastEventID = events.last?.id
            append(events: events, startingAt: 0)
        }
    }

    private func append(records: [NMEASimulator.OutputMessageRecord], startingAt: Int) {
        guard !records.isEmpty, let storage = textView.textStorage else { return }
        let pin = followTail || isPinnedToBottom
        let builder = NSMutableAttributedString()
        for (offset, record) in records.enumerated() {
            builder.append(Self.line(
                timestamp: record.timestamp,
                text: record.sentence.trimmingCharacters(in: .newlines),
                index: startingAt + offset
            ))
        }
        storage.append(builder)
        lineCount += records.count
        rebuildIfOverCap()
        if pin { scrollToEnd() }
    }

    private func append(events: [TransportHistoryEvent], startingAt: Int) {
        guard !events.isEmpty, let storage = textView.textStorage else { return }
        let pin = followTail || isPinnedToBottom
        let builder = NSMutableAttributedString()
        for (offset, event) in events.enumerated() {
            builder.append(Self.line(
                timestamp: event.timestamp,
                text: event.message,
                index: startingAt + offset
            ))
        }
        storage.append(builder)
        lineCount += events.count
        rebuildIfOverCap()
        if pin { scrollToEnd() }
    }

    private func reset() {
        textView.string = ""
        lastRecordID = nil
        lastEventID = nil
        lineCount = 0
        followTail = true
    }

    private func rebuildIfOverCap() {
        guard lineCount > Self.visibleLineCap, let storage = textView.textStorage else { return }
        let extra = lineCount - Self.visibleLineCap
        let string = storage.string as NSString
        var location = 0
        var removed = 0
        while removed < extra, location < string.length {
            let range = string.range(of: "\n", options: [], range: NSRange(location: location, length: string.length - location))
            guard range.location != NSNotFound else { break }
            location = range.location + 1
            removed += 1
        }
        guard location > 0 else { return }
        let kept = storage.attributedSubstring(from: NSRange(location: location, length: string.length - location))
        storage.setAttributedString(kept)
        lineCount -= removed
    }

    @objc
    private func clipViewBoundsDidChange() {
        guard !isProgrammaticScroll else { return }
        let clipBounds = scrollView.contentView.bounds
        guard clipBounds.width > 1, clipBounds.height > 1 else { return }
        followTail = isPinnedToBottom
    }

    private var isPinnedToBottom: Bool {
        let clip = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        if documentHeight <= clip.bounds.height + 1 {
            return true
        }
        return documentHeight - clip.bounds.maxY < 40
    }

    private func updateTextViewHeight() {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let inset = textView.textContainerInset.height * 2
        var frame = textView.frame
        frame.size.height = max(used.height + inset, scrollView.contentView.bounds.height)
        textView.frame = frame
    }

    private func scrollToEnd() {
        guard textView.layoutManager != nil, textView.textContainer != nil else {
            textView.scrollToEndOfDocument(nil)
            return
        }
        updateTextViewHeight()

        isProgrammaticScroll = true
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.scrollRangeToVisible(end)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        followTail = true
        DispatchQueue.main.async { [weak self] in
            self?.isProgrammaticScroll = false
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let primaryLineAttributes: [NSAttributedString.Key: Any] = makeLineAttributes(color: AppColors.consoleLinePrimary)
    private static let secondaryLineAttributes: [NSAttributedString.Key: Any] = makeLineAttributes(color: AppColors.consoleLineSecondary)

    private static func makeLineAttributes(color: Color) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(color),
            .paragraphStyle: paragraph
        ]
    }

    private static func line(timestamp: Date, text: String, index: Int) -> NSAttributedString {
        let time = timestampFormatter.string(from: timestamp)
        let attributes = index.isMultiple(of: 2) ? primaryLineAttributes : secondaryLineAttributes
        return NSAttributedString(string: "\(time)  \(text)\n", attributes: attributes)
    }
}
