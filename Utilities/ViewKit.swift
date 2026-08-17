//
//  ViewKit.swift
//  NMEASimulator
//

import SwiftUI

struct ViewKit {

    static func displayLabel(_ label: String, value: Double?, precision: Int? = 0) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(value.map { String(format: "%.\(precision ?? 0)f", $0) } ?? "--")
                .font(.system(.title, design: .monospaced))
                .fontWeight(.semibold)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(minWidth: 60, maxWidth: .infinity)
    }

    // MARK: - Toggle Row with Optional Info

    @ViewBuilder
    static func ToggleRowWithInfo(
        _ title: String,
        systemImage: String? = nil,
        isOn: Binding<Bool>,
        showInfo: Binding<Bool>? = nil,
        infoView: (() -> AnyView)? = nil
    ) -> some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)

            if let showInfo, let infoView {
                Button {
                    showInfo.wrappedValue = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: showInfo) {
                    SentenceHelpPopover(content: infoView())
                }
            }
        }
    }

    @ViewBuilder
    static func SentenceIntervalControl(
        _ title: String = "Interval",
        interval: Binding<Double>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Stepper(value: interval, in: 0...10, step: 0.1) {
                Text(interval.wrappedValue == 0 ? "Every tick" : "\(interval.wrappedValue, specifier: "%.1f") s")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .disabled(isDisabled)
        }
    }

    /// Single-line sentence control: name · interval · toggle · info.
    @ViewBuilder
    static func SentenceRow(
        _ title: String,
        isOn: Binding<Bool>,
        interval: Binding<Double>,
        intervalDisabled: Bool = false,
        showInfo: Binding<Bool>? = nil,
        infoView: (() -> AnyView)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                SentenceIntervalControl("", interval: interval, isDisabled: intervalDisabled || !isOn.wrappedValue)

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)

                if let showInfo, let infoView {
                    Button {
                        showInfo.wrappedValue = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: showInfo) {
                        SentenceHelpPopover(content: infoView())
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct PersistentDisclosureGroup<Content: View>: View {
    let title: String
    @AppStorage private var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, key: String, defaultExpanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = AppStorage(wrappedValue: defaultExpanded, key)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            content()
        }
    }
}

struct SentenceHelpPopover: View {
    @Environment(\.sidebarNavigation) private var sidebarNavigation
    let content: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            Divider()
            Button("Open in Manual") {
                sidebarNavigation?.select(.manual)
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Applies dimmed opacity if the condition is false
    public func dimmed(if condition: Bool) -> some View {
        self.opacity(condition ? 1.0 : 0.3)
    }
}

/// Numeric field that does not write the model until Return or focus loss.
/// The generator keeps using the last committed value while the user types.
struct DeferredNumericField: View {
    @Binding var value: Double
    var fractionDigits: Int
    var width: CGFloat? = 84
    var onEditingChange: ((Bool) -> Void)?

    @FocusState private var focused: Bool
    @State private var draft = ""

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: width)
            .focused($focused)
            .onAppear { draft = formatted(value) }
            .onChange(of: value) { _, newValue in
                if !focused { draft = formatted(newValue) }
            }
            .onChange(of: focused) { _, isFocused in
                onEditingChange?(isFocused)
                if isFocused {
                    draft = formatted(value)
                } else {
                    commit()
                }
            }
            .onSubmit {
                commit()
                focused = false
            }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never))
    }

    private func commit() {
        let normalized = draft.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else {
            draft = formatted(value)
            return
        }
        if parsed != value {
            value = parsed
        }
        draft = formatted(value)
    }
}
