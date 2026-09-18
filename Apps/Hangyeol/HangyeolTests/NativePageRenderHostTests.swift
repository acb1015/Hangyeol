import XCTest
@testable import Hangyeol

private final class PreviewLiveEngine: HangyeolLiveSession, @unchecked Sendable {
    var isOpen: Bool
    var svg: Data
    var renderError: Error?
    var pageIndexes: [UInt32] = []

    init(svg: Data = Data(), isOpen: Bool = true, renderError: Error? = nil) {
        self.svg = svg
        self.isOpen = isOpen
        self.renderError = renderError
    }

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: "live", sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: String(data: data, encoding: .utf8) ?? ""))]
        )
    }

    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        Data("live|\(type.rawValue)".utf8)
    }

    func replaceText(find: String, replace: String) throws -> Int {
        _ = find
        _ = replace
        return 0
    }

    func displayModel(type: DocumentFileType, title: String) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: title, sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: "preview"))]
        )
    }

    func saveHwpx(to path: String) throws {
        _ = path
    }

    func listTables() throws -> [TableInfo] { [] }
    func listImages() throws -> [ImageInfo] { [] }
    func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        _ = (table, row, col, text)
    }
    func insertText(section: UInt32, paragraph: UInt32, charOffset: UInt32, text: String) throws {
        _ = (section, paragraph, charOffset, text)
    }
    func deleteRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32) throws {
        _ = (section, paragraph, charOffset, count)
    }

    func renderPageSvg(pageIndex: UInt32) throws -> Data {
        pageIndexes.append(pageIndex)
        if let renderError {
            throw renderError
        }
        return svg
    }
}

@MainActor
final class NativePageRenderHostTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        NativePageRaster.previewProvider = nil
    }

    override func tearDown() async throws {
        NativePageRaster.previewProvider = nil
        EngineClient.resetToDefault()
        try await super.tearDown()
    }

    func testAttachSignalsLoadingThenReadyWithoutUI() async throws {
        let host = NativePageRenderHost()
        var loading: [Bool] = []
        var readyCount = 0
        var openFailures: [HangyeolError] = []
        host.onLoadingChange = { loading.append($0) }
        host.onReady = { readyCount += 1 }
        host.onOpenFailure = { openFailures.append($0) }

        let document = HangyeolDocument(model: MockEngine.sampleDocument())
        try await host.attach(document: document)

        XCTAssertEqual(loading, [true, false])
        XCTAssertEqual(readyCount, 1)
        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .placeholder)
        XCTAssertTrue(openFailures.isEmpty)
    }

    func testDetachClearsReadyAndSurface() async throws {
        let host = NativePageRenderHost()
        try await host.attach(document: HangyeolDocument(model: MockEngine.sampleDocument()))
        XCTAssertTrue(host.isReady)

        host.detach()
        XCTAssertFalse(host.isReady)
        XCTAssertEqual(host.surface, .idle)
        XCTAssertNil(host.selection)
    }

    func testEmptyDocumentShowsEmptySurfaceWithoutOpenFailure() async throws {
        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        var loading: [Bool] = []
        host.onOpenFailure = { openFailures.append($0) }
        host.onLoadingChange = { loading.append($0) }

        try await host.attach(document: HangyeolDocument())

        XCTAssertEqual(loading, [true, false])
        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .empty)
        XCTAssertTrue(openFailures.isEmpty)
    }

    func testAttachWithSessionOpenErrorCallsOnOpenFailure() async {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertThrowsError(try session.open(data: MockEngine.failureMarker, type: .hwpx))
        XCTAssertNotNil(session.lastOpenError)

        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        var loading: [Bool] = []
        var readyCount = 0
        host.onOpenFailure = { openFailures.append($0) }
        host.onLoadingChange = { loading.append($0) }
        host.onReady = { readyCount += 1 }

        let document = HangyeolDocument(model: .empty, session: session)
        do {
            try await host.attach(document: document)
            XCTFail("open failure should throw")
        } catch let error as HangyeolError {
            XCTAssertEqual(error, session.lastOpenError)
        } catch {
            XCTFail("unexpected \(error)")
        }

        XCTAssertEqual(loading, [true, false])
        XCTAssertEqual(openFailures, [session.lastOpenError].compactMap { $0 })
        XCTAssertEqual(readyCount, 0)
        XCTAssertFalse(host.isReady)
        XCTAssertEqual(host.surface, .failed)
    }

    func testFindIsDisplayOnlyAndDoesNotRequireSessionMutation() async throws {
        let document = HangyeolDocument(model: MockEngine.sampleDocument())
        let host = NativePageRenderHost()
        try await host.attach(document: document)

        let hits = host.find("한결", options: .default)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.selection.utf16Length, UInt32("한결".utf16.count))

        host.reveal(hits[0])
        XCTAssertEqual(host.selection, hits[0].selection)

        XCTAssertFalse(document.session.canReplace)
        XCTAssertFalse(document.hasUnsavedEdits)
    }

    func testViewportZoomAndFitCallbacks() async throws {
        let host = NativePageRenderHost()
        var viewports: [HangyeolViewportState] = []
        host.onViewportChange = { viewports.append($0) }
        try await host.attach(document: HangyeolDocument(model: MockEngine.sampleDocument()))
        viewports.removeAll()

        host.setZoom(2, animated: false)
        XCTAssertEqual(host.zoomScale, 2)
        XCTAssertEqual(viewports.last?.zoomScale, 2)
        XCTAssertNil(viewports.last?.fitMode)

        host.fitWidth()
        XCTAssertEqual(viewports.last?.fitMode, "width")
        host.fitPage()
        XCTAssertEqual(viewports.last?.fitMode, "page")
    }

    func testPresentPngAndSvgSurfacesWithoutNSView() {
        let host = NativePageRenderHost()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        host.presentPageImage(png: png)
        XCTAssertEqual(host.surface, .png(png))

        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)
        host.presentPageImage(svg: svg)
        XCTAssertEqual(host.surface, .svg(svg))
    }

    func testProductPreviewOnMockIsNilAndAttachShowsPlaceholder() async throws {
        NativePageRaster.previewProvider = nil
        let document = HangyeolDocument(model: MockEngine.sampleDocument())
        XCTAssertFalse(document.session.canRenderPagePreview)
        XCTAssertNil(NativePageRaster.preview(from: document))

        let host = NativePageRenderHost()
        try await host.attach(document: document)
        XCTAssertEqual(host.surface, .placeholder)
    }

    func testAttachUsesInjectedSvgPreviewWithoutOpenError() async throws {
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)
        NativePageRaster.previewProvider = { _ in .svg(svg) }

        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        host.onOpenFailure = { openFailures.append($0) }

        try await host.attach(document: HangyeolDocument(model: MockEngine.sampleDocument()))

        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .svg(svg))
        XCTAssertTrue(openFailures.isEmpty)
    }

    func testAttachUsesInjectedPngPreviewWithoutOpenError() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        NativePageRaster.previewProvider = { _ in .png(png) }

        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        host.onOpenFailure = { openFailures.append($0) }

        try await host.attach(document: HangyeolDocument(model: MockEngine.sampleDocument()))

        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .png(png))
        XCTAssertTrue(openFailures.isEmpty)
    }

    func testAttachUsesSessionSvgPreviewWithoutOpenError() async throws {
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' id='session'/>".utf8)
        let live = PreviewLiveEngine(svg: svg)
        let document = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(engine: live)
        )
        NativePageRaster.previewProvider = nil

        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        host.onOpenFailure = { openFailures.append($0) }

        try await host.attach(document: document)

        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .svg(svg))
        XCTAssertEqual(live.pageIndexes, [0])
        XCTAssertTrue(openFailures.isEmpty)
    }

    func testProductPreviewUsesDocumentSessionNotEngineClientCurrent() {
        let svg = Data("<svg id='session'/>".utf8)
        let live = PreviewLiveEngine(svg: svg)
        let document = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(engine: live)
        )
        EngineClient.current = PreviewLiveEngine(svg: Data("<svg id='singleton'/>".utf8))
        NativePageRaster.previewProvider = nil

        XCTAssertEqual(NativePageRaster.preview(from: document), .svg(svg))
        XCTAssertEqual(live.pageIndexes, [0])
    }

    func testProductPreviewEmptyOrThrowIsNil() {
        NativePageRaster.previewProvider = nil
        let empty = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(engine: PreviewLiveEngine(svg: Data()))
        )
        XCTAssertNil(NativePageRaster.preview(from: empty))

        let failing = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(
                engine: PreviewLiveEngine(svg: Data("<svg/>".utf8), renderError: HangyeolError.corrupt)
            )
        )
        XCTAssertNil(NativePageRaster.preview(from: failing))

        let closed = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(engine: PreviewLiveEngine(svg: Data("<svg/>".utf8), isOpen: false))
        )
        XCTAssertFalse(closed.session.canRenderPagePreview)
        XCTAssertNil(NativePageRaster.preview(from: closed))
    }

    func testInstallProductPreviewProviderIsTestOverrideable() {
        NativePageRaster.installProductPreviewProvider()
        XCTAssertNotNil(NativePageRaster.previewProvider)
        XCTAssertNil(
            NativePageRaster.preview(from: HangyeolDocument(model: MockEngine.sampleDocument()))
        )

        let svg = Data("<svg id='inject'/>".utf8)
        NativePageRaster.previewProvider = { _ in .svg(svg) }
        XCTAssertEqual(
            NativePageRaster.preview(from: HangyeolDocument(model: MockEngine.sampleDocument())),
            .svg(svg)
        )
    }

    func testAppPreviewPathDoesNotInventPngOrCSymbols() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Hangyeol", isDirectory: true)
        let raster = try String(
            contentsOf: appRoot.appendingPathComponent("Render/NativePageRaster.swift"),
            encoding: .utf8
        )
        let kit = try String(
            contentsOf: appRoot.appendingPathComponent("Document/KitRealEngine.swift"),
            encoding: .utf8
        )
        let window = try String(
            contentsOf: appRoot.appendingPathComponent("Views/DocumentWindow.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(raster.contains("hg_render_page_png"))
        XCTAssertFalse(raster.contains("import CHangyeolEngine"))
        XCTAssertFalse(kit.contains("import CHangyeolEngine"))
        XCTAssertFalse(kit.contains("hg_render_page_png"))
        XCTAssertTrue(kit.contains("kit.renderPageSvg"))
        XCTAssertTrue(window.contains("private let showsRenderHostSketch = false"))
        XCTAssertFalse(window.contains("showsRenderHostSketch = true"))
    }

    func testFactoryMakeHostStartsDetached() {
        let host = NativePageHostFactory.makeHost()
        XCTAssertFalse(host.isReady)
        XCTAssertEqual(host.surface, .idle)
    }

    func testFactoryAttachTokenIsStableForSameSession() {
        let document = HangyeolDocument(model: MockEngine.sampleDocument())
        let first = NativePageHostFactory.attachToken(for: document)
        let second = NativePageHostFactory.attachToken(for: document)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains(document.session.id.uuidString))
    }
}
