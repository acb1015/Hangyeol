import Foundation

/// 문서 엔진 경계. **기본값은 Real + Vendor XCFramework** (`KitRealEngine`).
/// `HANGYEOL_USE_MOCK` 기본은 **OFF** (미설정 / `0` / `false` / `NO`).
/// 롤백만 `resetToMock()` · 환경 `1`/`true`/`YES` · UserDefaults. XCFramework가 없으면 Mock 폴백.
protocol HangyeolEngine: Sendable {
    func open(data: Data, type: DocumentFileType) throws -> DocumentModel
    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data
}

/// Live DocumentCore session extras (Kit `RealEngine` via `KitRealEngine`).
protocol HangyeolLiveSession: HangyeolEngine {
    var isOpen: Bool { get }
    func replaceText(find: String, replace: String) throws -> Int
    func displayModel(type: DocumentFileType, title: String) throws -> DocumentModel
    func saveHwpx(to path: String) throws
    func listTables() throws -> [TableInfo]
    func listImages() throws -> [ImageInfo]
    func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws
    func insertText(section: UInt32, paragraph: UInt32, charOffset: UInt32, text: String) throws
    func deleteRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32) throws
    /// Current characters at an engine index. Used to invert `deleteRange`.
    func textInRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32) throws -> String
    /// Current cell plain text. Used to invert `setCellText`.
    func cellText(table: UInt32, row: UInt32, col: UInt32) throws -> String
    /// IR bytes for undo when an inverse command cannot be captured (`replaceText`, Real fallback).
    func captureUndoState() throws -> Data
    func restoreUndoState(_ data: Data) throws
    /// Read-only UTF-8 SVG for `pageIndex` (0-based). Kit `hg_render_page_svg`.
    func renderPageSvg(pageIndex: UInt32) throws -> Data
}

extension HangyeolLiveSession {
    func textInRange(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        count: UInt32
    ) throws -> String {
        _ = section
        _ = paragraph
        _ = charOffset
        _ = count
        throw HangyeolError.notYetImplemented(String(
            localized: "error.engine.undoPeek",
            defaultValue: "실행 취소 미리보기"
        ))
    }

    func cellText(table: UInt32, row: UInt32, col: UInt32) throws -> String {
        _ = table
        _ = row
        _ = col
        throw HangyeolError.notYetImplemented(String(
            localized: "error.engine.undoPeek",
            defaultValue: "실행 취소 미리보기"
        ))
    }

    func captureUndoState() throws -> Data {
        throw HangyeolError.notYetImplemented(String(
            localized: "error.engine.undoSnapshot",
            defaultValue: "실행 취소 스냅샷"
        ))
    }

    func restoreUndoState(_ data: Data) throws {
        _ = data
        throw HangyeolError.notYetImplemented(String(
            localized: "error.engine.undoSnapshot",
            defaultValue: "실행 취소 스냅샷"
        ))
    }

    func renderPageSvg(pageIndex: UInt32) throws -> Data {
        _ = pageIndex
        throw HangyeolError.notYetImplemented(String(
            localized: "error.engine.renderPageSvgMock",
            defaultValue: "페이지 미리보기 (Mock)"
        ))
    }
}

enum EngineClient {
    /// Launch env and UserDefaults key. `1` / `true` / `YES` force Mock.
    static let useMockFlagKey = "HANGYEOL_USE_MOCK"

    private static let holder = Holder()

    /// Process-wide factory probe / test seam. **Not** the open document's session.
    /// File open/save / page preview must use `HangyeolDocument.session` (`DocumentSession`).
    /// Never call `hg_render_page_svg` against this singleton.
    static var current: any HangyeolEngine {
        get { holder.engine }
        set { holder.engine = newValue }
    }

    static var isUsingMock: Bool { current is MockEngine }

    static var liveSession: (any HangyeolLiveSession)? {
        current as? any HangyeolLiveSession
    }

    /// Process-level rollback. Does not persist UserDefaults.
    /// Subsequent `makeEngine()` (new documents) also return Mock until `resetToDefault()`.
    static func resetToMock() {
        holder.forceMock = true
        current = MockEngine()
    }

    static func resetToDefault() {
        holder.forceMock = false
        current = makeDefaultEngine()
    }

    /// Default **OFF**. Only `1` / `true` / `YES` (env) or UserDefaults true force Mock.
    static var prefersMock: Bool {
        if environmentForcesMock { return true }
        return UserDefaults.standard.bool(forKey: useMockFlagKey)
    }

    /// Missing env, `0`, `false`, `NO` → false (Real+Vendor default).
    static var environmentForcesMock: Bool {
        guard let raw = ProcessInfo.processInfo.environment[useMockFlagKey] else {
            return false
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    /// New engine instance for one document. Does not touch `current`'s live `hg_engine*`.
    static func makeEngine() -> any HangyeolEngine {
        if holder.forceMock {
            return MockEngine()
        }
        return makeDefaultEngine()
    }

    /// Default: Real when the XCFramework is linked and Mock is not forced; else Mock.
    static func makeDefaultEngine() -> any HangyeolEngine {
        if prefersMock {
            return MockEngine()
        }
        if KitRealEngine.isAvailable {
            return KitRealEngine()
        }
        return MockEngine()
    }

    /// Smoke / find-replace against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.replaceText` / `DocumentSession.replaceText`.
    static func replaceText(find: String, replace: String) throws -> Int {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.replaceMock",
                defaultValue: "찾기/바꾸기 (Mock)"
            ))
        }
        return try session.replaceText(find: find, replace: replace)
    }

    /// Smoke / list tables against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.listTables` / `DocumentSession.listTables`.
    static func listTables() throws -> [TableInfo] {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.cellMock",
                defaultValue: "표 셀 편집 (Mock)"
            ))
        }
        return try session.listTables()
    }

    /// Smoke / list images against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.listImages` / `DocumentSession.listImages`.
    static func listImages() throws -> [ImageInfo] {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.imageMock",
                defaultValue: "이미지 목록 (Mock)"
            ))
        }
        return try session.listImages()
    }

    /// Smoke / set cell text against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.setCellText` / `DocumentSession.setCellText`.
    static func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.cellMock",
                defaultValue: "표 셀 편집 (Mock)"
            ))
        }
        try session.setCellText(table: table, row: row, col: col, text: text)
    }

    /// Smoke / insert text against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.insertText` / `DocumentSession.insertText`.
    static func insertText(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        text: String
    ) throws {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.paragraphMock",
                defaultValue: "문단 편집 (Mock)"
            ))
        }
        try session.insertText(
            section: section,
            paragraph: paragraph,
            charOffset: charOffset,
            text: text
        )
    }

    /// Smoke / delete range against `current` only (tests / process probe).
    /// Documents must call `HangyeolDocument.deleteRange` / `DocumentSession.deleteRange`.
    static func deleteRange(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        count: UInt32
    ) throws {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.paragraphMock",
                defaultValue: "문단 편집 (Mock)"
            ))
        }
        try session.deleteRange(
            section: section,
            paragraph: paragraph,
            charOffset: charOffset,
            count: count
        )
    }

    static func refreshDisplayModel(type: DocumentFileType, title: String) throws -> DocumentModel {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.replaceMock",
                defaultValue: "찾기/바꾸기 (Mock)"
            ))
        }
        return try session.displayModel(type: type, title: title)
    }

    static func saveHwpx(to path: String) throws {
        guard let session = liveSession else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.saveHwpxMock",
                defaultValue: "HWPX 엔진 저장 (Mock)"
            ))
        }
        try session.saveHwpx(to: path)
    }

    private final class Holder: @unchecked Sendable {
        private let lock = NSLock()
        private var _engine: any HangyeolEngine = EngineClient.makeDefaultEngine()
        private var _forceMock = false

        var forceMock: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _forceMock
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _forceMock = newValue
            }
        }

        var engine: any HangyeolEngine {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _engine
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _engine = newValue
            }
        }
    }
}
