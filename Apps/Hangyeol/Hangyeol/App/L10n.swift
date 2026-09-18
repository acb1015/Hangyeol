import Foundation

enum L10n {
    static let appName = String(localized: "app.name", defaultValue: "한결")
    static let appTagline = String(localized: "app.tagline", defaultValue: "한글 문서를 열고 본문과 표를 확인하세요.")
    static let untitled = String(localized: "document.untitled", defaultValue: "제목 없음")

    static let newDocument = String(localized: "action.newDocument", defaultValue: "새 문서")
    static let open = String(localized: "action.open", defaultValue: "열기…")
    static let openPrompt = String(localized: "action.openPrompt", defaultValue: "열기")
    static let openPanelMessage = String(
        localized: "action.openPanelMessage",
        defaultValue: "HWP 또는 HWPX 문서를 선택하세요."
    )
    static let openSample = String(localized: "action.openSample", defaultValue: "샘플 문서 열기")
    static let openDocument = String(localized: "action.openDocument", defaultValue: "문서 열기…")
    static let clearRecents = String(localized: "action.clearRecents", defaultValue: "최근 항목 지우기")
    static let dropToOpen = String(localized: "action.dropToOpen", defaultValue: "놓아서 열기")
    static let exportPDF = String(localized: "action.exportPDF", defaultValue: "PDF로 보내기…")
    static let exportPDFConfirm = String(localized: "action.exportPDFConfirm", defaultValue: "PDF로 보내기")
    static let printDocument = String(localized: "action.print", defaultValue: "인쇄…")
    static let find = String(localized: "action.find", defaultValue: "찾기…")
    static let findPlaceholder = String(localized: "find.query", defaultValue: "찾기")
    static let replacePlaceholder = String(localized: "find.replace", defaultValue: "바꾸기")
    static let findNext = String(localized: "find.next", defaultValue: "다음 찾기")
    static let replace = String(localized: "find.replaceAction", defaultValue: "모두 바꾸기")
    static let close = String(localized: "action.close", defaultValue: "닫기")
    static let ok = String(localized: "action.ok", defaultValue: "확인")
    static let retry = String(localized: "action.retry", defaultValue: "다시 시도")
    static let retrySave = String(localized: "action.retrySave", defaultValue: "다시 저장")
    static let retryOpen = String(localized: "action.retryOpen", defaultValue: "다시 열기")
    static let cancel = String(localized: "action.cancel", defaultValue: "취소")
    static let edited = String(localized: "chrome.edited", defaultValue: "편집됨")

    static let help = String(localized: "menu.help", defaultValue: "한결 도움말")
    static let about = String(localized: "menu.about", defaultValue: "한결 정보")
    static let fileMenuHint = String(localized: "menu.fileHint", defaultValue: "파일")
    static let editMenuHint = String(localized: "menu.editHint", defaultValue: "편집")

    static let errorTitle = String(localized: "sheet.error.title", defaultValue: "작업을 완료하지 못했습니다")
    static let saveFailureTitle = String(localized: "sheet.saveFailure.title", defaultValue: "문서를 저장하지 못했습니다")
    static let exportFailureTitle = String(localized: "sheet.exportFailure.title", defaultValue: "PDF로 보내지 못했습니다")
    static let printFailureTitle = String(localized: "sheet.printFailure.title", defaultValue: "인쇄하지 못했습니다")
    static let reopenFailureTitle = String(localized: "sheet.reopenFailure.title", defaultValue: "최근 문서를 다시 열지 못했습니다")
    static let recents = String(localized: "empty.recents", defaultValue: "최근 문서")
    static let recentsEmpty = String(
        localized: "empty.recentsNone",
        defaultValue: "최근에 연 문서가 없습니다. 문서를 열면 여기에 나타납니다."
    )
    static let recentsOpenHint = String(localized: "empty.recentsOpenHint", defaultValue: "이 최근 문서를 엽니다.")
    static let openSampleHint = String(
        localized: "empty.openSampleHint",
        defaultValue: "앱에 들어 있는 샘플 문서를 엽니다."
    )
    static let openDocumentHint = String(
        localized: "empty.openDocumentHint",
        defaultValue: "HWP 또는 HWPX 파일을 고릅니다."
    )
    static let week1Note = String(
        localized: "empty.week1",
        defaultValue: "HWP 또는 HWPX 파일을 열거나 이 창에 놓으세요."
    )
    static let errorNextAction = String(localized: "sheet.error.nextAction", defaultValue: "다음 조치")
    static let errorEmptyFileTitle = String(
        localized: "sheet.error.emptyFile.title",
        defaultValue: "빈 파일은 열 수 없습니다"
    )
    static let errorUnsupportedTypeTitle = String(
        localized: "sheet.error.unsupportedType.title",
        defaultValue: "선택한 파일은 열 수 없습니다"
    )
    static let errorUnsupportedTypeRecovery = String(
        localized: "error.unsupportedType.recovery",
        defaultValue: "HWP 또는 HWPX 파일을 선택하세요."
    )
    static let errorUnsupportedTitle = String(
        localized: "sheet.error.unsupported.title",
        defaultValue: "이 문서 형식은 열 수 없습니다"
    )
    static let errorUnsupportedCause = String(
        localized: "sheet.error.unsupported.cause",
        defaultValue: "이 버전이나 보호된 형식은 아직 열 수 없습니다."
    )
    static let errorUnsupportedRecovery = String(
        localized: "sheet.error.unsupported.recovery",
        defaultValue: "HWP 또는 HWPX 파일을 선택하세요."
    )
    static let errorEngineFailedTitle = String(
        localized: "sheet.error.engineFailed.title",
        defaultValue: "문서를 열지 못했습니다"
    )
    static let errorCorruptTitle = String(
        localized: "sheet.error.corrupt.title",
        defaultValue: "손상된 파일은 열 수 없습니다"
    )
    static let errorCorruptCause = String(
        localized: "sheet.error.corrupt.cause",
        defaultValue: "파일이 손상되었거나 형식이 올바르지 않습니다."
    )
    static let errorCorruptRecovery = String(
        localized: "sheet.error.corrupt.recovery",
        defaultValue: "다른 파일을 고르거나 원본을 다시 받으세요."
    )
    static let errorEncryptedTitle = String(
        localized: "sheet.error.encrypted.title",
        defaultValue: "암호 문서는 열 수 없습니다"
    )
    static let errorEncryptedCause = String(
        localized: "sheet.error.encrypted.cause",
        defaultValue: "이 파일은 암호로 보호되어 있습니다."
    )
    static let errorEncryptedRecovery = String(
        localized: "sheet.error.encrypted.recovery",
        defaultValue: "비밀번호 해제는 지원하지 않습니다. 다른 파일을 선택하세요."
    )
    static let errorSaveRejectedTitle = String(
        localized: "sheet.error.saveRejected.title",
        defaultValue: "HWP로는 저장할 수 없습니다"
    )
    static let errorSaveRejectedCause = String(
        localized: "sheet.error.saveRejected.cause",
        defaultValue: "이 파일은 HWP로 다시 저장할 수 없습니다."
    )
    static let errorSaveRejectedRecovery = String(
        localized: "sheet.error.saveRejected.recovery",
        defaultValue: "다른 이름으로 HWPX 파일을 저장하세요."
    )
    static let saveFailureRetryHint = String(
        localized: "sheet.saveFailure.retryHint",
        defaultValue: "같은 위치에 다시 저장합니다."
    )
    static let exportFailureRetryHint = String(
        localized: "sheet.exportFailure.retryHint",
        defaultValue: "같은 위치에 다시 보냅니다."
    )
    static let exportEmptyRetryHint = String(
        localized: "sheet.exportEmpty.retryHint",
        defaultValue: "문서를 연 뒤 다시 보냅니다."
    )
    static let printEmptyRetryHint = String(
        localized: "sheet.printEmpty.retryHint",
        defaultValue: "문서를 연 뒤 다시 인쇄합니다."
    )
    static let exportPDFMessage = String(
        localized: "export.pdf.message",
        defaultValue: "본문을 PDF 파일로 보냅니다."
    )
    static let exportProgressStatus = String(
        localized: "export.progress.status",
        defaultValue: "본문을 PDF로 보내는 중"
    )
    static let exportEmptyHint = String(
        localized: "export.empty.hint",
        defaultValue: "보낼 본문이 없습니다. 파일을 열거나 샘플 문서를 여세요."
    )
    static let printEmptyHint = String(
        localized: "print.empty.hint",
        defaultValue: "인쇄할 본문이 없습니다. 파일을 열거나 샘플 문서를 여세요."
    )

    static func exportProgressA11y(filename: String, status: String) -> String {
        "\(filename), \(status)"
    }
    static let reopenRetryHint = String(
        localized: "sheet.reopenFailure.retryHint",
        defaultValue: "최근 문서를 다시 엽니다."
    )
    static let findStubNote = String(
        localized: "find.stub",
        defaultValue: "이 문서에서는 찾기/바꾸기를 쓸 수 없습니다."
    )
    static let findLiveNote = String(
        localized: "find.live",
        defaultValue: "바꾸기는 이 문서의 열린 세션(표 셀 포함)에 적용됩니다. 허브-A 스모크: 1 → HGPOC99 후 HWPX 저장."
    )

    static func replacedCount(_ count: Int) -> String {
        if count == 0 {
            return String(localized: "find.replacedNone", defaultValue: "바꿀 곳이 없습니다.")
        }
        return String(
            format: String(localized: "find.replacedCount", defaultValue: "%d곳을 바꿨습니다."),
            locale: Locale(identifier: "ko_KR"),
            count
        )
    }

    static let helpBody = String(
        localized: "help.body",
        defaultValue: "한결은 macOS에서 HWP/HWPX 문서를 엽니다. 파일 → 열기… 를 누르거나 파일을 창이나 Dock 아이콘에 놓으세요. 본문과 표를 확인하고, PDF로 보내거나 인쇄할 수 있습니다."
    )
    static let helpKnownLimitsTitle = String(
        localized: "help.limits.title",
        defaultValue: "알려진 한계"
    )
    static let helpLimitLayout = String(
        localized: "help.limits.layout",
        defaultValue: "조판은 한/글과 같지 않습니다. 보이는 대로 편집(WYSIWYG)은 없고, 본문과 표를 구조화해 보여 줍니다."
    )
    static let helpLimitHwpSave = String(
        localized: "help.limits.hwpSave",
        defaultValue: ".hwp는 열 수 있습니다. 저장은 HWPX로만 됩니다."
    )
    static let helpLimitEncrypted = String(
        localized: "help.limits.encrypted",
        defaultValue: "암호가 걸린 문서는 열 수 없습니다. 암호를 풀지 않습니다."
    )
    static let helpLimitOpenErrors = String(
        localized: "help.limits.openErrors",
        defaultValue: "손상된 파일, 지원하지 않는 버전, 잘못된 형식, 빈 파일은 열 수 없습니다. 그때는 오류 안내가 열립니다."
    )
    static let helpLimitUnsupportedFormats = String(
        localized: "help.limits.unsupportedFormats",
        defaultValue: "DRM으로 보호된 문서, 옛 HWP 3.x, HML 파일은 열 수 없습니다."
    )
    static let helpLimitEditSubset = String(
        localized: "help.limits.editSubset",
        defaultValue: "문단과 표 칸의 글자만 고칠 수 있습니다. 행·열을 더하거나 지우거나 합치지 않고, 머리글·바닥글·수식·도형은 편집하지 않습니다."
    )
    static let helpLimitImages = String(
        localized: "help.limits.images",
        defaultValue: "그림은 화면에 보이지 않고, 넣거나 지울 수도 없습니다. HWPX로 저장하면 문서에 있던 그림은 파일에 그대로 남을 수 있습니다."
    )
    static let helpLimitPdfPrint = String(
        localized: "help.limits.pdfPrint",
        defaultValue: "PDF와 인쇄는 본문과 표 칸의 글자만 보냅니다. 한/글 조판 그대로 찍지 않습니다."
    )
    static let helpLimitMvpOut = String(
        localized: "help.limits.mvpOut",
        defaultValue: "자동 업데이트와 미리보기는 이 버전에 없습니다."
    )

    static let paragraphEditLiveNote = String(
        localized: "paragraph.edit.live",
        defaultValue: "문단은 이 문서의 열린 세션에 반영됩니다. 허브-A: 첫 문단에 HGINS99 입력 후 HWPX 저장."
    )
    static let paragraphEditFailureTitle = String(
        localized: "sheet.paragraph.title",
        defaultValue: "문단을 고치지 못했습니다"
    )
    static let paragraphEditRetryHint = String(
        localized: "sheet.paragraph.retryHint",
        defaultValue: "같은 문단에 다시 입력합니다."
    )
    static let paragraphEmpty = String(localized: "paragraph.empty", defaultValue: "빈 문단")

    static func paragraphA11y(ordinal: Int, text: String, editable: Bool) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? paragraphEmpty
            : text
        if editable {
            return String(
                format: String(
                    localized: "paragraph.a11y.edit",
                    defaultValue: "문단 %d을 편집합니다, %@"
                ),
                locale: Locale(identifier: "ko_KR"),
                ordinal,
                body
            )
        }
        return String(
            format: String(localized: "paragraph.a11y", defaultValue: "문단 %d, %@"),
            locale: Locale(identifier: "ko_KR"),
            ordinal,
            body
        )
    }

    static let tableEditLiveNote = String(
        localized: "table.edit.live",
        defaultValue: "표 칸은 이 문서의 열린 세션에 반영됩니다. 허브-A: (0,0)에 HGSET99 입력 후 HWPX 저장."
    )
    static let tableCellEditFailureTitle = String(
        localized: "sheet.tableCell.title",
        defaultValue: "표 칸을 고치지 못했습니다"
    )
    static let tableCellEditRetryHint = String(
        localized: "sheet.tableCell.retryHint",
        defaultValue: "같은 칸에 다시 입력합니다."
    )
    static let tableEmptyCell = String(localized: "table.cell.empty", defaultValue: "빈 칸")
    static let tableHeaderRole = String(localized: "table.cell.headerRole", defaultValue: "머리글")

    static func tableA11y(rows: Int, columns: Int) -> String {
        String(
            format: String(localized: "table.a11y", defaultValue: "표, %d행 %d열"),
            locale: Locale(identifier: "ko_KR"),
            rows,
            columns
        )
    }

    static func tableCellA11y(row: Int, column: Int, text: String, isHeader: Bool) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? tableEmptyCell
            : text
        if isHeader {
            return String(
                format: String(
                    localized: "table.cell.header.a11y",
                    defaultValue: "%d행 %d열, %@, %@"
                ),
                locale: Locale(identifier: "ko_KR"),
                row,
                column,
                tableHeaderRole,
                body
            )
        }
        return String(
            format: String(localized: "table.cell.a11y", defaultValue: "%d행 %d열, %@"),
            locale: Locale(identifier: "ko_KR"),
            row,
            column,
            body
        )
    }
    static let renderHostLabel = String(
        localized: "render.host.label",
        defaultValue: "문서 미리보기 영역"
    )
    static let renderHostPlaceholderTitle = String(
        localized: "render.host.placeholder.title",
        defaultValue: "렌더 화면 자리"
    )
    static let renderHostPlaceholderBody = String(
        localized: "render.host.placeholder.body",
        defaultValue: "네이티브 렌더 페이지(SVG 미리보기)가 여기에 연결됩니다. 지금은 정보구조 합의용 스케치입니다."
    )

    static let renderHostLoading = String(
        localized: "render.host.loading",
        defaultValue: "문서 화면을 불러오는 중"
    )

    static let renderHostReady = String(
        localized: "render.host.ready",
        defaultValue: "문서 화면 준비됨"
    )

}
