import Foundation
import UniformTypeIdentifiers

enum DocumentFileType: String, Codable, Sendable, CaseIterable {
    case hwpx
    case hwp

    var typeIdentifier: String {
        switch self {
        case .hwpx: return "org.hangyeol.hwpx"
        case .hwp: return "org.hangyeol.hwp"
        }
    }

    init?(typeIdentifier: String) {
        switch typeIdentifier {
        case "org.hangyeol.hwpx":
            self = .hwpx
        case "org.hangyeol.hwp":
            self = .hwp
        default:
            if UTType.hangyeolImportedIdentifier(
                typeIdentifier,
                matches: UTType.hangyeolImportedHwpxIdentifiers
            ) {
                self = .hwpx
            } else if UTType.hangyeolImportedIdentifier(
                typeIdentifier,
                matches: UTType.hangyeolImportedHwpIdentifiers
            ) {
                self = .hwp
            } else {
                return nil
            }
        }
    }

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "hwpx":
            self = .hwpx
        case "hwp":
            self = .hwp
        default:
            return nil
        }
    }
}

struct DocumentMetadata: Codable, Equatable, Sendable {
    var title: String
    var sourceType: DocumentFileType
    /// MockEngine JSON snapshot only. Never means a Real HWP/HWPX parse succeeded.
    var isMockPreview: Bool

    init(title: String, sourceType: DocumentFileType, isMockPreview: Bool = false) {
        self.title = title
        self.sourceType = sourceType
        self.isMockPreview = isMockPreview
    }

    enum CodingKeys: String, CodingKey {
        case title
        case sourceType
        case isMockPreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        sourceType = try container.decode(DocumentFileType.self, forKey: .sourceType)
        isMockPreview = try container.decodeIfPresent(Bool.self, forKey: .isMockPreview) ?? false
    }
}

struct TextRun: Codable, Equatable, Sendable {
    var text: String
    var isBold: Bool
    var isItalic: Bool

    init(text: String, isBold: Bool = false, isItalic: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

struct ParagraphBlock: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var runs: [TextRun]

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.runs = [TextRun(text: text)]
    }

    init(id: UUID = UUID(), runs: [TextRun]) {
        self.id = id
        self.runs = runs
    }

    var plainText: String {
        runs.map(\.text).joined()
    }
}

struct TableCell: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var isHeader: Bool

    init(id: UUID = UUID(), text: String, isHeader: Bool = false) {
        self.id = id
        self.text = text
        self.isHeader = isHeader
    }
}

struct TableRow: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var cells: [TableCell]

    init(id: UUID = UUID(), cells: [TableCell]) {
        self.id = id
        self.cells = cells
    }
}

struct TableBlock: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var columnCount: Int
    var rows: [TableRow]

    init(id: UUID = UUID(), columnCount: Int, rows: [TableRow]) {
        self.id = id
        self.columnCount = columnCount
        self.rows = rows
    }

    init(id: UUID = UUID(), headers: [String], body: [[String]]) {
        self.id = id
        self.columnCount = headers.count
        let headerRow = TableRow(
            cells: headers.map { TableCell(text: $0, isHeader: true) }
        )
        let bodyRows = body.map { row in
            TableRow(cells: row.map { TableCell(text: $0) })
        }
        self.rows = [headerRow] + bodyRows
    }
}

enum ContentBlock: Codable, Equatable, Identifiable, Sendable {
    case paragraph(ParagraphBlock)
    case table(TableBlock)

    var id: UUID {
        switch self {
        case .paragraph(let paragraph):
            return paragraph.id
        case .table(let table):
            return table.id
        }
    }
}

struct DocumentModel: Codable, Equatable, Sendable {
    var metadata: DocumentMetadata
    var blocks: [ContentBlock]

    static let empty = DocumentModel(
        metadata: DocumentMetadata(title: "", sourceType: .hwpx),
        blocks: []
    )

    var isEmpty: Bool {
        blocks.isEmpty
    }

    var displayTitle: String {
        let trimmed = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.untitled : trimmed
    }

    var plainText: String {
        blocks.map { block in
            switch block {
            case .paragraph(let paragraph):
                return paragraph.plainText
            case .table(let table):
                return table.rows
                    .map { row in row.cells.map(\.text).joined(separator: "\t") }
                    .joined(separator: "\n")
            }
        }
        .joined(separator: "\n\n")
    }
}
