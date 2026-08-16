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

    @Environment(NMEASimulator.self) private var nmeaManager
    let mode: Mode
    /// When false, skip live timers / generation observation (panel collapsed).
    var isActive: Bool = true

    var body: some View {
        let generation = isActive ? nmeaManager.consoleDisplayGeneration : 0

        ConsoleLogRepresentable(
            mode: mode,
            generation: generation,
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
    var simulator: NMEASimulator

    func makeNSView(context: Context) -> ConsoleLogHost {
        ConsoleLogHost()
    }

    func updateNSView(_ host: ConsoleLogHost, context: Context) {
        _ = generation
        host.scheduleSync(mode: mode, simulator: simulator)
    }
}

private final class ConsoleLogHost: NSView {
    private static let visibleLineCap = 200

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var lastMode: ConsoleView.Mode?
    private var lastRecordID: UUID?
    private var lastEventID: UUID?
    private var lineCount = 0
    private var syncQueued = false
    private var isSyncing = false

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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func scheduleSync(mode: ConsoleView.Mode, simulator: NMEASimulator) {
        #if DEBUG
        HangProbe.tick(.consoleSync)
        #endif
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncQueued = false
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
        let pin = isPinnedToBottom
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
        trimIfNeeded()
        if pin { scrollToEnd() }
    }

    private func append(events: [TransportHistoryEvent], startingAt: Int) {
        guard !events.isEmpty, let storage = textView.textStorage else { return }
        let pin = isPinnedToBottom
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
        trimIfNeeded()
        if pin { scrollToEnd() }
    }

    private func reset() {
        textView.string = ""
        lastRecordID = nil
        lastEventID = nil
        lineCount = 0
    }

    private func trimIfNeeded() {
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
        if location > 0 {
            storage.deleteCharacters(in: NSRange(location: 0, length: location))
            lineCount -= removed
        }
    }

    private var isPinnedToBottom: Bool {
        let visible = scrollView.contentView.bounds.maxY
        let document = scrollView.documentView?.bounds.maxY ?? visible
        return document - visible < 40
    }

    private func scrollToEnd() {
        textView.scrollToEndOfDocument(nil)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func line(timestamp: Date, text: String, index: Int) -> NSAttributedString {
        let time = timestampFormatter.string(from: timestamp)
        let color = NSColor(index.isMultiple(of: 2) ? AppColors.consoleLinePrimary : AppColors.consoleLineSecondary)
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: "\(time)  \(text)\n", attributes: attributes)
    }
}
