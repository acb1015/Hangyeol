import XCTest
@testable import Hangyeol

final class EngineClientTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        EngineClient.resetToDefault()
        super.tearDown()
    }

    func testResetToMockAlwaysInstallsMockEngine() throws {
        EngineClient.resetToMock()
        XCTAssertTrue(EngineClient.current is MockEngine)
        XCTAssertTrue(EngineClient.isUsingMock)
        XCTAssertNil(EngineClient.liveSession)

        let model = try EngineClient.current.open(data: Data("sample".utf8), type: .hwpx)
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.plainText.contains("한결"))
        XCTAssertTrue(model.metadata.isMockPreview)
    }

    func testMockEnvironmentDefaultIsOff() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: EngineClient.useMockFlagKey))
        if ProcessInfo.processInfo.environment[EngineClient.useMockFlagKey] == nil {
            XCTAssertFalse(EngineClient.environmentForcesMock)
            XCTAssertFalse(EngineClient.prefersMock)
        }
    }

    func testUserDefaultsFlagForcesMockInFactory() {
        UserDefaults.standard.set(true, forKey: EngineClient.useMockFlagKey)
        XCTAssertTrue(EngineClient.prefersMock)
        XCTAssertTrue(EngineClient.makeDefaultEngine() is MockEngine)
    }

    func testDefaultEngineIsRealOnlyWhenLinkedAndNotForced() {
        UserDefaults.standard.removeObject(forKey: EngineClient.useMockFlagKey)
        let engine = EngineClient.makeDefaultEngine()
        if KitRealEngine.isAvailable && !EngineClient.environmentForcesMock {
            XCTAssertTrue(engine is KitRealEngine)
        } else {
            XCTAssertTrue(engine is MockEngine)
        }
    }

    func testResetToDefaultRestoresFactoryChoice() {
        EngineClient.resetToMock()
        XCTAssertTrue(EngineClient.current is MockEngine)
        EngineClient.resetToDefault()
        if KitRealEngine.isAvailable && !EngineClient.prefersMock {
            XCTAssertTrue(EngineClient.current is KitRealEngine)
        } else {
            XCTAssertTrue(EngineClient.current is MockEngine)
        }
    }

    func testReplaceOnMockThrowsNotYetImplemented() {
        EngineClient.resetToMock()
        XCTAssertThrowsError(try EngineClient.replaceText(find: "1", replace: "HGPOC99")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testListTablesAndSetCellTextOnMockThrowNotYetImplemented() {
        EngineClient.resetToMock()
        XCTAssertThrowsError(try EngineClient.listTables()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try EngineClient.setCellText(table: 0, row: 0, col: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testListImagesOnMockThrowNotYetImplemented() {
        EngineClient.resetToMock()
        XCTAssertThrowsError(try EngineClient.listImages()) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testInsertTextAndDeleteRangeOnMockThrowNotYetImplemented() {
        EngineClient.resetToMock()
        XCTAssertThrowsError(try EngineClient.insertText(section: 0, paragraph: 0, charOffset: 0, text: "x")) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
        XCTAssertThrowsError(try EngineClient.deleteRange(section: 0, paragraph: 0, charOffset: 0, count: 1)) { error in
            guard case HangyeolError.notYetImplemented = error else {
                return XCTFail("expected notYetImplemented, got \(error)")
            }
        }
    }

    func testMakeEngineReturnsIndependentInstances() {
        EngineClient.resetToMock()
        let first = EngineClient.makeEngine()
        let second = EngineClient.makeEngine()
        XCTAssertTrue(first is MockEngine)
        XCTAssertTrue(second is MockEngine)
        // Existentials are distinct values; Real would also be distinct class instances.
        let sessionA = DocumentSession(engine: first)
        let sessionB = DocumentSession(engine: second)
        XCTAssertFalse(sessionA === sessionB)
    }

    func testResetToMockForcesFactoryWhileCurrentCanStillBeSwapped() {
        EngineClient.resetToMock()
        EngineClient.current = KitRealEngine()
        XCTAssertFalse(EngineClient.isUsingMock)
        XCTAssertTrue(EngineClient.makeEngine() is MockEngine)

        EngineClient.resetToDefault()
        let engine = EngineClient.makeEngine()
        if KitRealEngine.isAvailable && !EngineClient.prefersMock {
            XCTAssertTrue(engine is KitRealEngine)
        } else {
            XCTAssertTrue(engine is MockEngine)
        }
    }
}
