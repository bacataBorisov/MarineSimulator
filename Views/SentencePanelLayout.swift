import SwiftUI

/// Two-column sentence panel: controls left, optional preview right on wide windows.
struct SentencePanelLayout<Content: View, Preview: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= PageChrome.splitBreakpoint {
                HStack(alignment: .top, spacing: PageChrome.stackSpacing) {
                    ScrollView {
                        content()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)

                    preview()
                        .frame(width: min(PageChrome.previewColumnWidth, proxy.size.width * 0.38))
                }
                .padding(PageChrome.padding)
            } else {
                ScrollView {
                    content()
                        .padding(PageChrome.padding)
                }
            }
        }
    }
}
