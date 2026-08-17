import SwiftUI

typealias SentencePanelLayout = SentencePage

/// Shared 50/50 chrome for Wind, Compass, Hydro, and GPS sentence pages.
/// Left: stacked sentence cards. Right: live values (and later extras).
struct SentencePage<Sentences: View, Preview: View>: View {
    private let sentences: Sentences
    private let preview: Preview

    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    init(
        @ViewBuilder sentences: () -> Sentences,
        @ViewBuilder preview: () -> Preview
    ) {
        self.sentences = sentences()
        self.preview = preview()
    }

    private var consoleClearance: CGFloat {
        ConsolePanelView.toolbarHeight + CGFloat(max(0, storedLogHeight)) + 8
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= PageChrome.splitBreakpoint {
                HStack(alignment: .top, spacing: PageChrome.stackSpacing) {
                    ScrollView {
                        sentenceColumn
                            .padding(PageChrome.padding)
                            .padding(.bottom, consoleClearance)
                    }
                    .frame(maxWidth: .infinity)

                    ScrollView {
                        previewColumn
                            .padding([.top, .trailing, .bottom], PageChrome.padding)
                            .padding(.bottom, consoleClearance)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                        sentences
                        preview
                    }
                    .padding(PageChrome.padding)
                    .padding(.bottom, consoleClearance)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var sentenceColumn: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            sentences
        }
        .frame(maxWidth: PageChrome.sentenceCardMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            preview
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension SentencePage {
    /// Wraps live readouts in `SentencePreviewCard` so pages only supply values.
    init<Live: View>(
        @ViewBuilder sentences: () -> Sentences,
        @ViewBuilder live: () -> Live
    ) where Preview == SentencePreviewCard<Live> {
        self.sentences = sentences()
        self.preview = SentencePreviewCard { live() }
    }
}

/// Left-column sentence group. Pages supply title + rows only.
struct SentenceCard<Content: View>: View {
    var title: String
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        GroupBox(label: titleLabel) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                content()
            }
            .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

/// Compact live readout for the right-hand column.
/// Rendered as a `GroupBox` so its top edge lines up with the sentence cards.
struct SentencePreviewCard<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String = "Live Data", @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox(label: Label(title, systemImage: "waveform.path.ecg")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: PageChrome.previewColumnWidth, alignment: .topLeading)
    }
}
