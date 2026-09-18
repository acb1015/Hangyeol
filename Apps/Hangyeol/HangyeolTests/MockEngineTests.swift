import XCTest
@testable import Hangyeol

final class MockEngineTests: XCTestCase {
    private let engine = MockEngine()

    func testEmptyDataReturnsEmptyModel() throws {
        let model = try engine.open(data: Data(), type: .hwpx)
        XCTAssertTrue(model.isEmpty)
    }

    func testNonEmptyUnknownDataReturnsKoreanParagraphsAndTable() throws {
        let model = try engine.open(data: Data("not-json".utf8), type: .hwpx)
        XCTAssertTrue(model.metadata.isMockPreview)
        let paragraphs = model.blocks.compactMap { block -> String? in
            if case .paragraph(let paragraph) = block {
                return paragraph.plainText
            }
            return nil
        }

        XCTAssertTrue(paragraphs.contains(where: { $0.contains("한결") }))
        XCTAssertTrue(paragraphs.contains(where: { $0.contains("환영") }))
        XCTAssertTrue(paragraphs.contains(where: { $0.contains("Mock") }))

        let tables = model.blocks.compactMap { block -> TableBlock? in
            if case .table(let table) = block {
                return table
            }
            return nil
        }
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables.first?.columnCount, 2)
        XCTAssertGreaterThanOrEqual(tables.first?.rows.count ?? 0, 2)
        XCTAssertEqual(tables.first?.rows.first?.cells.first?.text, "항목")
    }

    func testSampleDocumentHasKoreanTableAndMockPreviewFlag() {
        let sample = MockEngine.sampleDocument()
        XCTAssertFalse(sample.isEmpty)
        XCTAssertTrue(sample.plainText.contains("한국어"))
        XCTAssertTrue(sample.metadata.isMockPreview)
        XCTAssertEqual(sample.metadata.sourceType, .hwpx)
        XCTAssertTrue(sample.plainText.contains("Mock 미리보기"))
    }

    func testNativeZipContainerDoesNotFakeSucceed() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00])
        XCTAssertTrue(HangyeolOpenBytes.looksLikeNativeDocumentContainer(zip))
        XCTAssertThrowsError(try engine.open(data: zip, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .corrupt)
        }
    }

    func testFailureMarkerThrows() {
        XCTAssertThrowsError(try engine.open(data: MockEngine.failureMarker, type: .hwp)) { error in
            guard case HangyeolError.engineFailed = error else {
                return XCTFail("expected HangyeolError.engineFailed, got \(error)")
            }
        }
    }

    func testEncryptedMarkerThrowsEncryptedNotSample() {
        XCTAssertThrowsError(try engine.open(data: HangyeolOpenBytes.encryptedMarker, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .encrypted)
        }
    }

    func testHwpSaveThrowsSaveRejected() {
        XCTAssertThrowsError(try engine.save(MockEngine.sampleDocument(), as: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolError, .saveRejected)
        }
    }

    func testSaveRoundTripPreservesPlainText() throws {
        let original = MockEngine.sampleDocument()
        let data = try engine.save(original, as: .hwpx)
        let restored = try engine.open(data: data, type: .hwpx)
        XCTAssertEqual(restored.blocks.count, original.blocks.count)
        XCTAssertEqual(restored.plainText, original.plainText)
        XCTAssertEqual(restored.metadata.sourceType, .hwpx)
        XCTAssertTrue(restored.metadata.isMockPreview)
    }
}
