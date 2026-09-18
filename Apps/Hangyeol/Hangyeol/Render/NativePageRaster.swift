/// Path B page-preview injection seam.
///
/// Product path: `hg_render_page_svg` on **this** document's session
/// (`HangyeolDocument.session` / that window's `hg_engine*`). Never
/// `EngineClient.current`. Buffer ownership stays in Kit (`takeBuffer` /
/// `hg_free_buffer`).
///
/// Mock / closed / unavailable / empty SVG / throw → `nil` → host `.placeholder`.
///
/// Tests may replace `previewProvider`. `preview(from:)` falls back to the
/// product path when the hook is `nil`. TearDown should reset the hook.
///
/// **Never** enable `native-skia` / Skia, and **never** add PNG FFI here.
/// Do not import `CHangyeolEngine` or invent `hg_render_*` C symbols.
@MainActor
enum NativePageRaster {
    typealias PreviewProvider = (HangyeolDocument) -> NativePageSurface?

    /// Test / product injection. App launch installs the product provider.
    static var previewProvider: PreviewProvider?

    /// Same-session page-0 SVG via `DocumentSession.renderPageSvg`.
    static let productPreviewProvider: PreviewProvider = { document in
        productPreview(from: document)
    }

    static func installProductPreviewProvider() {
        previewProvider = productPreviewProvider
    }

    static func productPreview(from document: HangyeolDocument) -> NativePageSurface? {
        guard document.session.canRenderPagePreview else { return nil }
        do {
            let data = try document.session.renderPageSvg(pageIndex: 0)
            guard !data.isEmpty else { return nil }
            return .svg(data)
        } catch {
            return nil
        }
    }

    static func preview(from document: HangyeolDocument) -> NativePageSurface? {
        if let previewProvider {
            return previewProvider(document)
        }
        return productPreview(from: document)
    }
}
