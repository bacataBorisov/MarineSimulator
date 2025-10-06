import SwiftUI
import MapKit

struct OverviewDashboard: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    let gridItems = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Wind & Compass
                DashboardMetricsCard(title: "Wind & Compass", systemImage: "wind") {
                    DashboardWindCompassCard()
                        .frame(height: 250)
                }

                // MARK: - Hydro Metrics
                DashboardMetricsCard(title: "Speed / Depth / Temp", systemImage: "drop") {
                    LazyVGrid(columns: gridItems, spacing: 12) {
                        MetricPill(label: "Speed", value: format(nmeaManager.hydro.speedLog, precision: 1), systemImage: "speedometer")
                        MetricPill(label: "Depth", value: format(nmeaManager.hydro.depth, precision: 1), systemImage: "ruler")
                        MetricPill(label: "Temp", value: format(nmeaManager.hydro.waterTemp, precision: 1) + "°C", systemImage: "thermometer")
                    }
                }

                // MARK: - GPS / Position
                DashboardMetricsCard(title: "Positioning", systemImage: "location") {
                    LazyVGrid(columns: gridItems, spacing: 12) {
                        MetricPill(label: "SOG", value: format(nmeaManager.gps.speedOverGround, precision: 1), systemImage: "gauge")
                        MetricPill(label: "COG", value: format(nmeaManager.gps.courseOverGround, precision: 0), systemImage: "location.north.line")
                        MetricPill(label: "UTC", value: nmeaManager.gps.utcTime ?? "--", systemImage: "clock")
                    }
                }

                // MARK: - Status Indicators
                DashboardMetricsCard(title: "System Status", systemImage: "checkmark.circle") {
                    HStack(spacing: 16) {
                        StatusLight(label: "Wind", isActive: !nmeaManager.shouldSendMWV)
                        StatusLight(label: "Compass", isActive: !nmeaManager.shouldSendHDG)
                        StatusLight(label: "GPS", isActive: !nmeaManager.shouldSendRMC)
                        StatusLight(label: "Hydro", isActive: !nmeaManager.shouldSendDBT)
                    }
                }
            }
            .padding()
        }
    }

    private func format(_ value: Double?, precision: Int = 0) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(precision)f", value)
    }
}

// MARK: - Status Light View
struct StatusLight: View {
    var label: String
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }
}