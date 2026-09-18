import CHangyeolEngine
import Foundation

/// Live Hangyeol engine session over `hg_*`.
///
/// Owns one `hg_engine*` from `hg_open` until `close()` / `deinit`.
/// When `HangyeolEngine.xcframework` is linked (`HANGYEOL_ENGINE_LINKED`),
/// calls go to the real DocumentCore cdylib and errors map through
/// `hg_status` + `hg_last_error` (never `notLinked`).
/// When the XCFramework is absent, the C stub is compiled and methods throw
/// `HangyeolKitError.notLinked`.
///
/// `hg_save(HWPX)` / `hg_save_hwpx` are the engine's clear-before-save path
/// (`line_segs` cleared; `hp:linesegarray` count 0). HWP write is
/// `SAVE_REJECTED` / `HG_UNSUPPORTED`.
///
/// Apps/Hangyeol uses this type only through `KitRealEngine` (app DocumentModel
/// is a different type). MockEngine stays available for rollback.
public final class RealEngine: HangyeolEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var session: OpaquePointer?

    /// `true` when Package.swift found the XCFramework and defined `HANGYEOL_ENGINE_LINKED`.
    public static var isLinked: Bool { HangyeolEngineSupport.isLinked }

    public init() {}

    deinit {
        lock.lock()
        closeUnlocked()
        lock.unlock()
    }

    /// Release the current `hg_engine*` session. NULL/`close` twice is a no-op.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        closeUnlocked()
    }

    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != nil
    }

    /// `hg_open`. Format is detected from **bytes** (F14); `type` is Kit ABI only.
    /// A previous session is `hg_close`d first.
    public func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        lock.lock()
        defer { lock.unlock() }
        closeUnlocked()
        var out: OpaquePointer?
        let status = data.withUnsafeBytes { raw -> hg_status in
            let bytes = raw.bindMemory(to: UInt8.self)
            return hg_open(bytes.baseAddress, bytes.count, type.hgFileType, &out)
        }
        try HangyeolEngineSupport.throwIfNeeded(status)
        session = out
        if session == nil && HangyeolEngineSupport.isLinked {
            throw HangyeolKitError.status(.corrupt, freeze: .corrupt)
        }
        return DocumentModel(fileType: type)
    }

    /// `hg_save` then `hg_free_buffer`. HWPX: engine clear-before-save.
    /// HWP: freeze `SAVE_REJECTED` / `HG_UNSUPPORTED`.
    public func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        _ = model
        return try withSession { engine in
            var outBytes: UnsafeMutablePointer<UInt8>?
            var outLength = 0
            let status = withUnsafeMutablePointer(to: &outBytes) { bytesPtr in
                hg_save(engine, type.hgFileType, bytesPtr, &outLength)
            }
            return try HangyeolEngineSupport.takeBuffer(
                status: status,
                bytes: outBytes,
                length: outLength
            )
        }
    }

    /// Freeze `hg_plain_text`: concatenate body + table-cell paragraph text (UTF-8).
    public func plainText() throws -> Data {
        try withSession { engine in
            var outBytes: UnsafeMutablePointer<UInt8>?
            var outLength = 0
            let status = withUnsafeMutablePointer(to: &outBytes) { bytesPtr in
                hg_plain_text(engine, bytesPtr, &outLength)
            }
            return try HangyeolEngineSupport.takeBuffer(
                status: status,
                bytes: outBytes,
                length: outLength
            )
        }
    }

    /// Freeze `hg_replace_text`: `replace_all_native` including table cells.
    public func replaceText(find: String, replace: String) throws -> Int {
        try withSession { engine in
            var count = 0
            let status = find.withCString { findPtr in
                replace.withCString { replacePtr in
                    hg_replace_text(engine, findPtr, replacePtr, &count)
                }
            }
            try HangyeolEngineSupport.throwIfNeeded(status)
            return count
        }
    }

    /// Freeze `hg_save_hwpx`: write HWPX to a UTF-8 filesystem path.
    /// Same clear-before-save as Kit `hg_save(..., HG_FILE_HWPX, ...)`.
    public func saveHwpx(to path: String) throws {
        try withSession { engine in
            let status = path.withCString { hg_save_hwpx(engine, $0) }
            try HangyeolEngineSupport.throwIfNeeded(status)
        }
    }

    /// Optional freeze `hg_insert_text` at (section, paragraph, char_offset).
    public func insertText(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        text: String
    ) throws {
        try withSession { engine in
            let status = text.withCString {
                hg_insert_text(engine, section, paragraph, charOffset, $0)
            }
            try HangyeolEngineSupport.throwIfNeeded(status)
        }
    }

    /// Optional freeze `hg_delete_range` of `count` characters at the same index.
    public func deleteRange(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        count: UInt32
    ) throws {
        try withSession { engine in
            let status = hg_delete_range(engine, section, paragraph, charOffset, count)
            try HangyeolEngineSupport.throwIfNeeded(status)
        }
    }

    /// Freeze `hg_list_tables`: document-order tables (`index` / `rows` / `cols`).
    /// Live when linked; `notLinked` when the C stub is compiled in.
    /// Invalid session maps through existing freeze ↔ Kit rules.
    public func listTables() throws -> [TableInfo] {
        try withSession { engine in
            var total = 0
            let countStatus = hg_list_tables(engine, nil, 0, &total)
            try HangyeolEngineSupport.throwIfNeeded(countStatus)
            guard total > 0 else { return [] }

            var tables = [hg_table_info](
                repeating: hg_table_info(
                    index: 0,
                    section: 0,
                    paragraph: 0,
                    control: 0,
                    rows: 0,
                    cols: 0
                ),
                count: total
            )
            var writtenTotal = 0
            let status = tables.withUnsafeMutableBufferPointer { buf in
                hg_list_tables(engine, buf.baseAddress, buf.count, &writtenTotal)
            }
            try HangyeolEngineSupport.throwIfNeeded(status)
            let n = min(writtenTotal, tables.count)
            return tables.prefix(n).map(TableInfo.init)
        }
    }

    /// Freeze `hg_list_images`: document-order pictures (`index` + size/format meta).
    /// Live when linked; `notLinked` when the C stub is compiled in.
    /// IR metadata only — not a BinData extract API (`docs/engine/image-meta.md`).
    public func listImages() throws -> [ImageInfo] {
        try withSession { engine in
            var total = 0
            let countStatus = hg_list_images(engine, nil, 0, &total)
            try HangyeolEngineSupport.throwIfNeeded(countStatus)
            guard total > 0 else { return [] }

            var images = [hg_image_info](
                repeating: HangyeolEngineSupport.zeroedCStruct(),
                count: total
            )
            var writtenTotal = 0
            let status = images.withUnsafeMutableBufferPointer { buf in
                hg_list_images(engine, buf.baseAddress, buf.count, &writtenTotal)
            }
            try HangyeolEngineSupport.throwIfNeeded(status)
            let n = min(writtenTotal, images.count)
            return images.prefix(n).map(ImageInfo.init)
        }
    }

    /// Freeze `hg_set_cell_text` at (`table`, `row`, `col`).
    /// `table` is `TableInfo.index` from `listTables`.
    /// Live when linked; `notLinked` when the C stub is compiled in.
    /// Invalid table/row/col is engine `HG_CORRUPT` / `CORRUPT` (existing mapping).
    public func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        try withSession { engine in
            let status = text.withCString {
                hg_set_cell_text(engine, table, row, col, $0)
            }
            try HangyeolEngineSupport.throwIfNeeded(status)
        }
    }

    /// Read-only page preview: UTF-8 SVG via `hg_render_page_svg`
    /// (layer + `RenderProfile::Screen`). Does not mutate IR for save.
    /// Out-of-range page is engine `HG_CORRUPT` / `CORRUPT`.
    /// Live when linked; `notLinked` when the C stub is compiled in.
    /// App `KitRealEngine` / `NativePageRaster` call this on the same `hg_engine*`.
    public func renderPageSvg(pageIndex: UInt32) throws -> Data {
        try withSession { engine in
            var outBytes: UnsafeMutablePointer<UInt8>?
            var outLength = 0
            let status = withUnsafeMutablePointer(to: &outBytes) { bytesPtr in
                hg_render_page_svg(engine, pageIndex, bytesPtr, &outLength)
            }
            return try HangyeolEngineSupport.takeBuffer(
                status: status,
                bytes: outBytes,
                length: outLength
            )
        }
    }

    /// Freeze `hg_last_error` for the last failed call on this thread, or `nil` after success.
    public func lastError() -> String? {
        HangyeolEngineSupport.lastErrorString()
    }

    public static func lastError() -> String? {
        HangyeolEngineSupport.lastErrorString()
    }

    private func closeUnlocked() {
        hg_close(session)
        session = nil
    }

    private func withSession<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(session)
    }
}
