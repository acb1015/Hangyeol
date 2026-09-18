import UniformTypeIdentifiers
import XCTest
@testable import Hangyeol

final class HangyeolDocumentTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        EngineClient.resetToDefault()
        super.tearDown()
    }

    func testReadableTypesIncludeHwpxAndHwp() {
        let identifiers = HangyeolDocument.readableContentTypes.map(\.identifier)
        XCTAssertEqual(identifiers.first, UTType.hangyeolHwpx.identifier)
        XCTAssertTrue(identifiers.contains(UTType.hangyeolHwpx.identifier))
        XCTAssertTrue(identifiers.contains(UTType.hangyeolHwp.identifier))
        for stable in UTType.hangyeolStableImportedIdentifiers {
            XCTAssertTrue(
                identifiers.contains(stable),
                "readableContentTypes missing stable imported \(stable)"
            )
        }
    }

    func testFileTypeMapsImportedHopHwpxWithoutRequiringHopInstalled() {
        let hop = UTType(importedAs: "net.golbin.hop.hwpx")
        XCTAssertNotEqual(hop.identifier, UTType.hangyeolHwpx.identifier)
        XCTAssertTrue(
            HangyeolDocument.readableContentTypes.contains { $0.identifier == hop.identifier }
        )
        XCTAssertEqual(HangyeolDocument.fileType(from: hop), .hwpx)
        XCTAssertEqual(DocumentFileType(typeIdentifier: hop.identifier), .hwpx)
    }

    func testFileTypeMapsImportedHopHwpWithoutRequiringHopInstalled() {
        let hop = UTType(importedAs: "net.golbin.hop.hwp")
        XCTAssertNotEqual(hop.identifier, UTType.hangyeolHwp.identifier)
        XCTAssertTrue(
            HangyeolDocument.readableContentTypes.contains { $0.identifier == hop.identifier }
        )
        XCTAssertEqual(HangyeolDocument.fileType(from: hop), .hwp)
        XCTAssertEqual(DocumentFileType(typeIdentifier: hop.identifier), .hwp)
    }

    func testFilenameExtensionBoundTypesAreReadableAndMapToDocumentFileType() {
        if let hwpx = UTType(filenameExtension: "hwpx") {
            XCTAssertTrue(
                HangyeolDocument.readableContentTypes.contains { $0.identifier == hwpx.identifier },
                "DocumentGroup must accept the system-bound .hwpx UTI (\(hwpx.identifier))"
            )
            XCTAssertEqual(HangyeolDocument.fileType(from: hwpx), .hwpx)
        }
        if let hwp = UTType(filenameExtension: "hwp") {
            XCTAssertTrue(
                HangyeolDocument.readableContentTypes.contains { $0.identifier == hwp.identifier },
                "DocumentGroup must accept the system-bound .hwp UTI (\(hwp.identifier))"
            )
            XCTAssertEqual(HangyeolDocument.fileType(from: hwp), .hwp)
        }
    }

    func testWritableTypeIsHwpxByDefault() {
        XCTAssertEqual(HangyeolDocument.writableContentTypes, [.hangyeolHwpx])
    }

    func testNewDocumentIsEmpty() {
        XCTAssertTrue(HangyeolDocument().model.isEmpty)
    }

    func testUTTypeIdentifiers() {
        XCTAssertEqual(UTType.hangyeolHwpx.identifier, "org.hangyeol.hwpx")
        XCTAssertEqual(UTType.hangyeolHwp.identifier, "org.hangyeol.hwp")
        XCTAssertEqual(HangyeolDocument.fileType(from: .hangyeolHwpx), .hwpx)
        XCTAssertEqual(HangyeolDocument.fileType(from: .hangyeolHwp), .hwp)
        XCTAssertEqual(
            HangyeolDocument.fileType(from: UTType.resolvedReadableType(for: "net.golbin.hop.hwpx")),
            .hwpx
        )
        XCTAssertEqual(
            HangyeolDocument.fileType(from: UTType.resolvedReadableType(for: "net.golbin.hop.hwp")),
            .hwp
        )
        XCTAssertEqual(
            HangyeolDocument.fileType(
                from: UTType.resolvedReadableType(for: "com.infraware.polarisofficeservice.hwp")
            ),
            .hwp
        )
        if let haansoftHwpx = UTType("com.haansoft.HancomOfficeViewer.mac.hwpx") {
            XCTAssertEqual(HangyeolDocument.fileType(from: haansoftHwpx), .hwpx)
        }
        if let haansoftHwp = UTType("com.haansoft.HancomOfficeViewer.mac.hwp") {
            XCTAssertEqual(HangyeolDocument.fileType(from: haansoftHwp), .hwp)
        }
    }

    func testEngineClientResetToMockStillOpensSample() throws {
        EngineClient.resetToMock()
        XCTAssertTrue(EngineClient.current is MockEngine)
        let model = try EngineClient.current.open(data: Data("sample".utf8), type: .hwpx)
        XCTAssertFalse(model.isEmpty)
    }

    func testNewDocumentsEachBindASession() {
        EngineClient.resetToMock()
        let a = HangyeolDocument()
        let b = HangyeolDocument()
        XCTAssertFalse(a.session === b.session)
    }

    func testCellApisOnUntitledMockDocumentThrowNotYetImplemented() {
        EngineClient.resetToMock()
        var document = HangyeolDocument()
        XCTAssertFalse(document.session.canEditCells)
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

    func testImageApisOnUntitledMockDocumentThrowNotYetImplemented() {
        EngineClient.resetToMock()
        let document = HangyeolDocument()
        XCTAssertFalse(document.session.canListImages)
        XCTAssertThrowsError(try document.listImages()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertFalse(document.hasUnsavedEdits)
    }

    func testParagraphApisOnUntitledMockDocumentThrowNotYetImplemented() {
        EngineClient.resetToMock()
        var document = HangyeolDocument()
        XCTAssertFalse(document.session.canEdit)
        XCTAssertFalse(document.session.canEditParagraphs)
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

    func testOpenConfigurationDoesNotUseProcessSingleton() throws {
        EngineClient.resetToMock()
        var snapshot = MockEngine.sampleDocument()
        snapshot.metadata.title = ""
        let payload = try JSONEncoder().encode(snapshot)
        EngineClient.current = KitRealEngine()

        let document = try HangyeolDocument(
            opening: payload,
            type: .hwpx,
            filename: "singleton-clobber.hwpx"
        )
        XCTAssertTrue(document.session.isUsingMock)
        XCTAssertFalse(document.model.isEmpty)
        XCTAssertEqual(document.model.metadata.title, "singleton-clobber")
        XCTAssertTrue(document.model.metadata.isMockPreview)
    }

    func testOpeningWelcomeJSONThroughRealDoesNotLookLikeSuccess() throws {
        let json = try JSONEncoder().encode(MockEngine.sampleDocument())
        if KitRealEngine.isAvailable && !EngineClient.prefersMock {
            XCTAssertThrowsError(
                try HangyeolDocument(opening: json, type: .hwpx, filename: "welcome.hwpx")
            )
        } else {
            let document = try HangyeolDocument(
                opening: json,
                type: .hwpx,
                filename: "welcome.hwpx"
            )
            XCTAssertTrue(document.session.isUsingMock)
            XCTAssertTrue(document.model.metadata.isMockPreview)
        }
    }
}
