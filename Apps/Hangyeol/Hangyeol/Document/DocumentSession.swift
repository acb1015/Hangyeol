import Combine
import Foundation

/// One engine instance bound to a single open document/window for its lifetime.
///
/// `HangyeolDocument` is a FileDocument value (copied by DocumentGroup). This
/// class is the identity of that copy-set: two windows each own a session, so
/// `KitRealEngine` / `hg_engine*` is not the process-wide `EngineClient.current`
/// singleton (PR #16 clobber).
///
/// Frontend: observe `lastSaveError` / `lastOpenError` (or catch throws) to
/// present sheets. This type does not present UI.
///
/// Session edits (`replaceText` / `setCellText` / `insertText` / `deleteRange`)
/// register inverses on the window `UndoManager` after a **successful** live
/// mutation. Attach it with `attachUndoManager` (DocumentGroup environment /
/// Edit → Undo/Redo). Mock throws `notYetImplemented` and never registers.
final class DocumentSession: ObservableObject, Identifiable, @unchecked Sendable {
    let id: UUID

    private let lock = NSLock()
    private var engine: any HangyeolEngine
    private weak var boundUndoManager: UndoManager?
    private var undoBaselineDelta = 0

    /// Last mapped save failure. Cleared on the next successful save.
    @Published private(set) var lastSaveError: HangyeolError?
    /// Last mapped open failure. Cleared on the next successful open.
    @Published private(set) var lastOpenError: HangyeolError?
    /// Bumped after UndoManager undo/redo so the FileDocument display model can refresh.
    @Published private(set) var undoGeneration: UInt64 = 0

    init(engine: any HangyeolEngine = EngineClient.makeEngine()) {
        self.id = UUID()
        self.engine = engine
    }

    deinit {
        boundUndoManager?.removeAllActions(withTarget: self)
    }

    /// Window / FileDocument `UndoManager` (`@Environment(\.undoManager)`).
    /// Standard Edit → Undo/Redo talks to this object; session APIs register automatically.
    var undoManager: UndoManager? { boundUndoManager }

    /// True when live edits have been registered and not fully undone (relative to open/save).
    var hasUndoableEdits: Bool { undoBaselineDelta != 0 }

    func attachUndoManager(_ undoManager: UndoManager?) {
        if boundUndoManager !== undoManager {
            boundUndoManager?.removeAllActions(withTarget: self)
            boundUndoManager = undoManager
        }
    }

    var isUsingMock: Bool {
        lock.lock()
        defer { lock.unlock() }
        return engine is MockEngine
    }

    var liveSession: (any HangyeolLiveSession)? {
        lock.lock()
        defer { lock.unlock() }
        return engine as? any HangyeolLiveSession
    }

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let live = engine as? any HangyeolLiveSession {
            return live.isOpen
        }
        return engine is MockEngine
    }

    /// Real session with an open `hg_engine*` (find/replace / live HWPX save).
    var canReplace: Bool {
        lock.lock()
        defer { lock.unlock() }
        return (engine as? any HangyeolLiveSession)?.isOpen == true
    }

    /// Shared live-edit gate: open Real session only (Mock / closed → false).
    var canEdit: Bool { canReplace }

    /// Real session with an open `hg_engine*` (table cell list/edit).
    var canEditCells: Bool { canEdit }

    /// Real session with an open `hg_engine*` (read-only `listImages`).
    var canListImages: Bool { canEdit }

    /// Real session with an open `hg_engine*` (paragraph `insertText` / `deleteRange`).
    var canEditParagraphs: Bool { canEdit }

    /// Open Real session only (`KitRealEngine` / live double). Mock / closed → false.
    /// Page preview must use this session's `hg_engine*`, never `EngineClient.current`.
    var canRenderPagePreview: Bool { canEdit }

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        do {
            lastOpenError = nil
            let model = try withEngine { engine in
                try engine.open(data: data, type: type)
            }
            clearUndoHistory()
            return model
        } catch let error as HangyeolError {
            lastOpenError = error
            throw error
        } catch {
            let mapped = HangyeolError.mapOpenFailure(error)
            lastOpenError = mapped
            throw mapped
        }
    }

    /// Persist this session's IR (Real) or Mock JSON. Never uses `EngineClient.current`.
    /// HWP write is always `saveRejected` (engine freeze SAVE_REJECTED).
    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        if type == .hwp {
            let error = HangyeolError.saveRejected
            lastSaveError = error
            throw error
        }
        do {
            lastSaveError = nil
            let data = try withEngine { engine -> Data in
                if let live = engine as? any HangyeolLiveSession, !live.isOpen {
                    // Untitled Real has no DocumentCore IR. Do not write Mock
                    // JSON under a .hwpx name (looks like Real success on reopen).
                    throw HangyeolError.saveFailed(String(
                        localized: "error.engine.untitledRealSave",
                        defaultValue: "엔진 세션이 없는 새 문서는 HWPX로 저장할 수 없습니다."
                    ))
                }
                return try engine.save(model, as: type)
            }
            undoBaselineDelta = 0
            return data
        } catch {
            let mapped = HangyeolError.mapSaveFailure(error)
            lastSaveError = mapped
            throw mapped
        }
    }

    func replaceText(find: String, replace: String) throws -> Int {
        guard let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.replaceMock",
                defaultValue: "찾기/바꾸기 (Mock)"
            ))
        }
        let snapshot = boundUndoManager == nil ? nil : try? session.captureUndoState()
        let count = try session.replaceText(find: find, replace: replace)
        if count > 0, let snapshot {
            registerUndoPair(
                undo: .restoreSnapshot(snapshot),
                redo: .replaceText(find: find, replace: replace)
            )
        }
        return count
    }

    func listTables() throws -> [TableInfo] {
        try requireOpenLiveSessionForCells().listTables()
    }

    func listImages() throws -> [ImageInfo] {
        try requireOpenLiveSessionForImages().listImages()
    }

    /// UTF-8 SVG for `pageIndex` on **this** session's engine. Never `EngineClient.current`.
    func renderPageSvg(pageIndex: UInt32) throws -> Data {
        try requireOpenLiveSessionForPagePreview().renderPageSvg(pageIndex: pageIndex)
    }

    func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        let session = try requireOpenLiveSessionForCells()
        let previous = boundUndoManager == nil ? nil : try? session.cellText(table: table, row: row, col: col)
        let snapshot = previous == nil && boundUndoManager != nil
            ? try? session.captureUndoState()
            : nil
        try session.setCellText(table: table, row: row, col: col, text: text)
        if let previous {
            registerUndoPair(
                undo: .setCellText(table: table, row: row, col: col, text: previous),
                redo: .setCellText(table: table, row: row, col: col, text: text)
            )
        } else if let snapshot {
            registerUndoPair(
                undo: .restoreSnapshot(snapshot),
                redo: .setCellText(table: table, row: row, col: col, text: text)
            )
        }
    }

    func insertText(section: UInt32, paragraph: UInt32, charOffset: UInt32, text: String) throws {
        try requireOpenLiveSessionForParagraphs().insertText(
            section: section,
            paragraph: paragraph,
            charOffset: charOffset,
            text: text
        )
        let count = UInt32(clamping: text.unicodeScalars.count)
        registerUndoPair(
            undo: .deleteRange(section: section, paragraph: paragraph, charOffset: charOffset, count: count),
            redo: .insertText(section: section, paragraph: paragraph, charOffset: charOffset, text: text)
        )
    }

    func deleteRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32) throws {
        let session = try requireOpenLiveSessionForParagraphs()
        let deleted = boundUndoManager == nil
            ? nil
            : try? session.textInRange(
                section: section,
                paragraph: paragraph,
                charOffset: charOffset,
                count: count
            )
        let snapshot = deleted == nil && boundUndoManager != nil
            ? try? session.captureUndoState()
            : nil
        try session.deleteRange(
            section: section,
            paragraph: paragraph,
            charOffset: charOffset,
            count: count
        )
        if let deleted {
            registerUndoPair(
                undo: .insertText(
                    section: section,
                    paragraph: paragraph,
                    charOffset: charOffset,
                    text: deleted
                ),
                redo: .deleteRange(
                    section: section,
                    paragraph: paragraph,
                    charOffset: charOffset,
                    count: count
                )
            )
        } else if let snapshot {
            registerUndoPair(
                undo: .restoreSnapshot(snapshot),
                redo: .deleteRange(
                    section: section,
                    paragraph: paragraph,
                    charOffset: charOffset,
                    count: count
                )
            )
        }
    }

    func displayModel(type: DocumentFileType, title: String) throws -> DocumentModel {
        guard let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.replaceMock",
                defaultValue: "찾기/바꾸기 (Mock)"
            ))
        }
        return try session.displayModel(type: type, title: title)
    }

    func saveHwpx(to path: String) throws {
        guard let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.saveHwpxMock",
                defaultValue: "HWPX 엔진 저장 (Mock)"
            ))
        }
        do {
            lastSaveError = nil
            try session.saveHwpx(to: path)
        } catch let error as HangyeolError {
            let mapped = HangyeolError.mapSaveFailure(error)
            lastSaveError = mapped
            throw mapped
        } catch {
            let mapped = HangyeolError.mapSaveFailure(error)
            lastSaveError = mapped
            throw mapped
        }
    }

    private enum SessionUndoAction {
        case insertText(section: UInt32, paragraph: UInt32, charOffset: UInt32, text: String)
        case deleteRange(section: UInt32, paragraph: UInt32, charOffset: UInt32, count: UInt32)
        case setCellText(table: UInt32, row: UInt32, col: UInt32, text: String)
        case replaceText(find: String, replace: String)
        case restoreSnapshot(Data)
    }

    private func apply(_ action: SessionUndoAction, on live: any HangyeolLiveSession) throws {
        switch action {
        case .insertText(let section, let paragraph, let charOffset, let text):
            try live.insertText(
                section: section,
                paragraph: paragraph,
                charOffset: charOffset,
                text: text
            )
        case .deleteRange(let section, let paragraph, let charOffset, let count):
            try live.deleteRange(
                section: section,
                paragraph: paragraph,
                charOffset: charOffset,
                count: count
            )
        case .setCellText(let table, let row, let col, let text):
            try live.setCellText(table: table, row: row, col: col, text: text)
        case .replaceText(let find, let replace):
            _ = try live.replaceText(find: find, replace: replace)
        case .restoreSnapshot(let data):
            try live.restoreUndoState(data)
        }
    }

    private func registerUndoPair(undo: SessionUndoAction, redo: SessionUndoAction) {
        guard let undoManager = boundUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.performUndoPair(undo: undo, redo: redo)
        }
        if !undoManager.isUndoing && !undoManager.isRedoing {
            undoBaselineDelta += 1
            undoManager.setActionName(String(
                localized: "undo.sessionEdit",
                defaultValue: "편집"
            ))
        }
    }

    private func performUndoPair(undo: SessionUndoAction, redo: SessionUndoAction) {
        guard let live = liveSession, live.isOpen else { return }
        do {
            try apply(undo, on: live)
        } catch {
            return
        }
        if boundUndoManager?.isUndoing == true {
            undoBaselineDelta -= 1
        } else {
            undoBaselineDelta += 1
        }
        registerUndoPair(undo: redo, redo: undo)
        undoGeneration += 1
    }

    private func clearUndoHistory() {
        boundUndoManager?.removeAllActions(withTarget: self)
        undoBaselineDelta = 0
    }

    private func requireOpenLiveSessionForCells() throws -> any HangyeolLiveSession {
        guard canEdit, let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.cellMock",
                defaultValue: "표 셀 편집 (Mock)"
            ))
        }
        return session
    }

    private func requireOpenLiveSessionForImages() throws -> any HangyeolLiveSession {
        guard canListImages, let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.imageMock",
                defaultValue: "이미지 목록 (Mock)"
            ))
        }
        return session
    }

    private func requireOpenLiveSessionForParagraphs() throws -> any HangyeolLiveSession {
        guard canEdit, let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.paragraphMock",
                defaultValue: "문단 편집 (Mock)"
            ))
        }
        return session
    }

    private func requireOpenLiveSessionForPagePreview() throws -> any HangyeolLiveSession {
        guard canRenderPagePreview, let session = liveSession, session.isOpen else {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.pagePreview",
                defaultValue: "페이지 미리보기"
            ))
        }
        return session
    }

    private func withEngine<T>(_ body: (any HangyeolEngine) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(engine)
    }

}
