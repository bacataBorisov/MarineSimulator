//
//  ConsoleView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 15.06.25.
//

import SwiftUI

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
        let _ = isActive ? nmeaManager.consoleDisplayGeneration : 0

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if mode == .nmea {
                            ForEach(Array(nmeaManager.outputMessageRecords.enumerated()), id: \.element.id) { index, record in
                                consoleRow(
                                    timestamp: record.timestamp,
                                    text: record.sentence,
                                    color: index.isMultiple(of: 2) ? AppColors.consoleLinePrimary : AppColors.consoleLineSecondary
                                )
                                .id(record.id)
                            }
                        } else {
                            ForEach(Array(nmeaManager.transportHistory.enumerated()), id: \.element.id) { index, event in
                                transportRow(
                                    event: event,
                                    color: index.isMultiple(of: 2) ? AppColors.consoleLinePrimary : AppColors.consoleLineSecondary
                                )
                                .id(event.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
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
                .onChange(of: scrollTargetID) {
                    guard isActive, let scrollTargetID else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(scrollTargetID, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func consoleRow(timestamp: Date?, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timestamp.map { Self.consoleTimestampFormatter.string(from: $0) } ?? "--:--:--")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(text.trimmingCharacters(in: .newlines))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func transportRow(event: TransportHistoryEvent, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.consoleTimestampFormatter.string(from: event.timestamp))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Label(event.message, systemImage: event.level.systemImage)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var scrollTargetID: AnyHashable? {
        switch mode {
        case .nmea:
            return nmeaManager.outputMessageRecords.last?.id
        case .transport:
            return nmeaManager.transportHistory.last?.id
        }
    }

    private static let consoleTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
