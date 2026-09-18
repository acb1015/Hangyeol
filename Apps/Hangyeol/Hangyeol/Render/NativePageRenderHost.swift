import CoreGraphics
import Foundation

/// Path B Phase1 페이지 표시. DocumentCore SVG/PNG FFI가 열리기 전 스텁 표면.
enum NativePageSurface: Equatable {
    case idle
    case loading
    case empty
    /// 엔진 래스터 API 없음. SF Symbol / 빈 페이지.
    case placeholder
    case png(Data)
    case svg(Data)
    case failed
}

/// 셸 소유 `HangyeolRenderHosting` 구현. Views/크롬/L10n을 소유하지 않음.
/// 문서 진실은 `HangyeolDocument.session` (`hg_engine*`). 이 호스트는 파생 미리보기만.
@MainActor
final class NativePageRenderHost: ObservableObject, HangyeolRenderHosting {
    @Published private(set) var surface: NativePageSurface = .idle
    @Published private(set) var isReady = false

    var zoomScale: CGFloat = 1 {
        didSet {
            guard !isApplyingViewport else { return }
            guard zoomScale != oldValue else { return }
            fitMode = nil
            publishViewport()
        }
    }

    private(set) var selection: HangyeolTextSelection?
    private var fitMode: String?
    private var attachedDocument: HangyeolDocument?
    private var isApplyingViewport = false

    var onReady: (() -> Void)?
    var onSelectionChange: ((HangyeolTextSelection?) -> Void)?
    var onViewportChange: ((HangyeolViewportState) -> Void)?
    var onOpenFailure: ((HangyeolError) -> Void)?
    var onLoadingChange: ((Bool) -> Void)?

    func attach(document: HangyeolDocument) async throws {
        resetPreview(keepingCallbacks: true)
        attachedDocument = document
        surface = .loading
        onLoadingChange?(true)
        await Task.yield()

        do {
            try bind(document)
            onLoadingChange?(false)
        } catch {
            onLoadingChange?(false)
            throw error
        }
    }

    func detach() {
        resetPreview(keepingCallbacks: true)
    }

    func setZoom(_ scale: CGFloat, animated: Bool) {
        _ = animated
        applyViewport(scale: clampZoom(scale), fit: nil)
    }

    func fitWidth() {
        applyViewport(scale: 1, fit: "width")
    }

    func fitPage() {
        applyViewport(scale: 1, fit: "page")
    }

    func select(_ selection: HangyeolTextSelection) {
        self.selection = selection
        onSelectionChange?(selection)
    }

    func clearSelection() {
        selection = nil
        onSelectionChange?(nil)
    }

    /// 표시용. 치환은 `document.session.replaceText` / DocumentSession.
    func find(_ query: String, options: HangyeolFindOptions) -> [HangyeolFindHit] {
        guard !query.isEmpty, let document = attachedDocument else { return [] }
        return Self.displayHits(in: document.model, query: query, options: options)
    }

    func reveal(_ hit: HangyeolFindHit) {
        select(hit.selection)
    }

    /// 엔진 래스터가 붙기 전 테스트·프리뷰가 PNG 페이지를 넣을 때.
    func presentPageImage(png data: Data) {
        surface = .png(data)
    }

    /// 엔진 래스터가 붙기 전 테스트·프리뷰가 SVG 페이지를 넣을 때.
    func presentPageImage(svg data: Data) {
        surface = .svg(data)
    }

    private func bind(_ document: HangyeolDocument) throws {
        if let openError = document.session.lastOpenError {
            surface = .failed
            onOpenFailure?(openError)
            throw openError
        }

        if document.model.isEmpty {
            surface = .empty
            markReady()
            return
        }

        // Preview hook only (`NativePageRaster.previewProvider`). No `hg_render_*` here.
        surface = NativePageRaster.preview(from: document) ?? .placeholder
        markReady()
    }

    private func markReady() {
        isReady = true
        onReady?()
        publishViewport()
    }

    private func resetPreview(keepingCallbacks: Bool) {
        _ = keepingCallbacks
        attachedDocument = nil
        isReady = false
        surface = .idle
        selection = nil
        isApplyingViewport = true
        zoomScale = 1
        fitMode = nil
        isApplyingViewport = false
    }

    private func applyViewport(scale: CGFloat, fit: String?) {
        isApplyingViewport = true
        zoomScale = scale
        fitMode = fit
        isApplyingViewport = false
        publishViewport()
    }

    private func publishViewport() {
        onViewportChange?(HangyeolViewportState(zoomScale: zoomScale, fitMode: fitMode))
    }

    private func clampZoom(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 0.25), 4)
    }

    static func displayHits(
        in model: DocumentModel,
        query: String,
        options: HangyeolFindOptions
    ) -> [HangyeolFindHit] {
        let needle = options.caseSensitive ? query : query.lowercased()
        var hits: [HangyeolFindHit] = []
        var nextID = 0
        for (index, block) in model.blocks.enumerated() {
            guard case .paragraph(let paragraph) = block else { continue }
            let haystack = options.caseSensitive ? paragraph.plainText : paragraph.plainText.lowercased()
            var searchStart = haystack.startIndex
            while searchStart < haystack.endIndex,
                  let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                let location = haystack.utf16.distance(from: haystack.startIndex, to: range.lowerBound)
                let length = query.utf16.count
                hits.append(
                    HangyeolFindHit(
                        id: nextID,
                        selection: HangyeolTextSelection(
                            section: 0,
                            paragraph: UInt32(index),
                            utf16Location: UInt32(location),
                            utf16Length: UInt32(length)
                        )
                    )
                )
                nextID += 1
                searchStart = range.upperBound
            }
        }
        return hits
    }
}
