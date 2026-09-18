import Foundation

enum HangyeolError: LocalizedError, Identifiable, Equatable {
    case emptyFile
    case sampleNotFound
    case engineFailed(String)
    case saveFailed(String)
    case bookmarkFailed(String)
    /// User-picked file that is not HWP/HWPX. Associated value is the filename.
    case unsupportedType(String)
    /// Engine freeze `UNSUPPORTED_VERSION` / `HG_UNSUPPORTED` (HWP 3.x, DRM, HML).
    /// No associated value — frontend owns ErrorSheet copy.
    case unsupported
    case notYetImplemented(String)
    /// HWP write (`hg_save(..., HG_FILE_HWP)` freeze `SAVE_REJECTED`).
    case saveRejected
    /// Engine freeze `ENCRYPTED` / `HG_PASSWORD`. Decrypt is forbidden. No associated value.
    case encrypted
    /// Engine freeze `CORRUPT` / `HG_CORRUPT` (truncated / malformed / F16 / F21). No associated value.
    case corrupt
    /// PDF export I/O or context failure. Distinct from document HWPX save.
    case exportFailed(String)
    case exportEmptyDocument
    case printEmptyDocument

    /// Posted on the main thread so DocumentWindow can bind `presentedError` / ErrorSheet.
    static let presentNotification = Notification.Name("HangyeolError.present")

    var id: String {
        switch self {
        case .emptyFile:
            return "emptyFile"
        case .sampleNotFound:
            return "sampleNotFound"
        case .engineFailed(let message):
            return "engineFailed:\(message)"
        case .saveFailed(let message):
            return "saveFailed:\(message)"
        case .bookmarkFailed(let message):
            return "bookmarkFailed:\(message)"
        case .unsupportedType(let name):
            return "unsupportedType:\(name)"
        case .unsupported:
            return "unsupported"
        case .notYetImplemented(let feature):
            return "notYetImplemented:\(feature)"
        case .saveRejected:
            return "saveRejected"
        case .encrypted:
            return "encrypted"
        case .corrupt:
            return "corrupt"
        case .exportFailed(let message):
            return "exportFailed:\(message)"
        case .exportEmptyDocument:
            return "exportEmptyDocument"
        case .printEmptyDocument:
            return "printEmptyDocument"
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return String(localized: "error.emptyFile", defaultValue: "파일이 비어 있어 열 수 없습니다.")
        case .sampleNotFound:
            return String(localized: "error.sampleNotFound", defaultValue: "샘플 문서를 찾지 못했습니다.")
        case .engineFailed(let message):
            return String(
                format: String(
                    localized: "error.engineFailed",
                    defaultValue: "문서를 열지 못했습니다. %@"
                ),
                message
            )
        case .saveFailed(let message):
            return String(
                format: String(
                    localized: "error.saveFailed",
                    defaultValue: "문서를 저장하지 못했습니다. %@"
                ),
                message
            )
        case .bookmarkFailed(let message):
            return String(
                format: String(
                    localized: "error.bookmarkFailed",
                    defaultValue: "최근 문서에 접근하지 못했습니다. %@"
                ),
                message
            )
        case .unsupportedType(let name):
            return String(
                format: String(
                    localized: "error.unsupportedType",
                    defaultValue: "‘%@’ 형식을 열 수 없습니다."
                ),
                name
            )
        case .unsupported:
            return String(
                localized: "error.unsupported",
                defaultValue: "이 문서 형식은 아직 열 수 없습니다."
            )
        case .notYetImplemented(let feature):
            return String(
                format: String(
                    localized: "error.notYetImplemented",
                    defaultValue: "%@은(는) 아직 지원하지 않습니다."
                ),
                feature
            )
        case .saveRejected:
            return String(
                localized: "error.saveRejected",
                defaultValue: "HWP로는 저장할 수 없습니다."
            )
        case .encrypted:
            return String(
                localized: "error.encrypted",
                defaultValue: "암호가 걸린 문서는 열 수 없습니다."
            )
        case .corrupt:
            return String(
                localized: "error.corrupt",
                defaultValue: "문서가 손상되어 열 수 없습니다."
            )
        case .exportFailed(let message):
            return String(
                format: String(
                    localized: "error.exportFailed",
                    defaultValue: "PDF로 보내지 못했습니다. %@"
                ),
                message
            )
        case .exportEmptyDocument:
            return String(
                localized: "error.exportEmpty",
                defaultValue: "이 창에는 보낼 본문이 없습니다."
            )
        case .printEmptyDocument:
            return String(
                localized: "error.printEmpty",
                defaultValue: "이 창에는 인쇄할 본문이 없습니다."
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyFile:
            return String(localized: "error.emptyFile.recovery", defaultValue: "다른 HWP 또는 HWPX 파일을 선택하세요.")
        case .sampleNotFound:
            return String(localized: "error.sampleNotFound.recovery", defaultValue: "앱을 다시 설치하거나 새 문서를 만드세요.")
        case .engineFailed:
            return String(localized: "error.engineFailed.recovery", defaultValue: "파일이 손상됐는지 확인한 뒤 다시 여세요.")
        case .saveFailed:
            return String(localized: "error.saveFailed.recovery", defaultValue: "저장 위치를 바꾸거나 폴더 권한을 확인한 뒤 다시 저장하세요.")
        case .bookmarkFailed:
            return String(localized: "error.bookmarkFailed.recovery", defaultValue: "파일을 다시 열어 접근 권한을 허용하세요.")
        case .unsupportedType, .unsupported:
            return String(localized: "error.unsupportedType.recovery", defaultValue: "HWP 또는 HWPX 파일을 선택하세요.")
        case .notYetImplemented:
            return String(localized: "error.notYetImplemented.recovery", defaultValue: "이후 버전에 제공할 예정입니다.")
        case .saveRejected:
            return String(
                localized: "error.saveRejected.recovery",
                defaultValue: "HWPX로 저장하세요."
            )
        case .encrypted:
            return String(
                localized: "error.encrypted.recovery",
                defaultValue: "비밀번호 해제는 지원하지 않습니다. 다른 파일을 선택하세요."
            )
        case .corrupt:
            return String(
                localized: "error.corrupt.recovery",
                defaultValue: "파일이 잘렸거나 패키지가 잘못된 건 아닌지 확인한 뒤 다시 여세요."
            )
        case .exportFailed:
            return String(
                localized: "error.exportFailed.recovery",
                defaultValue: "저장 위치를 바꾸거나 폴더 권한을 확인한 뒤 다시 보내세요."
            )
        case .exportEmptyDocument:
            return String(
                localized: "error.exportEmpty.recovery",
                defaultValue: "파일을 열거나 샘플 문서를 여세요."
            )
        case .printEmptyDocument:
            return String(
                localized: "error.printEmpty.recovery",
                defaultValue: "파일을 열거나 샘플 문서를 여세요."
            )
        }
    }

    /// Map engine/kit failures from open. Dedicated freeze cases, not `engineFailed` mush.
    static func mapOpenFailure(_ error: Error) -> HangyeolError {
        if let hangyeol = error as? HangyeolError {
            return hangyeol
        }
        return KitRealEngine.mapError(error)
    }

    /// Map engine/kit failures from save. Dedicated freeze cases stay distinct.
    static func mapSaveFailure(_ error: Error) -> HangyeolError {
        let hangyeol: HangyeolError
        if let typed = error as? HangyeolError {
            hangyeol = typed
        } else {
            hangyeol = KitRealEngine.mapError(error)
        }
        switch hangyeol {
        case .saveRejected, .saveFailed, .notYetImplemented, .exportFailed,
             .encrypted, .corrupt, .unsupported, .unsupportedType:
            return hangyeol
        case .engineFailed(let message):
            return .saveFailed(message)
        default:
            return .saveFailed(hangyeol.localizedDescription)
        }
    }
}

/// Byte probes so Mock never fake-succeeds Kit freeze failures (F16/F21/ENCRYPTED).
enum HangyeolOpenBytes {
    static let encryptedMarker = Data("HANGYEOL_ENCRYPTED".utf8)
    static let unsupportedMarker = Data("HANGYEOL_UNSUPPORTED".utf8)

    private static let zipLocal = Data([0x50, 0x4B, 0x03, 0x04])
    private static let zipEOCD = Data([0x50, 0x4B, 0x05, 0x06])
    private static let oleMagic = Data([0xD0, 0xCF, 0x11, 0xE0])

    /// `nil` means Mock may continue (JSON snapshot or sample preview).
    static func mockFailure(for data: Data) -> HangyeolError? {
        if data.starts(with: encryptedMarker) {
            return .encrypted
        }
        if data.starts(with: unsupportedMarker) {
            return .unsupported
        }
        if looksLikeCorruptContainer(data) {
            return .corrupt
        }
        return nil
    }

    /// ZIP (HWPX) or OLE (HWP) bytes. Mock must not decode these as a welcome preview.
    static func looksLikeNativeDocumentContainer(_ data: Data) -> Bool {
        data.starts(with: zipLocal) || data.starts(with: oleMagic)
    }

    /// Truncated ZIP (F16, no EOCD) or HWPX packaging break (F21: mimetype not first/STORE).
    static func looksLikeCorruptContainer(_ data: Data) -> Bool {
        guard data.starts(with: zipLocal) else { return false }
        guard data.count >= 30 else { return true }
        let method = uint16LE(data, offset: 8)
        let nameLen = Int(uint16LE(data, offset: 26))
        guard data.count >= 30 + nameLen else { return true }
        let nameData = data.subdata(in: 30..<(30 + nameLen))
        let name = String(data: nameData, encoding: .utf8) ?? ""
        let hasEOCD = data.range(of: zipEOCD) != nil
        if name != "mimetype" || method != 0 || !hasEOCD {
            return true
        }
        return false
    }

    private static func uint16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}
