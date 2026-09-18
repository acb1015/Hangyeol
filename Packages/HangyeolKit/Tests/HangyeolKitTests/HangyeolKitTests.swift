import XCTest
@testable import HangyeolKit

final class FreezeMappingTests: XCTestCase {
    func testFreezeCodesMapToKitStatus() {
        XCTAssertEqual(HangyeolFreezeCode.encrypted.kitStatus, .password)
        XCTAssertEqual(HangyeolFreezeCode.unsupportedVersion.kitStatus, .unsupported)
        XCTAssertEqual(HangyeolFreezeCode.saveRejected.kitStatus, .unsupported)
        XCTAssertEqual(HangyeolFreezeCode.corrupt.kitStatus, .corrupt)
    }

    func testLinkedEngineNeverReturnsNotLinked() {
        XCTAssertNil(HangyeolKitError.from(status: .ok, lastError: nil, engineLinked: true))
        XCTAssertEqual(
            HangyeolKitError.from(status: .password, lastError: "ENCRYPTED", engineLinked: true),
            .status(.password, freeze: .encrypted)
        )
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: "UNSUPPORTED_VERSION", engineLinked: true),
            .status(.unsupported, freeze: .unsupportedVersion)
        )
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: "SAVE_REJECTED", engineLinked: true),
            .status(.unsupported, freeze: .saveRejected)
        )
        XCTAssertEqual(
            HangyeolKitError.from(status: .corrupt, lastError: "CORRUPT", engineLinked: true),
            .status(.corrupt, freeze: .corrupt)
        )
        // Linked + no freeze string: still a status error, never notLinked.
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: nil, engineLinked: true),
            .status(.unsupported, freeze: nil)
        )
    }

    func testStubFailureWithoutFreezeIsNotLinked() {
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: nil, engineLinked: false),
            .notLinked
        )
        XCTAssertEqual(
            HangyeolKitError.from(status: .corrupt, lastError: nil, engineLinked: false),
            .notLinked
        )
    }

    func testStubFailureWithFreezeMapsLikeLiveEngine() {
        XCTAssertEqual(
            HangyeolKitError.from(status: .password, lastError: "ENCRYPTED", engineLinked: false),
            .status(.password, freeze: .encrypted)
        )
    }

    func testFreezeWinsOverMismatchedStatus() {
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: "ENCRYPTED", engineLinked: true),
            .status(.password, freeze: .encrypted)
        )
        XCTAssertEqual(
            HangyeolKitError.from(status: .unsupported, lastError: "CORRUPT", engineLinked: true),
            .status(.corrupt, freeze: .corrupt)
        )
    }
}

final class RealEngineTests: XCTestCase {
    func testStubOpenThrowsNotLinked() throws {
        try XCTSkipIf(RealEngine.isLinked, "XCFramework linked — notLinked fallback does not apply")
        let engine = RealEngine()
        XCTAssertFalse(RealEngine.isLinked)
        XCTAssertFalse(engine.isOpen)
        XCTAssertThrowsError(try engine.open(data: Data([0x50, 0x4B]), type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertFalse(engine.isOpen)
    }

    func testStubSessionMethodsThrowNotLinked() throws {
        try XCTSkipIf(RealEngine.isLinked, "XCFramework linked — notLinked fallback does not apply")
        let engine = RealEngine()
        let model = DocumentModel(fileType: .hwpx)
        XCTAssertThrowsError(try engine.save(model, as: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.save(model, as: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.plainText()) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.replaceText(find: "a", replace: "b")) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.saveHwpx(to: "/tmp/out.hwpx")) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.insertText(section: 0, paragraph: 0, charOffset: 0, text: "x")) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.listTables()) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.listImages()) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try engine.renderPageSvg(pageIndex: 0)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertNil(engine.lastError())
        engine.close()
    }

    func testFFIStubStillThrowsNotLinked() throws {
        try XCTSkipIf(RealEngine.isLinked, "XCFramework linked — HangyeolEngineFFI is not the live session")
        let ffi = HangyeolEngineFFI()
        XCTAssertThrowsError(try ffi.open(data: Data(), type: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try ffi.listTables()) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try ffi.listImages()) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try ffi.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
        XCTAssertThrowsError(try ffi.renderPageSvg(pageIndex: 0)) { error in
            XCTAssertEqual(error as? HangyeolKitError, .notLinked)
        }
    }
}
