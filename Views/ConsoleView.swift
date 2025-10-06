//
//  ConsoleView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 15.06.25.
//


import SwiftUI

struct ConsoleView: View {
    @Environment(NMEASimulator.self) private var nmeaManager
        
    var body: some View {
        
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(nmeaManager.outputMessages.indices, id: \.self) { index in
                        Text(nmeaManager.outputMessages[index])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)
                            .id(index)
                    }
                }
            }
            .onChange(of: nmeaManager.outputMessages.count) {
                withAnimation {
                    proxy.scrollTo(nmeaManager.outputMessages.count - 1, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    ConsoleView()
        .environment(NMEASimulator())
}
