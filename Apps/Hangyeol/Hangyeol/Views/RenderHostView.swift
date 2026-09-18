import SwiftUI

/// Path B 렌더 본문 슬롯. Kit/Session/RealEngine을 직접 호출하지 않는다.
/// 셸이 DocumentCore→SVG/PNG 네이티브 페이지 뷰를 content로 주입한다.
/// - `host == nil`: 합의용 placeholder
/// - `host != nil`: 콜백 구독 (실 네이티브 페이지 뷰는 셸 `NSViewRepresentable`(DocumentCore→SVG/PNG))
struct RenderHostView: View {
    var host: (any HangyeolRenderHosting)?
    var onOpenFailure: ((HangyeolError) -> Void)? = nil

    @State private var isReady = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if let host {
                hostChrome(host: host)
            } else {
                RenderHostPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.renderHostLabel)
        .accessibilityIdentifier("render-host-view")
        .onAppear { wireCallbacks() }
        .onChange(of: hostIdentity) { _, _ in wireCallbacks() }
    }

    /// Phase0: 셸 Representable이 붙기 전엔 상태·콜백만.
    @ViewBuilder
    private func hostChrome(host: any HangyeolRenderHosting) -> some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if isLoading || !isReady {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityLabel(L10n.renderHostLoading)
            }
        }
        .accessibilityIdentifier("render-host-live-stub")
        .accessibilityValue(isReady ? L10n.renderHostReady : L10n.renderHostLoading)
    }

    private var hostIdentity: ObjectIdentifier? {
        host.map { ObjectIdentifier($0) }
    }

    private func wireCallbacks() {
        guard let host else {
            isReady = false
            isLoading = false
            return
        }
        isReady = host.isReady
        host.onReady = {
            Task { @MainActor in
                isReady = true
                isLoading = false
            }
        }
        host.onLoadingChange = { loading in
            Task { @MainActor in
                isLoading = loading
            }
        }
        host.onOpenFailure = { error in
            Task { @MainActor in
                onOpenFailure?(error)
            }
        }
        // selection / viewport는 Phase2 크롬 연동 시 DocumentWindow가 구독.
    }
}

extension RenderHostView {
    /// 주입 전 스케치.
    static var placeholder: RenderHostView {
        RenderHostView(host: nil)
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
