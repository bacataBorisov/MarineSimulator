import SwiftUI

struct HydroMetricsView: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    var body: some View {
        GroupBox(label: Label("Hydro", systemImage: "drop")) {
            HStack(spacing: 24) {
                MetricColumn(label: "SPD", value: nmeaManager.formattedSpeed)
                MetricColumn(label: "DPT", value: nmeaManager.formattedDepth)
                MetricColumn(label: "SWT", value: nmeaManager.formattedTemperature)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func MetricColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .bold()
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Preview
#Preview {
    HydroMetricsView()
        .environment(NMEASimulator())
        .frame(width: 300)
        .padding()
}