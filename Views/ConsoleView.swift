import SwiftUI

struct ConsoleView: View {
    @Environment(NMEASimulator.self) private var nmeaManager
    @State private var scrollToBottom = false

    var body: some View {
        GroupBox(label: Label("NMEA Output", systemImage: "terminal")) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(nmeaManager.outputMessages.indices, id: \.self) { index in
                            Text(nmeaManager.outputMessages[index])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                                .id(index)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: nmeaManager.outputMessages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(nmeaManager.outputMessages.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 150) // Customize height as needed
    }
}