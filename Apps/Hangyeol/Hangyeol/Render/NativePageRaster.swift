/// Path B page-preview injection seam.
///
/// Product default calls `hg_render_page_svg` on **this document's** open Real
/// session (`DocumentSession` → Kit `RealEngine` → `hg_free_buffer` via
/// `HangyeolEngineSupport.takeBuffer`). Mock / closed / throw / empty / non-SVG
/// → `nil` so the host shows `.placeholder`.
///
/// Tests overwrite `previewProvider`; `tearDown` should call
/// `installProductPreviewProvider()` (or assign `productPreviewProvider`) so
/// injection does not leak. Product install does not overwrite a non-nil test
/// provider.
///
/// **Never** enable `native-skia` / PNG FFI from this hook. Product path stays SVG.
@MainActor
enum NativePageRaster {
    typealias PreviewProvider = (HangyeolDocument) -> NativePageSurface?

    /// Product SVG provider: same-session `renderPageSvg(pageIndex: 0)` only.
    static let productPreviewProvider: PreviewProvider = { document in
        productPreview(document)
    }

    /// Test / product injection. Default is the product SVG provider.
    static var previewProvider: PreviewProvider? = productPreviewProvider

    /// App launch / first attach. No-op when a test already injected a provider.
    static func installProductPreviewProvider() {
        if previewProvider == nil {
            previewProvider = productPreviewProvider
        }
    }

    static func preview(from document: HangyeolDocument) -> NativePageSurface? {
        installProductPreviewProvider()
        return previewProvider?(document)
    }

    /// Mock / not open / cannot render → `nil`. Throw / empty / non UTF-8 SVG → `nil`.
    /// Never reads `EngineClient.current`.
    static func productPreview(_ document: HangyeolDocument) -> NativePageSurface? {
        let session = document.session
        guard !session.isUsingMock, session.canRenderPagePreview else {
            return nil
        }
        guard let data = try? session.renderPageSvg(pageIndex: 0) else {
            return nil
        }
        return svgSurface(from: data)
    }

    static func svgSurface(from data: Data) -> NativePageSurface? {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "<svg", options: [.caseInsensitive]) != nil else {
            return nil
        }
        return .svg(data)
    }
}
