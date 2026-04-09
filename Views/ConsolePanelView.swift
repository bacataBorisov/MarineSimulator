import SwiftUI
import AppKit

@available(macOS 15.0, *)
struct ConsolePanelView: View {
    @Bindable var nmeaManager: NMEASimulator
    @Binding var consoleHeight: CGFloat

    let geometryHeight: CGFloat

    private let spacing: CGFloat = 8
    private let headerHeight: CGFloat = 28
    private let collapsedContentHeight: CGFloat = 0
    private let expandedMinimumHeight: CGFloat = 140
    @AppStorage("console_panel.mode") private var consoleModeRawValue: String = ConsoleView.Mode.nmea.rawValue
    @State private var lastExpandedHeight: CGFloat = 220

    private var consoleMode: Binding<ConsoleView.Mode> {
        Binding(
            get: { ConsoleView.Mode(rawValue: consoleModeRawValue) ?? .nmea },
            set: { consoleModeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 38, height: 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCollapsedState()
                    }
                    .help(consoleHeight <= collapsedContentHeight ? "Expand Console" : "Collapse Console")

                HStack(spacing: 10) {
                    Picker("Console Mode", selection: consoleMode) {
                        ForEach(ConsoleView.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Spacer(minLength: 0)

                    Button {
                        if consoleMode.wrappedValue == .nmea {
                            nmeaManager.clearOutputMessages()
                        } else {
                            nmeaManager.clearTransportHistory()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, spacing)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.consoleChrome,
                        AppColors.consoleBackgroundStart.opacity(0.96),
                        AppColors.consoleBackgroundMid.opacity(0.92)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.rowResize(directions: [.up, .down]).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let startingHeight = max(consoleHeight, collapsedContentHeight)
                        let newHeight = startingHeight - value.translation.height
                        let maxHeight = geometryHeight - UIConstants.tabBarHeight - headerHeight
                        consoleHeight = min(max(newHeight, collapsedContentHeight), maxHeight)

                        if consoleHeight > collapsedContentHeight {
                            lastExpandedHeight = max(consoleHeight, expandedMinimumHeight)
                        }
                    }
                    .onEnded { _ in
                        snapConsoleHeight()
                    }
            )

            ConsoleView(mode: consoleMode.wrappedValue)
                .frame(height: consoleHeight)
                .frame(maxWidth: .infinity)
                .clipped()
        }
        .onAppear {
            if consoleHeight > collapsedContentHeight {
                lastExpandedHeight = consoleHeight
            }
        }
    }

    private func toggleCollapsedState() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            if consoleHeight <= collapsedContentHeight {
                consoleHeight = max(lastExpandedHeight, expandedMinimumHeight)
            } else {
                lastExpandedHeight = max(consoleHeight, expandedMinimumHeight)
                consoleHeight = collapsedContentHeight
            }
        }
    }

    private func snapConsoleHeight() {
        let collapseThreshold: CGFloat = 72

        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            if consoleHeight < collapseThreshold {
                consoleHeight = collapsedContentHeight
            } else {
                consoleHeight = max(consoleHeight, expandedMinimumHeight)
                lastExpandedHeight = consoleHeight
            }
        }
    }
}
