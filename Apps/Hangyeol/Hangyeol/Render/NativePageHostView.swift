import AppKit
import SwiftUI

/// Path B 네이티브 페이지 호스트. WKWebView / postMessage 없음.
/// PNG는 `NSImage`, SVG는 ImageIO가 디코드하면 그리고 아니면 빈 페이지+심볼.
final class NativePageHostNSView: NSView {
    var surface: NativePageSurface = .idle {
        didSet { needsDisplay = true }
    }

    var zoomScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityIdentifier("native-page-host")
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.renderHostLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        switch surface {
        case .idle, .loading, .empty:
            return
        case .placeholder:
            drawPageChrome()
            drawSymbol("doc.richtext")
        case .png(let data), .svg(let data):
            drawPageChrome()
            if let image = NSImage(data: data) {
                drawImage(image)
            } else {
                drawSymbol("doc.richtext")
            }
        case .failed:
            drawPageChrome()
            drawSymbol("exclamationmark.triangle")
        }
    }

    private func pageRect() -> NSRect {
        let inset = bounds.insetBy(dx: 24, dy: 24)
        guard inset.width > 8, inset.height > 8 else { return bounds }
        let aspect: CGFloat = 210.0 / 297.0
        var width = inset.width * zoomScale
        var height = width / aspect
        if height > inset.height {
            height = inset.height
            width = height * aspect
        }
        return NSRect(
            x: inset.midX - width / 2,
            y: inset.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func drawPageChrome() {
        let rect = pageRect()
        NSColor.textBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawImage(_ image: NSImage) {
        let rect = pageRect().insetBy(dx: 8, dy: 8)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawSymbol(_ name: String) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let size = min(48, pageRect().width / 4)
        let rect = NSRect(
            x: bounds.midX - size / 2,
            y: bounds.midY - size / 2,
            width: size,
            height: size
        )
        NSColor.secondaryLabelColor.setFill()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// DocumentCore→SVG/PNG 페이지를 담는 셸 `NSViewRepresentable`.
struct NativePageHostView: NSViewRepresentable {
    @ObservedObject var host: NativePageRenderHost

    func makeNSView(context: Context) -> NativePageHostNSView {
        let view = NativePageHostNSView()
        view.surface = host.surface
        view.zoomScale = host.zoomScale
        return view
    }

    func updateNSView(_ nsView: NativePageHostNSView, context: Context) {
        nsView.surface = host.surface
        nsView.zoomScale = host.zoomScale
    }
}

/// `RenderHostView(host:)`에 Path B 페이지 뷰를 넣는 셸 컨테이너.
struct NativePageHostedRenderView: View {
    var document: HangyeolDocument
    var onOpenFailure: ((HangyeolError) -> Void)? = nil

    @StateObject private var host = NativePageRenderHost()

    var body: some View {
        RenderHostView(host: host, onOpenFailure: onOpenFailure)
            .overlay {
                NativePageHostView(host: host)
                    .allowsHitTesting(host.isReady)
            }
            .task(id: NativePageHostFactory.attachToken(for: document)) {
                await Task.yield()
                do {
                    try await host.attach(document: document)
                } catch is HangyeolError {
                    // `attach`가 `onOpenFailure`를 이미 호출함.
                } catch {
                    host.onOpenFailure?(.engineFailed(error.localizedDescription))
                }
            }
            .onDisappear {
                host.detach()
            }
    }
}

/// DocumentWindow가 `RenderHostView(host:)`에 네이티브 페이지 호스트를 주입하는 팩토리.
enum NativePageHostFactory {
    @MainActor
    static func makeHost() -> NativePageRenderHost {
        NativePageRenderHost()
    }

    /// Real + `canRenderPagePreview`일 때 DocumentWindow 본문.
    @MainActor
    static func renderHostView(
        document: HangyeolDocument,
        onOpenFailure: ((HangyeolError) -> Void)? = nil
    ) -> some View {
        NativePageHostedRenderView(document: document, onOpenFailure: onOpenFailure)
    }

    static func attachToken(for document: HangyeolDocument) -> String {
        "\(document.session.id.uuidString)|\(document.model.blocks.count)|\(document.hasUnsavedEdits)|\(document.session.undoGeneration)"
    }
}
