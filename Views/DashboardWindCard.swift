// DashboardWindCard.swift
// A compact macOS-compatible SwiftUI view for visualizing live wind angles

import SwiftUI

struct DashboardWindCard: View {
    let twd: Double?
    let twa: Double?
    let awa: Double?
    let width: CGFloat

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Wind")
                .font(.headline)

            AnemometerView(
                trueWindAngle: twa ?? 0,
                apparentWindAngle: awa ?? 0,
                width: width
            )
            .frame(width: width, height: width)

            HStack(spacing: 16) {
                windLabel("TWD", value: twd)
                windLabel("TWA", value: twa)
                windLabel("AWA", value: awa)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func windLabel(_ label: String, value: Double?) -> some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°", $0) } ?? "--")
                .font(.title2)
                .monospacedDigit()
        }
    }
}

#Preview {
    DashboardWindCard(
        twd: 86,
        twa: 44,
        awa: 26,
        width: 150
    )
}