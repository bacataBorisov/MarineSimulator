//
//  ResizableSidePanel.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 6.10.25.
//


import SwiftUI
import AppKit

struct LeadingSidePanel<Content: View>: View {
    enum Edge { case leading, trailing }
    let edge: Edge
    @Binding var isVisible: Bool
    let topOffset: CGFloat  // height of your top bar so panel sits below it
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 0) {
                    if edge == .trailing { Spacer() }
                    VStack(spacing: 0) {
                        Spacer().frame(height: topOffset)
                        content
                            .frame(width: 320) // fixed width, non-resizable
                            .background(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15),
                                    radius: 8,
                                    x: edge == .leading ? 2 : -2,
                                    y: 0)
                    }
                    if edge == .leading { Spacer() }
                }
                .transition(.move(edge: edge == .leading ? .leading : .trailing)
                    .combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.34), value: isVisible)
    }
}

