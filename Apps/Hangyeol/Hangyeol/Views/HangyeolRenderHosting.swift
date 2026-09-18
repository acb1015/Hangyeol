import CoreGraphics
import Foundation

/// 셸(개발자2)이 구현하는 렌더 호스트 계약. Views는 Kit/RealEngine을 직접 호출하지 않고 이것만 본다.
/// Phase0: 프로토콜·콜백 스텁. DocumentCore→SVG/PNG→네이티브 페이지 뷰(`NSViewRepresentable`) 실체는 셸 소유.
@MainActor
protocol HangyeolRenderHosting: AnyObject {
    func attach(document: HangyeolDocument) async throws
    func detach()
    var isReady: Bool { get }

    var zoomScale: CGFloat { get set }
    func setZoom(_ scale: CGFloat, animated: Bool)
    func fitWidth()
    func fitPage()

    var selection: HangyeolTextSelection? { get }
    func select(_ selection: HangyeolTextSelection)
    func clearSelection()

    /// 표시용 찾기. 치환은 `document.session.replaceText` / DocumentSession.
    func find(_ query: String, options: HangyeolFindOptions) -> [HangyeolFindHit]
    func reveal(_ hit: HangyeolFindHit)

    var onReady: (() -> Void)? { get set }
    var onSelectionChange: ((HangyeolTextSelection?) -> Void)? { get set }
    var onViewportChange: ((HangyeolViewportState) -> Void)? { get set }
    var onOpenFailure: ((HangyeolError) -> Void)? { get set }
    /// 프론트 제안: 크롬 로딩 표시. 합의 후 유지/삭제.
    var onLoadingChange: ((Bool) -> Void)? { get set }
}

struct HangyeolTextSelection: Equatable, Sendable {
    var section: UInt32
    var paragraph: UInt32
    var utf16Location: UInt32
    var utf16Length: UInt32
}

struct HangyeolFindOptions: Equatable, Sendable {
    var caseSensitive: Bool
    var wrapAround: Bool

    static let `default` = HangyeolFindOptions(caseSensitive: false, wrapAround: true)
}

struct HangyeolFindHit: Equatable, Identifiable, Sendable {
    var id: Int
    var selection: HangyeolTextSelection
}

struct HangyeolViewportState: Equatable, Sendable {
    var zoomScale: CGFloat
    /// `nil` = 자유 배율, `"width"` / `"page"` = fit 모드 힌트.
    var fitMode: String?
}
