import SwiftUI
import AppKit

#if DEBUG
/// Counts evaluations of a retained page body. Selection must not increment it.
enum RetainedDestinationBodyProbe {
    static var connectionEvaluations = 0
    static var simulationEvaluations = 0
    static var boatEvaluations = 0
    static var timerStatusEvaluations = 0
    static var timerStatus = ""
    static var timerStatusCard: String?
    static var intervalLabel = ""
    static var readings: [String: String] = [:]

    static func record(_ page: SidebarItem) {
        switch page {
        case .connection: connectionEvaluations += 1
        case .simulation: simulationEvaluations += 1
        case .boat: boatEvaluations += 1
        default: break
        }
    }

    static func noteTimerStatus(_ status: String, card: String?) {
        timerStatusEvaluations += 1
        timerStatus = status
        timerStatusCard = card
    }

    static func noteInterval(_ label: String) {
        intervalLabel = label
    }

    static func noteReading(_ title: String, _ label: String) {
        readings[title] = label
    }
}

private struct SettingsCardIdentityKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Debug-only identity of the enclosing `SettingsCard`, used to prove which card contains a child.
    var settingsCardIdentity: String? {
        get { self[SettingsCardIdentityKey.self] }
        set { self[SettingsCardIdentityKey.self] = newValue }
    }
}
#endif

/// Scrollable page shell used by Connection and the other sidebar panels.
struct PageContainer<Content: View>: View {
    var maxWidth: CGFloat = PageChrome.maxWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .pageContentFrame(maxWidth: maxWidth)
                .tracksConsoleEdge()
        }
        .background(DesignToken.Surface.page)
    }
}

/// Zero-size identity token for a destination whose SwiftUI tree stays mounted.
struct RetainedDestinationMarker: NSViewRepresentable {
    var page: SidebarItem

    func makeNSView(context: Context) -> RetainedDestinationMarkerView {
        RetainedDestinationMarkerView(page: page)
    }

    func updateNSView(_ nsView: RetainedDestinationMarkerView, context: Context) {}
}

final class RetainedDestinationMarkerView: NSView {
    let page: SidebarItem

    init(page: SidebarItem) {
        self.page = page
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    func pageContentFrame(maxWidth: CGFloat = PageChrome.maxWidth) -> some View {
        self
            .padding(PageChrome.padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Responsive layout

/// Content-width classes for setup pages.
/// `contentWidth` is the width proposed to the page body after the page inset.
/// Sidebar, toolbar, and console can make that width smaller than the 960×640 window.
/// These classes do not promise a content height. Pages scroll.
enum ContentWidthClass: Equatable {
    /// Available content below 720 points.
    case compact
    /// From 720 up to, but not including, two minimum configuration cards.
    case regular
    /// 900 points and above: 440 + 20 + 440.
    case wide
}

/// Layout names for `DesignToken`. Width class uses available page content, not the window.
enum ResponsiveLayout {
    static let targetMinimumContentWidth = DesignToken.Breakpoint.regular

    static let configurationGutter = DesignToken.Spacing.section
    static let configurationCardMinimum = DesignToken.Width.configurationCardMinimum
    static let configurationCardMaximum = DesignToken.Width.configurationCardMaximum
    /// Page column maximum for Connection and Simulation, including the page inset.
    static let adaptivePageMaxWidth = DesignToken.Width.adaptivePage

    static let formLabelWidth = DesignToken.Form.labelWidth
    static let formColumnGap = DesignToken.Spacing.field
    static let formValueMinimum = DesignToken.Form.valueMinimum
    static let formValueIdeal = DesignToken.Form.valueIdeal
    static let formValueMaximum = DesignToken.Form.valueMaximum
    static let formStackedSpacing = DesignToken.Spacing.stacked

    static var twoColumnContentWidth: CGFloat {
        configurationCardMinimum * 2 + configurationGutter
    }

    static var formRowCompactWidth: CGFloat {
        formLabelWidth + formColumnGap + formValueMinimum
    }

    /// Inner width of an adaptive page at `adaptivePageMaxWidth`.
    static var adaptiveContentWidth: CGFloat {
        adaptivePageMaxWidth - PageChrome.padding * 2
    }

    static func widthClass(for contentWidth: CGFloat) -> ContentWidthClass {
        if contentWidth < targetMinimumContentWidth { return .compact }
        if contentWidth < twoColumnContentWidth { return .regular }
        return .wide
    }

    static func formRowStyle(for availableWidth: CGFloat) -> FormRowStyle {
        availableWidth >= formRowCompactWidth ? .compactGrid : .stacked
    }

    static func formValueColumnWidth(for rowWidth: CGFloat) -> CGFloat {
        guard formRowStyle(for: rowWidth) == .compactGrid else {
            return min(formValueMaximum, max(0, rowWidth))
        }
        let remaining = rowWidth - formLabelWidth - formColumnGap
        return min(formValueMaximum, max(formValueMinimum, remaining))
    }
}

enum FormRowStyle: Equatable {
    /// Trailing label column, gap, leading value column.
    case compactGrid
    /// Label above the value. Used when the row cannot hold the compact grid.
    case stacked
}

/// Accessibility contract for a boat or sail measurement row.
enum FormRowAccessibility {
    static func editorLabel(_ title: String) -> String { title }
    /// A read-only row keeps its visible title. An editor hides that title from accessibility
    /// and puts the same string on the field, so the label is not announced twice.
    static let readOnlyKeepsVisibleTitle = true
    /// A measurement unit is placed in the value column, beside the editor.
    static let unitStaysBesideValue = true

    static func layoutStyle(for availableWidth: CGFloat) -> FormRowStyle {
        ResponsiveLayout.formRowStyle(for: availableWidth)
    }
}

/// Accessibility identifiers for Connection and Simulation cards.
enum SetupSection: String, Equatable {
    case connectionHealth
    case connectionWarning
    case primaryOutput
    case transmission
    case additionalOutputs
    case hardwareProfile
    case sentenceUpdateRates
    case testPresets
    case weatherSource
    case onboardSensors
    case advancedControls
}

/// Toolbar title and the decision not to repeat it in the page body.
enum PageTitlePresentation {
    static func toolbarTitle(for item: SidebarItem) -> String {
        item.pageTitle
    }

    /// Sidebar pages take their title from the toolbar. Section headings stay in the page.
    static func inContentPageTitle(for item: SidebarItem) -> String? {
        _ = item
        return nil
    }

    static let shellOwnsTopSeparator = true
}

/// The shell detail column owns the single separator under the toolbar.
enum ShellChrome {
    static let topSeparatorHeight: CGFloat = 1
    static let pagesAddTopSeparator = false
}

struct ShellContentTopSeparator: View {
    var body: some View {
        Rectangle()
            .fill(DesignToken.Separator.standard)
            .frame(height: ShellChrome.topSeparatorHeight)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// One label and one value. Narrow rows stack. Wider rows keep the label column.
/// Only the fitting branch is built, so an editor is not created twice.
struct CompactFormRow<Value: View>: View {
    var title: String
    var editor: Bool = false
    @ViewBuilder var value: () -> Value
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        let stacked = rowWidth > 0 && FormRowAccessibility.layoutStyle(for: rowWidth) == .stacked
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: ResponsiveLayout.formStackedSpacing) {
                    rowLabel
                    value()
                        .frame(maxWidth: ResponsiveLayout.formValueMaximum, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ResponsiveLayout.formColumnGap) {
                    rowLabel
                        .frame(width: ResponsiveLayout.formLabelWidth, alignment: .trailing)
                    value()
                        .frame(
                            minWidth: ResponsiveLayout.formValueMinimum,
                            maxWidth: ResponsiveLayout.formValueMaximum,
                            alignment: .leading
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            let nextStacked = newWidth > 0 && FormRowAccessibility.layoutStyle(for: newWidth) == .stacked
            let currentStacked = rowWidth > 0 && FormRowAccessibility.layoutStyle(for: rowWidth) == .stacked
            if rowWidth == 0 || nextStacked != currentStacked {
                rowWidth = newWidth
            }
        }
    }

    private var rowLabel: some View {
        Text(title)
            .font(DesignToken.Typography.field)
            .foregroundStyle(.secondary)
            .accessibilityHidden(editor)
    }
}

/// Compact and Regular are one column. Wide is two columns plus full-width bands.
/// The unused branch is not built. State stays in the observable model and the retained root.
struct SetupColumns<Compact: View, Wide: View>: View {
    @State private var contentWidth: CGFloat = 0
    @ViewBuilder var compact: () -> Compact
    @ViewBuilder var wide: () -> Wide

    private var isWide: Bool {
        contentWidth >= ResponsiveLayout.twoColumnContentWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            if isWide {
                wide()
            } else {
                compact()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            guard newWidth > 1 else { return }
            let nextWide = newWidth >= ResponsiveLayout.twoColumnContentWidth
            let currentWide = contentWidth >= ResponsiveLayout.twoColumnContentWidth
            if contentWidth == 0 || nextWide != currentWide {
                contentWidth = newWidth
            }
        }
    }
}

enum FormTextInputMode: Equatable {
    case plain
    case wholeNumber
    case decimal
    case signedDecimal

    func sanitize(_ raw: String) -> String {
        switch self {
        case .plain:
            return raw
        case .wholeNumber:
            return String(raw.filter(\.isNumber))
        case .decimal:
            return sanitizeDecimal(raw, allowNegative: false)
        case .signedDecimal:
            return sanitizeDecimal(raw, allowNegative: true)
        }
    }

    var hintMessage: String? {
        switch self {
        case .plain: return nil
        case .wholeNumber: return "Whole numbers only (0–9)."
        case .decimal: return "Numbers only (e.g. 12.5)."
        case .signedDecimal: return "Numbers only (e.g. -2.5 or 12.5)."
        }
    }

    private func sanitizeDecimal(_ raw: String, allowNegative: Bool) -> String {
        var seenSeparator = false
        var result = ""
        result.reserveCapacity(raw.count)
        for character in raw {
            if allowNegative && character == "-" && result.isEmpty {
                result.append("-")
            } else if character.isNumber {
                result.append(character)
            } else if (character == "." || character == ",") && !seenSeparator {
                seenSeparator = true
                result.append(".")
            }
        }
        return result
    }
}

/// Text field with one persistent external label. An optional unit stays beside the value.
struct FormTextRow: View {
    var title: String
    @Binding var text: String
    var accessibilityLabel: String?
    var unit: String?
    var inputMode: FormTextInputMode = .plain
    var validationError: ((String) -> String?)? = nil

    @FocusState private var isFocused: Bool
    @State private var draftText: String
    @State private var isRevertingDraft = false
    @State private var committedMessage: String?
    @State private var inputHintMessage: String?
    @State private var showValidationPopover = false

    init(
        title: String,
        text: Binding<String>,
        accessibilityLabel: String? = nil,
        unit: String? = nil,
        inputMode: FormTextInputMode = .plain,
        validationError: ((String) -> String?)? = nil
    ) {
        self.title = title
        self._text = text
        self.accessibilityLabel = accessibilityLabel
        self.unit = unit
        self.inputMode = inputMode
        self.validationError = validationError
        self._draftText = State(initialValue: text.wrappedValue)
    }

    private var label: String { accessibilityLabel ?? FormRowAccessibility.editorLabel(title) }
    private var activePopoverMessage: String? { inputHintMessage ?? committedMessage }

    private var usesCompactFieldWidth: Bool {
        unit != nil || inputMode != .plain || draftText.isEmpty
    }

    var body: some View {
        CompactFormRow(title: title, editor: true) {
            HStack(spacing: 0) {
                HStack(spacing: DesignToken.Spacing.related) {
                    if usesCompactFieldWidth {
                        field
                            .frame(
                                minWidth: unit != nil ? DesignToken.Form.editorMinimum : 56,
                                alignment: .leading
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        field
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let unit {
                        Text(unit)
                            .font(DesignToken.Typography.field)
                            .foregroundStyle(.secondary)
                    }

                    if let committedMessage {
                        Button {
                            showValidationPopover.toggle()
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.warning)
                        }
                        .buttonStyle(.plain)
                        .help(committedMessage)
                        .accessibilityLabel("\(title): \(committedMessage)")
                    }
                }
                .popover(isPresented: $showValidationPopover, arrowEdge: .bottom) {
                    if let message = activePopoverMessage {
                        Text(message)
                            .font(DesignToken.Typography.supporting)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(DesignToken.Spacing.inset)
                            .frame(width: 220, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if usesCompactFieldWidth {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isFocused = true
                        }
                }
            }
        }
        .onChange(of: draftText) { _, newValue in
            if isRevertingDraft {
                isRevertingDraft = false
                return
            }
            let sanitized = inputMode.sanitize(newValue)
            if sanitized != newValue, let hint = inputMode.hintMessage {
                isRevertingDraft = true
                draftText = sanitized
                if text != sanitized {
                    text = sanitized
                }
                NSSound.beep()
                inputHintMessage = hint
                showValidationPopover = true
            } else {
                inputHintMessage = nil
                if !isFocused {
                    committedMessage = validationError?(sanitized)
                } else {
                    committedMessage = nil
                    showValidationPopover = false
                }
                if text != sanitized {
                    text = sanitized
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                committedMessage = nil
                showValidationPopover = false
            } else {
                inputHintMessage = nil
                let message = validationError?(draftText)
                committedMessage = message
                showValidationPopover = message != nil
            }
        }
        .onChange(of: text) { _, newValue in
            if draftText != newValue {
                draftText = newValue
            }
            if !isFocused {
                committedMessage = validationError?(newValue)
            }
        }
    }

    private var field: some View {
        TextField("", text: $draftText)
            .textFieldStyle(.plain)
            .font(DesignToken.Typography.field)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit {
                inputHintMessage = nil
                let message = validationError?(draftText)
                committedMessage = message
                showValidationPopover = message != nil
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier(label)
            .multilineTextAlignment(.leading)
    }
}

/// Menu picker with one persistent external label and the same label on the control.
struct FormMenuRow<Selection: Hashable, Content: View>: View {
    var title: String
    var accessibilityLabel: String?
    @Binding var selection: Selection
    var isEnabled: Bool = true
    @ViewBuilder var content: () -> Content

    private var label: String { accessibilityLabel ?? FormRowAccessibility.editorLabel(title) }

    var body: some View {
        CompactFormRow(title: title, editor: true) {
            Picker(label, selection: $selection, content: content)
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityIdentifier(label)
                .pickerStyle(.menu)
                .disabled(!isEnabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
