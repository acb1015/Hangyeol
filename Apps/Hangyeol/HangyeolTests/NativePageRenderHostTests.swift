import XCTest
@testable import Hangyeol

@MainActor
final class NativePageRenderHostTests: XCTestCase {
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

    func testRasterHookIsNilUntilEngineFFIExists() {
        XCTAssertNil(
            NativePageRaster.preview(from: HangyeolDocument(model: MockEngine.sampleDocument()))
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
