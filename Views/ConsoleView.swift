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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if mode == .nmea {
                        ForEach(nmeaManager.outputMessages.indices, id: \.self) { index in
                            consoleRow(
                                timestamp: nmeaManager.outputMessageTimestamp(at: index),
                                text: nmeaManager.outputMessages[index],
                                color: index.isMultiple(of: 2) ? AppColors.consoleLinePrimary : AppColors.consoleLineSecondary
                            )
                            .id(index)
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
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.consoleBackgroundStart,
                        AppColors.consoleBackgroundMid,
                        AppColors.consoleBackgroundEnd
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .onChange(of: scrollTargetID) {
                guard let scrollTargetID else { return }
                proxy.scrollTo(scrollTargetID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func consoleRow(timestamp: Date?, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timestamp.map { Self.consoleTimestampFormatter.string(from: $0) } ?? "--:--:--")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private static let consoleTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @ViewBuilder
    private func transportRow(event: TransportHistoryEvent, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(event.category.rawValue.capitalized, systemImage: event.level.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(event.level.color)

                Text(event.timestamp, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(event.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var scrollTargetID: AnyHashable? {
        switch mode {
        case .nmea:
            return nmeaManager.outputMessages.indices.last
        case .transport:
            return nmeaManager.transportHistory.last?.id
        }
    }
}

#Preview {
    ConsoleView(mode: .nmea)
        .environment(NMEASimulator())
}

private extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .connected:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "questionmark.circle"
        case .connected:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }
}
