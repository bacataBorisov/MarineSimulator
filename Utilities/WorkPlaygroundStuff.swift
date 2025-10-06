//
//  WorkPlaygroundStuff.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

//
//  ResizableVStack.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//


import SwiftUI

struct ResizableVStack: View {
    @State private var topHeight: CGFloat = 300
    private let minHeight: CGFloat = 0
    private let dividerHeight: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top View
                Color.blue
                    .frame(height: topHeight)
                    .overlay(Text("Top View").foregroundColor(.white))

                // Divider
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: dividerHeight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newHeight = topHeight + value.translation.height
                                let maxHeight = geometry.size.height - minHeight - dividerHeight
                                topHeight = min(max(newHeight, minHeight), maxHeight)
                            }
                    )

                // Bottom View
                Color.green
                    .overlay(Text("Bottom View").foregroundColor(.white))
            }
            .animation(.none, value: topHeight) // prevent glitchy animation during drag
        }
    }
}

#Preview {
    ResizableVStack()
}
