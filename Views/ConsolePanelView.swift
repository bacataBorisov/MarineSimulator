import SwiftUI
import AppKit

struct ConsolePanelView: View {
    @Binding var showConsole: Bool
    @Binding var consoleHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if showConsole {
                // Drag handle
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(height: 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newHeight = consoleHeight - value.translation.height
                                consoleHeight = min(max(newHeight, minHeight), maxHeight)
                            }
                    )
                    .onHover { _ in
                        NSCursor.resizeUpDown.set()
                    }

                // Console output
                ConsoleView()
                    .frame(height: consoleHeight)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .border(Color.gray.opacity(0.3), width: 1)
            }

            // Toggle button bar
            HStack {
                Button {
                    showConsole.toggle()
                } label: {
                    Label("", systemImage: "menubar.rectangle")
                        .rotationEffect(.degrees(180))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(height: 24) // Adjust as needed
            }
        }
        .animation(.easeInOut(duration: 0.3), value: consoleHeight)
        .transition(.move(edge: .bottom))
    }
}