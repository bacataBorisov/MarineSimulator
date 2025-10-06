import SwiftUI

struct ViewKit {
    static func displayLabel(_ label: String, value: Double?) -> some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°", $0) } ?? "--")
                .font(.title2)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}