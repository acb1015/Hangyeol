import HangyeolKit
import XCTest
@testable import Hangyeol

final class KitRealEngineTests: XCTestCase {
    func testPlainTextMapsToParagraphsInOrder() {
        let model = KitRealEngine.documentModel(
            fromPlainText: "본문\n셀1\n셀2",
            type: .hwpx,
            title: "허브-A"
        )
        XCTAssertEqual(model.metadata.title, "허브-A")
        XCTAssertEqual(model.metadata.sourceType, .hwpx)
        let texts = model.blocks.compactMap { block -> String? in
            if case .paragraph(let paragraph) = block { return paragraph.plainText }
            return nil
        }
        XCTAssertEqual(texts, ["본문", "셀1", "셀2"])
        XCTAssertTrue(model.blocks.allSatisfy {
            if case .paragraph = $0 { return true }
            return false
        })
    }

    func testBlankAndWhitespaceLinesAreDropped() {
        let model = KitRealEngine.documentModel(
            fromPlainText: "\n  가  \n\n나\n",
            type: .hwp
        )
        XCTAssertEqual(model.metadata.sourceType, .hwp)
        let texts = model.blocks.compactMap { block -> String? in
            if case .paragraph(let paragraph) = block { return paragraph.plainText }
            return nil
        }
        XCTAssertEqual(texts, ["가", "나"])
    }

    func testEmptyPlainTextKeepsOneParagraphSoDocumentIsOpen() {
        let model = KitRealEngine.documentModel(fromPlainText: "   \n\n", type: .hwpx)
        XCTAssertEqual(model.blocks.count, 1)
        XCTAssertFalse(model.isEmpty)
        if case .paragraph(let paragraph) = model.blocks[0] {
            XCTAssertEqual(paragraph.plainText, "")
        } else {
            XCTFail("expected a paragraph")
        }
    }

    func testGenericErrorMapsToEngineFailed() {
        struct Dummy: Error, LocalizedError {
            var errorDescription: String? { "dummy-kit" }
        }
        XCTAssertEqual(KitRealEngine.mapError(Dummy()), .engineFailed("dummy-kit"))
    }

    func testSaveRejectedFreezeMapsToSaveRejected() {
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.unsupported, freeze: .saveRejected)),
            .saveRejected
        )
    }

    func testEncryptedFreezeMapsToEncrypted() {
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.password, freeze: .encrypted)),
            .encrypted
        )
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.password)),
            .encrypted
        )
        XCTAssertEqual(
            HangyeolError.mapOpenFailure(HangyeolKitError.status(.unsupported, freeze: .encrypted)),
            .encrypted
        )
    }

    func testCorruptFreezeMapsToCorrupt() {
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.corrupt, freeze: .corrupt)),
            .corrupt
        )
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.corrupt)),
            .corrupt
        )
        XCTAssertEqual(
            HangyeolError.mapOpenFailure(HangyeolKitError.status(.unsupported, freeze: .corrupt)),
            .corrupt
        )
    }

    func testUnsupportedFreezeMapsToUnsupported() {
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.unsupported, freeze: .unsupportedVersion)),
            .unsupported
        )
        XCTAssertEqual(
            KitRealEngine.mapError(HangyeolKitError.status(.unsupported)),
            .unsupported
        )
        XCTAssertEqual(
            HangyeolError.mapOpenFailure(HangyeolKitError.status(.unsupported, freeze: .unsupportedVersion)),
            .unsupported
        )
    }

    func testFreezeCodesDoNotMapToEngineFailedMush() {
        let cases: [HangyeolKitError] = [
            .status(.password, freeze: .encrypted),
            .status(.corrupt, freeze: .corrupt),
            .status(.unsupported, freeze: .unsupportedVersion),
            .status(.unsupported, freeze: .saveRejected)
        ]
        for kitError in cases {
            if case .engineFailed = KitRealEngine.mapError(kitError) {
                XCTFail("freeze \(kitError) must not collapse to engineFailed")
            }
        }
    }

    func testMapSaveFailureKeepsDedicatedFreezeCases() {
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolError.saveRejected),
            .saveRejected
        )
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolError.engineFailed("CORRUPT")),
            .saveFailed("CORRUPT")
        )
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolKitError.status(.unsupported, freeze: .saveRejected)),
            .saveRejected
        )
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolError.corrupt),
            .corrupt
        )
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolError.encrypted),
            .encrypted
        )
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolError.unsupported),
            .unsupported
        )
    }

    func testRenderPageSvgMapsKitErrorsWhenSessionClosed() {
        let engine = KitRealEngine()
        XCTAssertFalse(engine.isOpen)
        XCTAssertThrowsError(try engine.renderPageSvg(pageIndex: 0)) { error in
            guard let hangyeol = error as? HangyeolError else {
                return XCTFail("expected HangyeolError, got \(error)")
            }
            switch hangyeol {
            case .engineFailed, .corrupt, .unsupported, .notYetImplemented:
                break
            default:
                XCTFail("unexpected mapped error \(hangyeol)")
            }
        }
    }
}
