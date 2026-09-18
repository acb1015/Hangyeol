import XCTest
@testable import Hangyeol

final class DocumentModelTests: XCTestCase {
    func testEmptyModel() {
        XCTAssertTrue(DocumentModel.empty.isEmpty)
        XCTAssertEqual(DocumentModel.empty.displayTitle, L10n.untitled)
        XCTAssertEqual(DocumentModel.empty.plainText, "")
    }

    func testParagraphAndTablePlainText() {
        let model = DocumentModel(
            metadata: DocumentMetadata(title: "시험", sourceType: .hwpx),
            blocks: [
                .paragraph(ParagraphBlock(text: "첫 문단")),
                .table(TableBlock(headers: ["가", "나"], body: [["1", "2"]]))
            ]
        )
        XCTAssertEqual(model.displayTitle, "시험")
        XCTAssertTrue(model.plainText.contains("첫 문단"))
        XCTAssertTrue(model.plainText.contains("가\t나"))
        XCTAssertTrue(model.plainText.contains("1\t2"))
    }

    func testJSONRoundTrip() throws {
        let original = MockEngine.sampleDocument()
        XCTAssertTrue(original.metadata.isMockPreview)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DocumentModel.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.metadata.isMockPreview)
    }

    func testLegacyJSONWithoutMockFlagDecodesAsNotPreview() throws {
        let json = Data("""
        {"metadata":{"title":"구버전","sourceType":"hwpx"},"blocks":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(DocumentModel.self, from: json)
        XCTAssertFalse(decoded.metadata.isMockPreview)
    }
}
