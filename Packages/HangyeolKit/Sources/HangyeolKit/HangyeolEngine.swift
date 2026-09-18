import Foundation

/// Kit-local file type. Mirrors `Apps/Hangyeol` `DocumentFileType` without sharing types.
/// The app imports HangyeolKit only through `KitRealEngine` (do not treat this
/// enum as the app file-type).
public enum DocumentFileType: String, Sendable, Codable, CaseIterable {
    case hwpx
    case hwp
}

/// Placeholder document payload. Not the app `DocumentModel`.
/// `RealEngine` keeps the live IR in the `hg_engine*` session; this value
/// only records the Kit `DocumentFileType` passed to `open`.
/// The app maps UTF-8 `plainText()` into Hangyeol paragraphs (`KitRealEngine`).
public struct DocumentModel: Sendable, Equatable {
    public var fileType: DocumentFileType

    public init(fileType: DocumentFileType) {
        self.fileType = fileType
    }
}

/// One table in document order (`hg_table_info`).
/// Pass `index` as `table` to `RealEngine.setCellText`. `rows` / `cols` size the grid.
/// Table UI (TableBlock views) is frontend-owned; this is ABI addressing only.
public struct TableInfo: Sendable, Equatable {
    public var index: UInt32
    public var section: UInt32
    public var paragraph: UInt32
    public var control: UInt32
    public var rows: UInt32
    public var cols: UInt32

    public init(
        index: UInt32,
        section: UInt32,
        paragraph: UInt32,
        control: UInt32,
        rows: UInt32,
        cols: UInt32
    ) {
        self.index = index
        self.section = section
        self.paragraph = paragraph
        self.control = control
        self.rows = rows
        self.cols = cols
    }
}

/// One picture in document order (`hg_image_info`).
/// `index` addresses the picture; `width`/`height` + `format` / `binDataId` / `href`
/// are size/format meta. Image UI (ImageBlock views) is frontend-owned.
/// Not a BinData extract or keep-on-save API (`docs/engine/image-meta.md`).
public struct ImageInfo: Sendable, Equatable {
    public var index: UInt32
    public var section: UInt32
    public var paragraph: UInt32
    public var control: UInt32
    public var width: UInt32
    public var height: UInt32
    public var byteLen: UInt32
    public var binDataId: UInt32
    public var format: String
    public var href: String

    public init(
        index: UInt32,
        section: UInt32,
        paragraph: UInt32,
        control: UInt32,
        width: UInt32,
        height: UInt32,
        byteLen: UInt32,
        binDataId: UInt32,
        format: String,
        href: String
    ) {
        self.index = index
        self.section = section
        self.paragraph = paragraph
        self.control = control
        self.width = width
        self.height = height
        self.byteLen = byteLen
        self.binDataId = binDataId
        self.format = format
        self.href = href
    }
}

/// Same boundary as the app `HangyeolEngine` protocol (`open` / `save`).
/// Freeze edit ABI (`hg_plain_text` / `hg_replace_text` / `hg_save_hwpx` /
/// `hg_insert_text` / `hg_delete_range` / `hg_list_tables` / `hg_set_cell_text` /
/// `hg_list_images` / `hg_render_page_svg` / `hg_last_error`) lives on `RealEngine`.
/// The app wraps this type in `KitRealEngine`; `MockEngine` remains for rollback.
public protocol HangyeolEngine: Sendable {
    func open(data: Data, type: DocumentFileType) throws -> DocumentModel
    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data
}
