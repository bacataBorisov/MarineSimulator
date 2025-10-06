//
//  TopControlBar.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 4.10.25.
//

import SwiftUI

struct TopControlBar: View {
    @Environment(NMEASimulator.self) private var nmea

    @Binding var showLeft: Bool
    @Binding var showRight: Bool
    @Binding var showBottom: Bool

    @FocusState private var hostFocused: Bool
    @FocusState private var portFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Panel toggles
            ToggleIcon("sidebar.left", isOn: $showLeft)
            ToggleIcon("sidebar.right", isOn: $showRight)
            ToggleIcon("rectangle.bottomthird.inset.fill", isOn: $showBottom)

            Divider().frame(height: 22)

            Spacer()

            // Quick sentence toggles (compact)
            HStack(spacing: 10) {
                QuickToggle("MWV", \SentenceToggleStates.shouldSendMWV)
                QuickToggle("MWD", \SentenceToggleStates.shouldSendMWD)
                QuickToggle("VPW", \SentenceToggleStates.shouldSendVPW)
                QuickToggle("HDG", \SentenceToggleStates.shouldSendHDG)
                QuickToggle("HDT", \SentenceToggleStates.shouldSendHDT)
                QuickToggle("ROT", \SentenceToggleStates.shouldSendROT)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08)))
        .shadow(radius: 10)
    }
}

private struct ToggleIcon: View {
    let sf: String; @Binding var isOn: Bool
    init(_ sf: String, isOn: Binding<Bool>) { self.sf = sf; self._isOn = isOn }
    var body: some View {
        Button { withAnimation(.spring) { isOn.toggle() } } label: {
            Image(systemName: sf)
        }
        .buttonStyle(.bordered)
    }
}

private struct QuickToggle: View {
    @Environment(NMEASimulator.self) private var nmea

    let label: String
    let keyPath: WritableKeyPath<SentenceToggleStates, Bool>

    init(_ label: String, _ keyPath: WritableKeyPath<SentenceToggleStates, Bool>) {
        self.label = label
        self.keyPath = keyPath
    }

    private var isOn: Bool {
        nmea.sentenceToggles[keyPath: keyPath]
    }

    var body: some View {
        Button {
            nmea.sentenceToggles[keyPath: keyPath].toggle()
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isOn ? .green.opacity(0.25) : .white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

