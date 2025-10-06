import SwiftUI
import AppKit

@available(macOS 15.0, *)
struct ConsolePanelView: View {
    
    @Bindable var nmeaManager: NMEASimulator
    @Binding var consoleHeight: CGFloat
    
    let geometryHeight: CGFloat
    
    private let spacing: CGFloat = 8
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle + Trash button
            HStack {
                Spacer()
                Divider()
                Button {
                    nmeaManager.outputMessages.removeAll()
                } label: {
                    Label("", systemImage: "trash")
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, spacing)
                .padding(.bottom, 4)
            }
            .frame(height: UIConstants.bottomBarHeight)
            .frame(maxWidth: .infinity)
            .background(.black)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = consoleHeight - value.translation.height
                        let maxHeight = geometryHeight - UIConstants.tabBarHeight //tab bar in the DashboardView
                        consoleHeight = min(max(newHeight, UIConstants.bottomBarHeight), maxHeight)
                        NSCursor.rowResize(directions: [.up, .down]).set()
                    }
                
            )
            
            ConsoleView()
                .frame(height: consoleHeight)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}
