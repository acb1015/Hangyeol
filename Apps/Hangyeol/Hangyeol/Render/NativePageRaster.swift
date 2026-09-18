/// Path B page-preview injection seam.
///
/// Default `previewProvider` is `nil`, so `preview(from:)` returns `nil` and the
/// host falls back to `.placeholder`.
///
/// Wire `hg_render_*` / DocumentCore SVG **only after** 개발자1 FFI lands
/// (`hg_render_*` on the freeze header + Kit). Until that merge, do **not**
/// import C render symbols, call `hg_render_*`, or link new Vendor symbols here.
///
/// **Never** enable `native-skia` / Skia from this hook. Product path stays SVG.
@MainActor
enum NativePageRaster {
    typealias PreviewProvider = (HangyeolDocument) -> NativePageSurface?

    /// Test / post-FFI injection. Product default is `nil`.
    /// Assign a `hg_render_*` provider only after that FFI merge — not before.
    static var previewProvider: PreviewProvider?

    static func preview(from document: HangyeolDocument) -> NativePageSurface? {
        previewProvider?(document)
    }
}
