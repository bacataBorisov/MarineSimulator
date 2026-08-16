import SwiftUI

/// Two-column sentence panel: controls left, optional preview right on wide windows.
struct SentencePanelLayout<Content: View, Preview: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 720 {
                HStack(alignment: .top, spacing: UIConstants.spacing * 2) {
                    ScrollView {
                        content()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)

                    preview()
                        .padding()
                        .frame(width: min(320, proxy.size.width * 0.38))
                }
            } else {
                ScrollView {
                    content()
                        .padding()
                }
            }
        }
    }
}
