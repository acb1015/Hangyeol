import HangyeolKit
import UniformTypeIdentifiers
import XCTest
@testable import Hangyeol

final class HangyeolOpenFailureTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        EngineClient.resetToDefault()
        super.tearDown()
    }

    func testFrontendErrorSheetCasesHaveStableIDsAndNoAssociatedValues() {
        XCTAssertEqual(HangyeolError.encrypted.id, "encrypted")
        XCTAssertEqual(HangyeolError.corrupt.id, "corrupt")
        XCTAssertEqual(HangyeolError.unsupported.id, "unsupported")
        XCTAssertEqual(HangyeolError.saveRejected.id, "saveRejected")
        XCTAssertEqual(HangyeolError.unsupportedType("notes.txt").id, "unsupportedType:notes.txt")
        XCTAssertEqual(HangyeolError.encrypted, .encrypted)
        XCTAssertEqual(HangyeolError.corrupt, .corrupt)
        XCTAssertEqual(HangyeolError.unsupported, .unsupported)
    }

    func testErrorSheetCopyOmitsFreezeJargon() {
        for error in [HangyeolError.encrypted, .corrupt, .unsupported, .saveRejected] as [HangyeolError] {
            let text = error.localizedDescription
            XCTAssertFalse(text.contains("ENCRYPTED"), text)
            XCTAssertFalse(text.contains("CORRUPT"), text)
            XCTAssertFalse(text.contains("UNSUPPORTED_VERSION"), text)
            XCTAssertFalse(text.contains("SAVE_REJECTED"), text)
            XCTAssertFalse(text.contains("HG_PASSWORD"), text)
            XCTAssertNotNil(error.recoverySuggestion)
        }
    }

    func testMockOpenCorruptTruncatedFixtureDoesNotSwallow() throws {
        let data = try RepoFixtures.data("16_corrupt_truncated.hwpx")
        XCTAssertEqual(HangyeolOpenBytes.mockFailure(for: data), .corrupt)
        XCTAssertThrowsError(try MockEngine().open(data: data, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .corrupt)
        }
    }

    func testMockOpenPrettyprintedBadFixtureIsCorrupt() throws {
        let data = try RepoFixtures.data("21_prettyprinted_bad.hwpx")
        XCTAssertEqual(HangyeolOpenBytes.mockFailure(for: data), .corrupt)
        XCTAssertThrowsError(try MockEngine().open(data: data, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .corrupt)
        }
    }

    func testWrongExtPdfFilenameIsUnsupportedType() throws {
        let url = try RepoFixtures.url("14_wrong_ext_hwpx.pdf")
        XCTAssertFalse(UTType.hangyeolSupports(url: url))
        XCTAssertEqual(
            HangyeolError.unsupportedType(url.lastPathComponent).id,
            "unsupportedType:14_wrong_ext_hwpx.pdf"
        )
        // Bytes are valid HWPX (detect ignores extension); Mock must not treat them as CORRUPT
        // and must not fake-succeed as a welcome preview.
        let data = try Data(contentsOf: url)
        XCTAssertNil(HangyeolOpenBytes.mockFailure(for: data))
        XCTAssertTrue(HangyeolOpenBytes.looksLikeNativeDocumentContainer(data))
        XCTAssertThrowsError(try MockEngine().open(data: data, type: .hwpx)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testSyntheticEncryptedMapsToEncryptedAndMockDoesNotSwallow() throws {
        let data = try RepoFixtures.data("22_encrypted_synthetic.bin")
        XCTAssertTrue(data.starts(with: HangyeolOpenBytes.encryptedMarker))
        XCTAssertEqual(HangyeolOpenBytes.mockFailure(for: data), .encrypted)
        XCTAssertThrowsError(try MockEngine().open(data: data, type: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolError, .encrypted)
        }
        XCTAssertThrowsError(try MockEngine().open(data: HangyeolOpenBytes.encryptedMarker, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .encrypted)
        }
    }

    func testUnsupportedMarkerMapsToUnsupported() {
        XCTAssertEqual(
            HangyeolOpenBytes.mockFailure(for: HangyeolOpenBytes.unsupportedMarker),
            .unsupported
        )
        XCTAssertThrowsError(
            try MockEngine().open(data: HangyeolOpenBytes.unsupportedMarker, type: .hwp)
        ) { error in
            XCTAssertEqual(error as? HangyeolError, .unsupported)
        }
    }

    func testSessionOpenCorruptPublishesLastOpenErrorForErrorSheet() throws {
        EngineClient.resetToMock()
        let session = DocumentSession(engine: MockEngine())
        let data = try RepoFixtures.data("16_corrupt_truncated.hwpx")
        XCTAssertThrowsError(try session.open(data: data, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .corrupt)
        }
        XCTAssertEqual(session.lastOpenError, .corrupt)
        XCTAssertEqual(
            SessionOpenFailurePresentation.presentedError(
                lastOpenError: session.lastOpenError,
                dismissedID: nil
            ),
            .corrupt
        )
        XCTAssertNil(
            SessionOpenFailurePresentation.presentedError(
                lastOpenError: session.lastOpenError,
                dismissedID: HangyeolError.corrupt.id
            )
        )
    }

    func testSessionOpenEncryptedPublishesEncrypted() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertThrowsError(
            try session.open(data: HangyeolOpenBytes.encryptedMarker, type: .hwpx)
        ) { error in
            XCTAssertEqual(error as? HangyeolError, .encrypted)
        }
        XCTAssertEqual(session.lastOpenError, .encrypted)
    }

    func testSessionOpenUnsupportedPublishesUnsupported() {
        let session = DocumentSession(engine: MockEngine())
        XCTAssertThrowsError(
            try session.open(data: HangyeolOpenBytes.unsupportedMarker, type: .hwpx)
        ) { error in
            XCTAssertEqual(error as? HangyeolError, .unsupported)
        }
        XCTAssertEqual(session.lastOpenError, .unsupported)
    }

    func testHangyeolDocumentOpenCorruptThrowsCorrupt() throws {
        EngineClient.resetToMock()
        let data = try RepoFixtures.data("16_corrupt_truncated.hwpx")
        XCTAssertThrowsError(
            try HangyeolDocument(
                opening: data,
                type: .hwpx,
                filename: "16_corrupt_truncated.hwpx"
            )
        ) { error in
            XCTAssertEqual(HangyeolError.mapOpenFailure(error), .corrupt)
        }
    }

    func testHangyeolDocumentOpenEncryptedThrowsEncrypted() throws {
        EngineClient.resetToMock()
        let data = try RepoFixtures.data("22_encrypted_synthetic.bin")
        XCTAssertThrowsError(
            try HangyeolDocument(
                opening: data,
                type: .hwpx,
                filename: "22_encrypted_synthetic.hwpx"
            )
        ) { error in
            XCTAssertEqual(HangyeolError.mapOpenFailure(error), .encrypted)
        }
    }

    @MainActor
    func testFileOpeningMapsKitFreezeToDedicatedCases() {
        XCTAssertEqual(
            FileOpening.mappedError(HangyeolKitError.status(.corrupt, freeze: .corrupt)),
            .corrupt
        )
        XCTAssertEqual(
            FileOpening.mappedError(HangyeolKitError.status(.password, freeze: .encrypted)),
            .encrypted
        )
        XCTAssertEqual(
            FileOpening.mappedError(HangyeolKitError.status(.unsupported, freeze: .unsupportedVersion)),
            .unsupported
        )
        XCTAssertEqual(
            FileOpening.mappedError(HangyeolError.unsupportedType("14_wrong_ext_hwpx.pdf")),
            .unsupportedType("14_wrong_ext_hwpx.pdf")
        )
    }

    func testSaveRejectedPathStaysSaveRejectedOnSessionAndMock() {
        let session = DocumentSession(engine: MockEngine())
        let model = MockEngine.sampleDocument()
        XCTAssertThrowsError(try session.save(model, as: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolError, .saveRejected)
        }
        XCTAssertEqual(session.lastSaveError, .saveRejected)
        XCTAssertThrowsError(try MockEngine().save(model, as: .hwp)) { error in
            XCTAssertEqual(error as? HangyeolError, .saveRejected)
        }
        XCTAssertEqual(
            HangyeolError.mapSaveFailure(HangyeolKitError.status(.unsupported, freeze: .saveRejected)),
            .saveRejected
        )
    }

    func testRealSessionDoesNotFakeSuccessOnCorrupt() throws {
        let session = DocumentSession(engine: KitRealEngine())
        let data = try RepoFixtures.data("16_corrupt_truncated.hwpx")
        XCTAssertThrowsError(try session.open(data: data, type: .hwpx)) { error in
            let mapped = HangyeolError.mapOpenFailure(error)
            if KitRealEngine.isAvailable {
                XCTAssertEqual(mapped, .corrupt)
            } else {
                guard case .engineFailed = mapped else {
                    return XCTFail("unlinked Real must fail open, got \(mapped)")
                }
            }
        }
        XCTAssertNotNil(session.lastOpenError)
        XCTAssertFalse(session.isUsingMock)
    }

    func testRealOpenCorruptMapsWhenLinked() throws {
        try XCTSkipIf(!KitRealEngine.isAvailable, "XCFramework not linked — Real CORRUPT path is Mock/Kit mapped in other tests")
        let data = try RepoFixtures.data("16_corrupt_truncated.hwpx")
        XCTAssertThrowsError(try KitRealEngine().open(data: data, type: .hwpx)) { error in
            XCTAssertEqual(error as? HangyeolError, .corrupt)
        }
    }

    func testValidHubSampleIsNotClassifiedAsOpenFailure() throws {
        let data = try RepoFixtures.data("hub_hwpxlib_SimpleTable.hwpx")
        XCTAssertNil(HangyeolOpenBytes.mockFailure(for: data))
        XCTAssertTrue(HangyeolOpenBytes.looksLikeNativeDocumentContainer(data))
        XCTAssertThrowsError(try MockEngine().open(data: data, type: .hwpx)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("Mock must not fake-succeed hub-A, got \(error)")
            }
        }
    }
}

private enum RepoFixtures {
    static func url(_ filename: String) throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("fixtures").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        throw XCTSkip("missing fixtures/\(filename)")
    }

    static func data(_ filename: String) throws -> Data {
        try Data(contentsOf: try url(filename))
    }
}
