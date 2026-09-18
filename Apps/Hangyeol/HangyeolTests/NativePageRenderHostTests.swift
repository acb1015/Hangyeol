import XCTest
@testable import Hangyeol

private final class PreviewLiveEngine: HangyeolLiveSession, @unchecked Sendable {
    var isOpen: Bool = true
    var pageSvg: Data?
    var renderError: Error?

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        _ = data
        return DocumentModel(
            metadata: DocumentMetadata(title: "live", sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: "본문"))]
        )
    }

    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        Data("live|\(type.rawValue)|\(model.plainText)".utf8)
    }

    func replaceText(find: String, replace: String) throws -> Int {
        _ = find
        _ = replace
        return 0
    }

    func displayModel(type: DocumentFileType, title: String) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: title, sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: "본문"))]
        )
    }

    func saveHwpx(to path: String) throws {
        try Data().write(to: URL(fileURLWithPath: path))
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
        _ = pageIndex
        if let renderError {
            throw renderError
        }
        if let pageSvg {
            return pageSvg
        }
        throw HangyeolError.notYetImplemented("페이지 미리보기")
    }
}

@MainActor
final class NativePageRenderHostTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        NativePageRaster.previewProvider = NativePageRaster.productPreviewProvider
    }

    override func tearDown() async throws {
        NativePageRaster.previewProvider = NativePageRaster.productPreviewProvider
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

    func testProductPreviewReturnsNilForMockSession() {
        NativePageRaster.installProductPreviewProvider()
        XCTAssertNotNil(NativePageRaster.previewProvider)
        XCTAssertNil(
            NativePageRaster.preview(from: HangyeolDocument(model: MockEngine.sampleDocument()))
        )
    }

    func testProductPreviewNilProviderFallsBackToProductThenMockPlaceholder() async throws {
        NativePageRaster.previewProvider = nil
        let host = NativePageRenderHost()
        try await host.attach(document: HangyeolDocument(model: MockEngine.sampleDocument()))
        XCTAssertEqual(host.surface, .placeholder)
        XCTAssertNotNil(NativePageRaster.previewProvider)
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

    func testProductPreviewUsesStubLiveSessionSvgNotEngineClient() async throws {
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg'><rect/></svg>".utf8)
        let live = PreviewLiveEngine()
        live.pageSvg = svg
        EngineClient.current = MockEngine()
        NativePageRaster.previewProvider = NativePageRaster.productPreviewProvider

        let document = HangyeolDocument(
            model: MockEngine.sampleDocument(),
            session: DocumentSession(engine: live)
        )
        XCTAssertTrue(document.session.canRenderPagePreview)
        XCTAssertEqual(NativePageRaster.preview(from: document), .svg(svg))

        let host = NativePageRenderHost()
        var openFailures: [HangyeolError] = []
        host.onOpenFailure = { openFailures.append($0) }
        try await host.attach(document: document)

        XCTAssertTrue(host.isReady)
        XCTAssertEqual(host.surface, .svg(svg))
        XCTAssertTrue(openFailures.isEmpty)
        XCTAssertTrue(EngineClient.current is MockEngine)
    }

    func testProductPreviewReturnsNilWhenLiveThrowsOrEmptyOrNonSvg() {
        NativePageRaster.previewProvider = NativePageRaster.productPreviewProvider
        let throwing = PreviewLiveEngine()
        throwing.renderError = HangyeolError.corrupt
        XCTAssertNil(
            NativePageRaster.preview(
                from: HangyeolDocument(
                    model: MockEngine.sampleDocument(),
                    session: DocumentSession(engine: throwing)
                )
            )
        )

        let empty = PreviewLiveEngine()
        empty.pageSvg = Data()
        XCTAssertNil(
            NativePageRaster.preview(
                from: HangyeolDocument(
                    model: MockEngine.sampleDocument(),
                    session: DocumentSession(engine: empty)
                )
            )
        )

        let plain = PreviewLiveEngine()
        plain.pageSvg = Data("not-svg".utf8)
        XCTAssertNil(
            NativePageRaster.preview(
                from: HangyeolDocument(
                    model: MockEngine.sampleDocument(),
                    session: DocumentSession(engine: plain)
                )
            )
        )

        let invalidUTF8 = PreviewLiveEngine()
        invalidUTF8.pageSvg = Data([0xFF, 0xFE])
        XCTAssertNil(
            NativePageRaster.preview(
                from: HangyeolDocument(
                    model: MockEngine.sampleDocument(),
                    session: DocumentSession(engine: invalidUTF8)
                )
            )
        )
    }

    func testInjectedProviderIsNotOverwrittenByProductInstall() {
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)
        NativePageRaster.previewProvider = { _ in .svg(svg) }
        NativePageRaster.installProductPreviewProvider()
        XCTAssertEqual(
            NativePageRaster.preview(from: HangyeolDocument(model: MockEngine.sampleDocument())),
            .svg(svg)
        )
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
