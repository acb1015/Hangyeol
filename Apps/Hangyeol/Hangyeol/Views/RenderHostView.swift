import SwiftUI

/// HOP/rhwp 렌더 본문을 담을 호스트 자리.
/// - 기본: 비활성 → `DocumentWindow`가 `StructuredTextView`를 그대로 씀.
/// - 활성: 개발자2가 WKWebView 등 `content`를 주입.
/// Kit/Session/RealEngine을 직접 호출하지 않는다.
struct RenderHostView<Content: View>: View {
    /// `false`(기본)면 호출측에서 StructuredTextView를 쓴다.
    var isActive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if isActive {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L10n.renderHostLabel)
                    .accessibilityIdentifier("render-host-view")
            } else {
                EmptyView()
            }
        }
    }
}

extension RenderHostView where Content == RenderHostPlaceholder {
    /// 주입 전 스케치용 placeholder.
    static var placeholder: RenderHostView<RenderHostPlaceholder> {
        RenderHostView(isActive: true) { RenderHostPlaceholder() }
    }
}

struct RenderHostPlaceholder: View {
    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            VStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(L10n.renderHostPlaceholderTitle)
                    .font(.headline)
                Text(L10n.renderHostPlaceholderBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("render-host-placeholder")
    }
}
