import UniformTypeIdentifiers
import XCTest
@testable import Hangyeol

private final class TaggedEngine: HangyeolEngine, @unchecked Sendable {
    let tag: String

    init(tag: String) {
        self.tag = tag
    }

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: tag, sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: String(data: data, encoding: .utf8) ?? ""))]
        )
    }

    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        Data("\(tag)|\(type.rawValue)|\(model.metadata.title)".utf8)
    }
}

private final class FakeLiveEngine: HangyeolLiveSession, @unchecked Sendable {
    var isOpen: Bool = true
    var replaceCount = 0
    var listedTables: [TableInfo] = []
    var listedImages: [ImageInfo] = []
    var setCellCalls: [(UInt32, UInt32, UInt32, String)] = []
    var insertCalls: [(UInt32, UInt32, UInt32, String)] = []
    var deleteCalls: [(UInt32, UInt32, UInt32, UInt32)] = []
    var pageSvg: Data = Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)
    var renderPageSvgCalls: [UInt32] = []
    var renderPageSvgError: Error?

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: "live", sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: String(data: data, encoding: .utf8) ?? ""))]
        )
    }

    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        Data("live-ir|\(type.rawValue)|\(model.plainText)".utf8)
    }

    func replaceText(find: String, replace: String) throws -> Int {
        _ = find
        _ = replace
        replaceCount += 1
        return 1
    }

    func displayModel(type: DocumentFileType, title: String) throws -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(title: title, sourceType: type),
            blocks: [.paragraph(ParagraphBlock(text: "replaced"))]
        )
    }

    func saveHwpx(to path: String) throws {
        try Data("live-hwpx".utf8).write(to: URL(fileURLWithPath: path))
    }

    func listTables() throws -> [TableInfo] {
        listedTables
    }

    func listImages() throws -> [ImageInfo] {
        listedImages
    }

    func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        setCellCalls.append((table, row, col, text))
    }

    func insertText(section: UInt32, paragraph: UInt32, charOffset: UInt32, text: String) throws {
        insertCalls.append((section, paragraph, charOffset, text))
    }

    func deleteRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32) throws {
        deleteCalls.append((section, paragraph, charOffset, count))
    }

    func renderPageSvg(pageIndex: UInt32) throws -> Data {
        renderPageSvgCalls.append(pageIndex)
        if let renderPageSvgError {
            throw renderPageSvgError
        }
        return pageSvg
    }
}

final class DocumentSessionTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        EngineClient.resetToDefault()
        super.tearDown()
    }

    func testNewDocumentsDoNotShareSessions() {
        EngineClient.resetToMock()
        let a = HangyeolDocument()
        let b = HangyeolDocument()
        XCTAssertFalse(a.session === b.session)
        XCTAssertNotEqual(a.session.id, b.session.id)
    }

    func testFileDocumentCopiesShareTheSameSession() {
        let session = DocumentSession(engine: MockEngine())
        let original = HangyeolDocument(model: MockEngine.sampleDocument(), session: session)
        var copy = original
        copy.hasUnsavedEdits = true
        XCTAssertTrue(copy.session === original.session)
    }

    func testSaveUsesBoundSessionNotProcessSingleton() throws {
        let sessionA = DocumentSession(engine: TaggedEngine(tag: "A"))
        let sessionB = DocumentSession(engine: TaggedEngine(tag: "B"))
        let model = DocumentModel(
            metadata: DocumentMetadata(title: "doc", sourceType: .hwpx),
            blocks: [.paragraph(ParagraphBlock(text: "본문"))]
        )
        let docA = HangyeolDocument(model: model, session: sessionA)
        let docB = HangyeolDocument(model: model, session: sessionB)

        EngineClient.current = TaggedEngine(tag: "SINGLETON")

        let dataA = try docA.encodedContents(as: .hwpx)
        let dataB = try docB.encodedContents(as: .hwpx)
        XCTAssertEqual(String(data: dataA, encoding: .utf8), "A|hwpx|doc")
        XCTAssertEqual(String(data: dataB, encoding: .utf8), "B|hwpx|doc")
        XCTAssertNotEqual(dataA, dataB)
        XCTAssertNil(sessionA.lastSaveError)
    }

    func testHwpWritePublishesSaveRejected() {
        let session = DocumentSession(engine: TaggedEngine(tag: "A"))
        let doc = HangyeolDocument(model: MockEngine.sampleDocument(), session: session)
        XCTAssertThrowsError(try doc.encodedContents(as: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolError, .saveRejected)
        }
        XCTAssertEqual(session.lastSaveError, .saveRejected)
    }

    func testMockSaveThenReopenUsesNewSessionAndRestoresJSON() throws {
        EngineClient.resetToMock()
        let original = HangyeolDocument(model: MockEngine.sampleDocument())
        let data = try original.encodedContents(as: .hwpx)

        let reopened = try HangyeolDocument(
            opening: data,
            type: .hwpx,
            filename: "roundtrip.hwpx"
        )

        XCTAssertFalse(reopened.session === original.session)
        XCTAssertEqual(reopened.model.plainText, original.model.plainText)
        XCTAssertEqual(reopened.model.blocks.count, original.model.blocks.count)
        XCTAssertFalse(reopened.hasUnsavedEdits)
        XCTAssertTrue(reopened.session.isUsingMock)
    }

    func testRealAdapterDoesNotBindMockForWelcomeJSON() throws {
        let session = DocumentSession(engine: KitRealEngine())
        XCTAssertFalse(session.isUsingMock)

        let sample = MockEngine.sampleDocument()
        let json = try JSONEncoder().encode(sample)
        XCTAssertThrowsError(try session.open(data: json, type: .hwpx)) { error in
            let mapped = HangyeolError.mapOpenFailure(error)
            XCTAssertNotEqual(mapped, .emptyFile)
        }
        XCTAssertFalse(session.isUsingMock)
        XCTAssertNotNil(session.lastOpenError)
    }

    func testReplaceMarksDocumentDirtyOnBoundSession() throws {
        let live = FakeLiveEngine()
        var document = HangyeolDocument(
            model: DocumentModel(
                metadata: DocumentMetadata(title: "제목", sourceType: .hwpx),
                blocks: [.paragraph(ParagraphBlock(text: "원본"))]
            ),
            session: DocumentSession(engine: live)
        )
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertTrue(document.session.canReplace)

        let count = try document.replaceText(find: "원본", replace: "새")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(live.replaceCount, 1)
        XCTAssertTrue(document.hasUnsavedEdits)
        XCTAssertEqual(document.model.plainText, "replaced")
        XCTAssertEqual(document.model.metadata.title, "제목")
    }

    func testSetCellTextMarksDocumentDirtyOnBoundSession() throws {
        let live = FakeLiveEngine()
        live.listedTables = [
            TableInfo(index: 0, section: 0, paragraph: 1, control: 0, rows: 2, cols: 3)
        ]
        var document = HangyeolDocument(
            model: DocumentModel(
                metadata: DocumentMetadata(title: "제목", sourceType: .hwpx),
                blocks: [.paragraph(ParagraphBlock(text: "원본"))]
            ),
            session: DocumentSession(engine: live)
        )
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertTrue(document.session.canEditCells)

        let tables = try document.listTables()
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].index, 0)
        XCTAssertEqual(tables[0].section, 0)
        XCTAssertEqual(tables[0].paragraph, 1)
        XCTAssertEqual(tables[0].control, 0)
        XCTAssertEqual(tables[0].rows, 2)
        XCTAssertEqual(tables[0].cols, 3)
        XCTAssertFalse(document.hasUnsavedEdits)

        try document.setCellText(table: 0, row: 0, col: 1, text: "새")
        XCTAssertEqual(live.setCellCalls.count, 1)
        XCTAssertEqual(live.setCellCalls[0].0, 0)
        XCTAssertEqual(live.setCellCalls[0].1, 0)
        XCTAssertEqual(live.setCellCalls[0].2, 1)
        XCTAssertEqual(live.setCellCalls[0].3, "새")
        XCTAssertTrue(document.hasUnsavedEdits)
        XCTAssertEqual(document.model.plainText, "replaced")
        XCTAssertEqual(document.model.metadata.title, "제목")
    }

    func testListImagesOnBoundSessionDoesNotMarkDirty() throws {
        let live = FakeLiveEngine()
        live.listedImages = [
            ImageInfo(
                index: 0,
                section: 0,
                paragraph: 2,
                control: 0,
                width: 120,
                height: 80,
                byteLen: 2048,
                binDataId: 1,
                format: "png",
                href: "BinData/image1.png"
            )
        ]
        let document = HangyeolDocument(
            model: DocumentModel(
                metadata: DocumentMetadata(title: "제목", sourceType: .hwpx),
                blocks: [.paragraph(ParagraphBlock(text: "원본"))]
            ),
            session: DocumentSession(engine: live)
        )
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertTrue(document.session.canListImages)

        let images = try document.listImages()
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].index, 0)
        XCTAssertEqual(images[0].section, 0)
        XCTAssertEqual(images[0].paragraph, 2)
        XCTAssertEqual(images[0].control, 0)
        XCTAssertEqual(images[0].width, 120)
        XCTAssertEqual(images[0].height, 80)
        XCTAssertEqual(images[0].byteLen, 2048)
        XCTAssertEqual(images[0].binDataId, 1)
        XCTAssertEqual(images[0].format, "png")
        XCTAssertEqual(images[0].href, "BinData/image1.png")
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertEqual(document.model.plainText, "원본")
    }

    func testInsertTextMarksDocumentDirtyOnBoundSession() throws {
        let live = FakeLiveEngine()
        var document = HangyeolDocument(
            model: DocumentModel(
                metadata: DocumentMetadata(title: "제목", sourceType: .hwpx),
                blocks: [.paragraph(ParagraphBlock(text: "원본"))]
            ),
            session: DocumentSession(engine: live)
        )
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertTrue(document.session.canEdit)
        XCTAssertTrue(document.session.canEditParagraphs)
        XCTAssertEqual(document.session.canEditParagraphs, document.session.canReplace)

        try document.insertText(section: 0, paragraph: 0, charOffset: 0, text: "앞")
        XCTAssertEqual(live.insertCalls.count, 1)
        XCTAssertEqual(live.insertCalls[0].0, 0)
        XCTAssertEqual(live.insertCalls[0].1, 0)
        XCTAssertEqual(live.insertCalls[0].2, 0)
        XCTAssertEqual(live.insertCalls[0].3, "앞")
        XCTAssertTrue(document.hasUnsavedEdits)
        XCTAssertEqual(document.model.plainText, "replaced")
        XCTAssertEqual(document.model.metadata.title, "제목")
    }

    func testDeleteRangeMarksDocumentDirtyOnBoundSession() throws {
        let live = FakeLiveEngine()
        var document = HangyeolDocument(
            model: DocumentModel(
                metadata: DocumentMetadata(title: "제목", sourceType: .hwpx),
                blocks: [.paragraph(ParagraphBlock(text: "원본"))]
            ),
            session: DocumentSession(engine: live)
        )
        XCTAssertFalse(document.hasUnsavedEdits)
        XCTAssertTrue(document.session.canEditParagraphs)

        try document.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)
        XCTAssertEqual(live.deleteCalls.count, 1)
        XCTAssertEqual(live.deleteCalls[0].0, 0)
        XCTAssertEqual(live.deleteCalls[0].1, 0)
        XCTAssertEqual(live.deleteCalls[0].2, 0)
        XCTAssertEqual(live.deleteCalls[0].3, 1)
        XCTAssertTrue(document.hasUnsavedEdits)
        XCTAssertEqual(document.model.plainText, "replaced")
        XCTAssertEqual(document.model.metadata.title, "제목")
    }

    func testRenderPageSvgOnBoundSessionDoesNotUseProcessSingleton() throws {
        let live = FakeLiveEngine()
        live.pageSvg = Data("<svg id='session'/>".utf8)
        let session = DocumentSession(engine: live)
        let other = FakeLiveEngine()
        other.pageSvg = Data("<svg id='singleton'/>".utf8)
        EngineClient.current = other

        XCTAssertTrue(session.canRenderPagePreview)
        let data = try session.renderPageSvg(pageIndex: 0)
        XCTAssertEqual(data, live.pageSvg)
        XCTAssertEqual(live.renderPageSvgCalls, [0])
        XCTAssertTrue(other.renderPageSvgCalls.isEmpty)
    }

    func testRenderPageSvgOnMockThrowsNotYetImplemented() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertFalse(session.canRenderPagePreview)
        XCTAssertThrowsError(try session.renderPageSvg(pageIndex: 0)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testRenderPageSvgOnClosedLiveSessionThrow() {
        let live = FakeLiveEngine()
        live.isOpen = false
        let session = DocumentSession(engine: live)
        XCTAssertFalse(session.canRenderPagePreview)
        XCTAssertThrowsError(try session.renderPageSvg(pageIndex: 0)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertTrue(live.renderPageSvgCalls.isEmpty)
    }

    func testCellApisOnMockThrowNotYetImplemented() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertFalse(session.canEditCells)
        XCTAssertThrowsError(try session.listTables()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try session.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }

        var document = HangyeolDocument(model: MockEngine.sampleDocument(), session: session)
        XCTAssertThrowsError(try document.listTables()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try document.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertFalse(document.hasUnsavedEdits)
    }

    func testImageApisOnMockThrowNotYetImplemented() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertFalse(session.canListImages)
        XCTAssertThrowsError(try session.listImages()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }

        let document = HangyeolDocument(model: MockEngine.sampleDocument(), session: session)
        XCTAssertThrowsError(try document.listImages()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertFalse(document.hasUnsavedEdits)
    }

    func testParagraphApisOnMockThrowNotYetImplemented() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertFalse(session.canEdit)
        XCTAssertFalse(session.canEditParagraphs)
        XCTAssertThrowsError(try session.insertText(section: 0, paragraph: 0, charOffset: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try session.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }

        var document = HangyeolDocument(model: MockEngine.sampleDocument(), session: session)
        XCTAssertThrowsError(try document.insertText(section: 0, paragraph: 0, charOffset: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try document.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertFalse(document.hasUnsavedEdits)
    }

    func testParagraphApisOnClosedLiveSessionThrow() {
        let live = FakeLiveEngine()
        live.isOpen = false
        let session = DocumentSession(engine: live)
        XCTAssertFalse(session.canEditParagraphs)
        XCTAssertThrowsError(try session.insertText(section: 0, paragraph: 0, charOffset: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try session.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertTrue(live.insertCalls.isEmpty)
        XCTAssertTrue(live.deleteCalls.isEmpty)
    }

    func testCellApisOnClosedLiveSessionThrow() {
        let live = FakeLiveEngine()
        live.isOpen = false
        let session = DocumentSession(engine: live)
        XCTAssertFalse(session.canEditCells)
        XCTAssertThrowsError(try session.listTables()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try session.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertTrue(live.setCellCalls.isEmpty)
    }

    func testImageApisOnClosedLiveSessionThrow() {
        let live = FakeLiveEngine()
        live.isOpen = false
        live.listedImages = [
            ImageInfo(
                index: 0,
                section: 0,
                paragraph: 0,
                control: 0,
                width: 1,
                height: 1,
                byteLen: 1,
                binDataId: 1,
                format: "png",
                href: "image1.png"
            )
        ]
        let session = DocumentSession(engine: live)
        XCTAssertFalse(session.canListImages)
        XCTAssertThrowsError(try session.listImages()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testOpenLiveSaveDoesNotReencodeAsTaggedJSON() throws {
        let live = FakeLiveEngine()
        let session = DocumentSession(engine: live)
        let model = try session.open(data: Data("허브".utf8), type: .hwpx)
        let saved = try session.save(model, as: .hwpx)
        XCTAssertEqual(String(data: saved, encoding: .utf8), "live-ir|hwpx|허브")
        XCTAssertFalse(session.isUsingMock)
    }

    func testUntitledLiveWithoutOpenDoesNotWriteMockJSON() throws {
        let live = FakeLiveEngine()
        live.isOpen = false
        let session = DocumentSession(engine: live)
        let model = MockEngine.sampleDocument()
        XCTAssertThrowsError(try session.save(model, as: .hwpx)) { error in
            guard case HangyeolError.saveFailed = error else {
                return XCTFail("expected saveFailed, got \(error)")
            }
        }
        XCTAssertFalse(session.isUsingMock)
        XCTAssertNotNil(session.lastSaveError)
    }

    func testMakeEngineAfterResetToMockIgnoresCurrentSingleton() {
        EngineClient.resetToMock()
        EngineClient.current = KitRealEngine()
        XCTAssertTrue(EngineClient.makeEngine() is MockEngine)
        XCTAssertTrue(DocumentSession().isUsingMock)
        EngineClient.resetToDefault()
        if KitRealEngine.isAvailable && !EngineClient.prefersMock {
            XCTAssertTrue(EngineClient.makeEngine() is KitRealEngine)
        } else {
            XCTAssertTrue(EngineClient.makeEngine() is MockEngine)
        }
    }
}
