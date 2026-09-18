import CHangyeolEngine
import Foundation

/// Thin FFI façade over the C stub (ABI coverage). Always throws `notLinked`
/// when the XCFramework is absent. When the real library is linked, use
/// `RealEngine` (this type does not own an `hg_engine*` session).
///
/// Product save (when the XCFramework is linked) must clear every paragraph
/// and table-cell `line_segs` before serialize (`hp:linesegarray` count 0).
/// Kit `hg_save(HWPX)` and freeze `hg_save_hwpx` are that same path.
public struct HangyeolEngineFFI: HangyeolEngine {
    public init() {}

    public func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        #if HANGYEOL_ENGINE_LINKED
        _ = data
        _ = type
        throw HangyeolKitError.unimplemented
        #else
        var engine: OpaquePointer?
        _ = data.withUnsafeBytes { raw -> hg_status in
            let bytes = raw.bindMemory(to: UInt8.self)
            return hg_open(bytes.baseAddress, bytes.count, type.hgFileType, &engine)
        }
        defer { hg_close(engine) }
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Stub only. Real `hg_save` (DocumentCore cdylib) must lineseg-clear before write.
    /// HWP (`HG_FILE_HWP`) is freeze `SAVE_REJECTED` / `HG_UNSUPPORTED` (HWPX-only write).
    public func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        #if HANGYEOL_ENGINE_LINKED
        _ = model
        _ = type
        throw HangyeolKitError.unimplemented
        #else
        _ = model
        var outBytes: UnsafeMutablePointer<UInt8>?
        var outLength = 0
        _ = withUnsafeMutablePointer(to: &outBytes) { bytesPtr in
            hg_save(nil, type.hgFileType, bytesPtr, &outLength)
        }
        hg_free_buffer(outBytes)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_plain_text`: concatenate body + table-cell paragraph text (UTF-8).
    public func plainText() throws -> Data {
        #if HANGYEOL_ENGINE_LINKED
        throw HangyeolKitError.unimplemented
        #else
        var outBytes: UnsafeMutablePointer<UInt8>?
        var outLength = 0
        _ = hg_plain_text(nil, &outBytes, &outLength)
        hg_free_buffer(outBytes)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_replace_text`: `replace_all_native` including table cells.
    public func replaceText(find: String, replace: String) throws -> Int {
        #if HANGYEOL_ENGINE_LINKED
        _ = find
        _ = replace
        throw HangyeolKitError.unimplemented
        #else
        var count = 0
        _ = find.withCString { findPtr in
            replace.withCString { replacePtr in
                hg_replace_text(nil, findPtr, replacePtr, &count)
            }
        }
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_save_hwpx`: write HWPX to a UTF-8 filesystem path.
    /// Same clear-before-save as Kit `hg_save(..., HG_FILE_HWPX, ...)`.
    public func saveHwpx(to path: String) throws {
        #if HANGYEOL_ENGINE_LINKED
        _ = path
        throw HangyeolKitError.unimplemented
        #else
        _ = path.withCString { hg_save_hwpx(nil, $0) }
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Optional freeze `hg_insert_text` at (section, paragraph, char_offset).
    public func insertText(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        text: String
    ) throws {
        #if HANGYEOL_ENGINE_LINKED
        _ = section
        _ = paragraph
        _ = charOffset
        _ = text
        throw HangyeolKitError.unimplemented
        #else
        _ = text.withCString { hg_insert_text(nil, section, paragraph, charOffset, $0) }
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Optional freeze `hg_delete_range` of `count` characters at the same index.
    public func deleteRange(
        section: UInt32,
        paragraph: UInt32,
        charOffset: UInt32,
        count: UInt32
    ) throws {
        #if HANGYEOL_ENGINE_LINKED
        _ = section
        _ = paragraph
        _ = charOffset
        _ = count
        throw HangyeolKitError.unimplemented
        #else
        _ = hg_delete_range(nil, section, paragraph, charOffset, count)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_list_tables`. Live session is `RealEngine.listTables`.
    public func listTables() throws -> [TableInfo] {
        #if HANGYEOL_ENGINE_LINKED
        throw HangyeolKitError.unimplemented
        #else
        var count = 0
        _ = hg_list_tables(nil, nil, 0, &count)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_list_images`. Live session is `RealEngine.listImages`.
    public func listImages() throws -> [ImageInfo] {
        #if HANGYEOL_ENGINE_LINKED
        throw HangyeolKitError.unimplemented
        #else
        var count = 0
        _ = hg_list_images(nil, nil, 0, &count)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_set_cell_text`. Live session is `RealEngine.setCellText`.
    public func setCellText(table: UInt32, row: UInt32, col: UInt32, text: String) throws {
        #if HANGYEOL_ENGINE_LINKED
        _ = table
        _ = row
        _ = col
        _ = text
        throw HangyeolKitError.unimplemented
        #else
        _ = text.withCString { hg_set_cell_text(nil, table, row, col, $0) }
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Read-only `hg_render_page_svg` (UTF-8 SVG, layer + Screen).
    /// Live session is `RealEngine.renderPageSvg`. Views wiring is the app.
    public func renderPageSvg(pageIndex: UInt32) throws -> Data {
        #if HANGYEOL_ENGINE_LINKED
        _ = pageIndex
        throw HangyeolKitError.unimplemented
        #else
        var outBytes: UnsafeMutablePointer<UInt8>?
        var outLength = 0
        _ = hg_render_page_svg(nil, pageIndex, &outBytes, &outLength)
        hg_free_buffer(outBytes)
        throw HangyeolKitError.notLinked
        #endif
    }

    /// Freeze `hg_last_error`: thread-local string code, or `nil` after success.
    public static func lastError() -> String? {
        HangyeolEngineSupport.lastErrorString()
    }
}
