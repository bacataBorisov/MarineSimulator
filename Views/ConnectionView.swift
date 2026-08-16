import SwiftUI

struct ConnectionView: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConnectionHealthBanner(nmeaManager: nmeaManager)

                if nmeaManager.outputEndpoints.allSatisfy({ !$0.isEnabled }) {
                    Label("All outputs are off — Start still runs the simulation, but nothing is sent.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                SettingsCard(title: "Primary Output") {
                    if let primaryID = nmeaManager.outputEndpoints.first?.id,
                       let primaryIndex = nmeaManager.outputEndpoints.firstIndex(where: { $0.id == primaryID }) {
                        EndpointEditorView(
                            nmeaManager: nmeaManager,
                            endpoint: $nmeaManager.outputEndpoints[primaryIndex],
                            isPrimary: true
                        )
                    }
                }

                SettingsCard(title: "Additional Outputs") {
                    Text("Add destinations for multi-device testing (e.g. iPhone + iPad unicast).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(nmeaManager.outputEndpoints.enumerated()), id: \.element.id) { index, _ in
                        if index > 0 {
                            EndpointEditorView(
                                nmeaManager: nmeaManager,
                                endpoint: $nmeaManager.outputEndpoints[index],
                                isPrimary: false
                            )
                            .padding(12)
                            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            nmeaManager.addOutputEndpoint()
                        } label: {
                            Label("Add Output", systemImage: "plus")
                        }
                    }
                }

                SettingsCard(title: "Transmission") {
                    Toggle("Enable Timer", isOn: $nmeaManager.isTimerSelected)
                        .toggleStyle(.switch)
                        .controlSize(.regular)

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Send Interval (s)")
                            .frame(width: 140, alignment: .leading)
                        Stepper(value: $nmeaManager.interval, in: 0.1...10, step: 0.1) {
                            Text(String(format: "%.1f", nmeaManager.interval))
                                .monospacedDigit()
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                        .disabled(!nmeaManager.isTimerSelected)
                        Spacer(minLength: 0)
                    }

                    Text("Base tick rate; per-sentence rates in Realistic mode may be faster.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(nmeaManager.isTimerSelected ? "Continuous timer mode is active." : "Timer disabled: Start sends one burst only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview {
    ConnectionView(nmeaManager: NMEASimulator())
        .frame(width: 920, height: 720)
}
