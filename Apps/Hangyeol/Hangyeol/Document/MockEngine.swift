import Foundation

/// 실제 HWP/HWPX 파서 대신 Mock JSON 미리보기만 돌려 주는 롤백 엔진.
/// ZIP/OLE 컨테이너를 본문으로 바꾸지 않는다 (Real 성공처럼 보이면 안 됨).
struct MockEngine: HangyeolEngine {
    static let failureMarker = Data("HANGYEOL_FAIL".utf8)

    func open(data: Data, type: DocumentFileType) throws -> DocumentModel {
        if data.isEmpty {
            return .empty
        }
        if data.starts(with: Self.failureMarker) {
            throw HangyeolError.engineFailed(String(
                localized: "error.engine.mockFail",
                defaultValue: "모의 엔진이 문서를 열 수 없습니다."
            ))
        }
        if let mapped = HangyeolOpenBytes.mockFailure(for: data) {
            throw mapped
        }
        if HangyeolOpenBytes.looksLikeNativeDocumentContainer(data) {
            throw HangyeolError.notYetImplemented(String(
                localized: "error.engine.mockNativeOpen",
                defaultValue: "HWP/HWPX 열기 (Mock)"
            ))
        }
        if var decoded = try? JSONDecoder().decode(DocumentModel.self, from: data),
           !decoded.blocks.isEmpty {
            decoded.metadata.isMockPreview = true
            return decoded
        }
        return Self.sampleDocument(type: type)
    }

    func save(_ model: DocumentModel, as type: DocumentFileType) throws -> Data {
        if type == .hwp {
            throw HangyeolError.saveRejected
        }
        var snapshot = model
        snapshot.metadata.sourceType = type
        snapshot.metadata.isMockPreview = true
        return try JSONEncoder().encode(snapshot)
    }

    static func sampleDocument(type: DocumentFileType = .hwpx) -> DocumentModel {
        DocumentModel(
            metadata: DocumentMetadata(
                title: String(localized: "sample.title", defaultValue: "한결 Mock 미리보기"),
                sourceType: type,
                isMockPreview: true
            ),
            blocks: [
                .paragraph(ParagraphBlock(text: "한결에 오신 것을 환영합니다.")),
                .paragraph(ParagraphBlock(text: "이 화면은 Mock 미리보기입니다. Real HWPX 파서 성공이 아닙니다.")),
                .paragraph(ParagraphBlock(runs: [
                    TextRun(text: "아래에서 ", isBold: false),
                    TextRun(text: "간단한 표", isBold: true),
                    TextRun(text: "를 확인할 수 있습니다.", isBold: false)
                ])),
                .table(TableBlock(
                    headers: ["항목", "내용"],
                    body: [
                        ["형식", "Mock JSON (HWPX 아님)"],
                        ["엔진", "MockEngine (롤백)"],
                        ["언어", "한국어"]
                    ]
                )),
                .paragraph(ParagraphBlock(text: "파일 메뉴에서 실제 HWP/HWPX를 열려면 Real + Vendor XCFramework가 필요합니다."))
            ]
        )
    }

    static func loadBundledSample() throws -> DocumentModel {
        if let url = Bundle.main.url(
            forResource: "welcome.mock",
            withExtension: "json",
            subdirectory: "Sample"
        ) {
            let data = try Data(contentsOf: url)
            return try MockEngine().open(data: data, type: .hwpx)
        }
        return sampleDocument()
    }
}
