# UTI / Finder / Dock smoke (week-5)

역할: **개발자2** — app shell / UTI / sandbox / Info.plist.  
Views · Sheets · L10n 카피 재디자인, known-limitations, XCFramework, engine 은 **이 문서 범위 밖**.

기준 브랜치: `main` (PR **#31** 머지 이후). Linux CI / Cloud Agent는 Finder·Dock를 돌릴 수 없다. 아래 **Mac 수동** 칸은 개발자2 머신 연결 시 수행.

소스:

| 항목 | 경로 |
|------|------|
| 선언 | `Apps/Hangyeol/Hangyeol/Resources/Info.plist` |
| Swift UTI | `Apps/Hangyeol/Hangyeol/System/UTTypes.swift` |
| 열기·드롭 | `Apps/Hangyeol/Hangyeol/System/FileOpening.swift` |
| 문서 모델 | `HangyeolDocument` (`DocumentGroup` / `FileDocument`) |
| 샌드박스 | `Hangyeol.entitlements` + `SecurityScopedBookmarks.swift` + `RecentDocuments.swift` |
| 단위 테스트 | `HangyeolTests/FileOpeningTests.swift`, `HangyeolOpenFailureTests.swift`, `HangyeolDocumentTests.swift` |

---

## 정적 계약 (리포에서 확인 · Mac 불필요)

한결이 **소유(Owner)** 하는 UTI는 `org.hangyeol.*` 뿐이다 (`UTExportedTypeDeclarations`).  
한컴·HOP 등 타사 HWP/HWPX UTI는 `UTImportedTypeDeclarations`로 **Viewer/Editor import가 필수**다. 한컴 상표·아이콘 에셋은 번들하지 않는다. (PR #34 당시 “한컴 UTI import 금지”는 **철회**.)

Mac에서 확인한 확장자 바인딩 (HOP 설치, 한컴 미설치):

- `UTType(filenameExtension: "hwpx")` = `net.golbin.hop.hwpx` (Hangul Word Processor XML document) — **필수 최소셋**
- `UTType(filenameExtension: "hwp")` = `net.golbin.hop.hwp` (Hangul Word Processor document) — **필수 최소셋**
- `com.infraware.polarisofficeservice.hwp` 존재 (Polaris, `.hwp`)
- `com.hancom.hwpx` / `com.hancom.hwp` / `com.haansoft.*` 는 이 Mac에서 lookup **MISSING**. imported에 넣어도 해롭지 않음.

한/글에서 만든 파일(예: Downloads `[양식1] 2026년도 TU-VCC 5기 기술트랙 사업계획서_하베스트랩.hwpx`)도 NSDocument가 HOP UTI 설명으로 거절한 그 케이스다.

| UTI | 역할 | 확장자 | Swift |
|-----|------|--------|-------|
| `org.hangyeol.hwpx` | **Owner** (export) | `hwpx` | `UTType.hangyeolHwpx` (`exportedAs:`) |
| `org.hangyeol.hwp` | **Owner** (export) | `hwp` | `UTType.hangyeolHwp` (`exportedAs:`) |
| `net.golbin.hop.hwpx` | import (**필수**, HOP `.hwpx` 바인딩) | `hwpx` | `hangyeolImportedHwpxIdentifiers` |
| `net.golbin.hop.hwp` | import (**필수**, HOP `.hwp` 바인딩) | `hwp` | `hangyeolImportedHwpIdentifiers` |
| `com.infraware.polarisofficeservice.hwp` | import (Polaris, Mac lookup) | `hwp` | 동일 |
| `com.haansoft.HancomOfficeViewer.mac.hwpx` | import (한컴 뷰어, 미설치 Mac에선 MISSING; 확장자 태그 없음 — HOP와 합침 방지) | `hwpx` | 동일 |
| `com.haansoft.HancomOfficeViewer.mac.hwp` | import (한컴 뷰어, 미설치 Mac에선 MISSING; 확장자 태그 없음) | `hwp` | 동일 |

`DocumentFileType.typeIdentifier` 는 계속 `org.hangyeol.hwpx` / `org.hangyeol.hwp`. 타사 식별자는 `init?(typeIdentifier:)` · `HangyeolDocument.fileType(from:)` 가 `.hwpx` / `.hwp` 로 매핑한다.

`UTType.hangyeolReadableTypes` 는 `org.hangyeol.*` + plist imported를 `UTType(id) ?? UTType(importedAs:)` 로 넣고, `.hwpx`/`.hwp` 확장자 바인딩을 붙인다.  
`importedAs` 가 haansoft를 HOP UTI로 흡수하므로, Swift 테스트가 원본 문자열을 요구하는 대상은 **보존되는 ID만**: `net.golbin.hop.hwpx` / `net.golbin.hop.hwp` / `com.infraware.polarisofficeservice.hwp`. haansoft는 Info.plist imported + `LSItemContentTypes` 에 둔다. `HangyeolDocument.readableContentTypes` 와 같다.  
쓰기 타입은 HWPX만 (`writableContentTypes` == `[.hangyeolHwpx]`). HWP 디스크 저장은 엔진 `SAVE_REJECTED` → `HangyeolError.saveRejected` (PR #31). Finder 핸들러는 **Owner + Editor** 로 둔다 (열기·기본 앱 순위, org.hangyeol 문서 타입).

### Info.plist 키

- `CFBundleTypeRole` = **Editor**
- `LSHandlerRank` = **Owner** (org.hangyeol 문서 타입 두 개. 한컴을 Owner로 export하지 않음)
- `LSItemContentTypes` = `org.hangyeol.*` **와** 해당 확장자의 imported UTI
- `UTExportedTypeDeclarations` = `org.hangyeol.hwpx` / `org.hangyeol.hwp` + `public.filename-extension` + `public.data` / `public.content`
- `UTImportedTypeDeclarations` = HOP·한컴 뷰어 UTI (아이콘 키 없음)
- 루트 `LSSupportsOpeningDocumentsInPlace` = **true** (샌드박스 제자리 열기)

엔타이틀먼트: `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `files.bookmarks.document-scope`.

`xcodeproj` 는 `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Hangyeol/Resources/Info.plist` 로 병합한다. 문서 타입·UTI·제자리 열기는 **소스 Info.plist** 가 단일 출처다.

---

## 코드 경로 (어디가 무엇을 여나)

Finder 더블클릭 / Dock 아이콘 드롭은 **DocumentGroup + Info.plist** 가 연다. `AppDelegate` 에 `application(_:open:)` 을 넣지 않는다. Week-2에서 `NSDocumentController` 를 기동 직후 건드리면 `PlatformDocumentController.createDocumentClassIfNeeded` SIGSEGV 가 났다.

창 드롭 · 커스텀 **문서 열기…** 패널 · 최근 문서 재열기는 `FileOpening` → `UTType.hangyeolSupports` 가드 → `OpenDocumentAction` / `NSDocumentController.openDocument`.

| 동작 | 진입 | 성공 | 실패 |
|------|------|------|------|
| Finder 더블클릭 `.hwpx` / `.hwp` | Launch Services → `DocumentGroup` / `HangyeolDocument.init(configuration:)` | 문서 창 | 엔진 freeze → `lastOpenError` → ErrorSheet (`.corrupt` / `.encrypted` / `.unsupported` …) |
| Dock 아이콘 · Finder에서 앱 아이콘으로 드롭 (선언된 타입) | 위와 동일 | 문서 창 | 위와 동일 |
| 문서 **창** 위에 드롭 | `onDrop(of: [.fileURL])` → `FileOpening.handleDrop` → `open(url:)` | 위와 동일 | 확장자 가드 실패 시 **즉시** `.unsupportedType` (무음 금지) |
| 파일 → 문서 열기… | `FileOpening.makeOpenPanel` (`allowedContentTypes` = 한결 UTI, `allowsOtherFileTypes` = false) | `FileOpening.open` | 패널에 `.pdf` 안 보임. 우회 드롭은 ErrorSheet |
| 최근 문서 | `RecentDocuments.open` → 북마크 `resolve` + `startAccessing` → `FileOpening.openResolved` | 재열기 | `.bookmarkFailed` / 열기 freeze |

`UTType.hangyeolSupports` 는 **경로 확장자만** 본다 (`hwpx` / `hwp`, 대소문자 무시). 바이트 매직은 쓰지 않는다. F14는 내용이 HWPX여도 `.pdf` 이면 false.

---

## 충돌 (다른 앱이 `.hwpx` / `.hwp` UTI를 export)

HOP가 `UTType(filenameExtension: "hwpx")` 를 `net.golbin.hop.hwpx` (localizedDescription: Hangul Word Processor XML document) 로 소유하면, NSDocument는 그 UTI로 연다. `readableContentTypes`가 `org.hangyeol.hwpx` 뿐이면 DocumentGroup이 파일에 닿기 전에 거절한다:

> 문서 'hub-A.hwpx'을(를) 열 수 없습니다. 한결은(는) 'Hangul Word Processor XML document' 포맷인 파일을 열 수 없습니다.

같은 거절이 한/글에서 만든 Downloads `[양식1] 2026년도 TU-VCC 5기 기술트랙 사업계획서_하베스트랩.hwpx` 에서도 났다. Spotlight/`mdls` 가 `org.hangyeol.hwpx` 를 보여도 NSDocument는 확장자→UTI 를 쓴다. `.hwp` 는 HOP(`net.golbin.hop.hwp`)와 Polaris(`com.infraware.polarisofficeservice.hwp`).

필수 최소셋: imported + `LSItemContentTypes` + `hangyeolReadableTypes` 에 `net.golbin.hop.hwpx` / `net.golbin.hop.hwp` + `fileType` 매핑. Owner는 `org.hangyeol.*`.

필수:

1. `UTImportedTypeDeclarations`에 한컴/HOP UTI를 Viewer/Editor로 import (상표·아이콘 번들 금지).
2. `CFBundleDocumentTypes.LSItemContentTypes`에 `org.hangyeol.*` **와** imported UTI.
3. `hangyeolReadableTypes`가 import + `UTType(filenameExtension:)` 바인딩을 포함.
4. `HangyeolDocument.fileType(from:)` 가 경쟁 UTI를 `.hwpx` / `.hwp` 로 매핑 (확장자 폴백).

성공: HOP UTI로 태그된 `.hwpx` 와 `org.hangyeol.hwpx` hub-A 를 DocumentGroup이 모두 수용. 위 시스템 알림 없음.

---

## Mac 수동 스모크 (개발자2)

전제: macOS 14+ / Apple Silicon, `Apps/Hangyeol/Hangyeol.xcodeproj` 서명 후 Run. XCFramework 없어도 Mock으로 열기 UX는 확인 가능. Real freeze(`.corrupt`) 매핑은 Vendor XCFramework가 있을 때 한 번 더.

픽스처는 저장소 `fixtures/` (라이선스: `docs/fixtures-intake-list.md`). 샌드박스 밖 경로가 편하면 Desktop에 복사.

| # | 단계 | 기대 | 통과 |
|---|------|------|------|
| 1 | UTI 정합 | 빌드된 `Hangyeol.app/Contents/Info.plist` 에 `org.hangyeol.hwpx` / `org.hangyeol.hwp` export, `UTImportedTypeDeclarations`에 `net.golbin.hop.hwpx` 등, `LSHandlerRank=Owner`, `LSSupportsOpeningDocumentsInPlace=true` | ☐ |
| 2 | Finder에서 `fixtures/hub_hwpxlib_SimpleTable.hwpx` (hub-A) **더블클릭** | 한결이 기동·전면, DocumentGroup 창에 표 본문. Preview/한컴으로 가면 기본 앱 확인 | ☐ |
| 2b | **충돌** HOP 설치 상태에서 hub-A 더블클릭 (한결로 열기) | HOP UTI로 태그돼도 한결 창이 열린다. “Hangul Word Processor XML document 포맷인 파일을 열 수 없습니다” **없음** | ☐ |
| 3 | `.hwp` 더블클릭 | COMMIT_OK `.hwp` 없음 (F13 backlog). 번들 `welcome.mock.json`을 `.hwp`로 바꿔 쓰지 말 것 (Mock JSON ≠ Real). HOLD F11 금지. 있으면 Hangul F01만 | ☐ |
| 4 | hub-A를 **실행 중** 한결 **Dock 아이콘**에 드롭 | 새 문서 창 (또는 기존 창에 열림). FileOpening 가드는 이 경로에 없음 — Info.plist 타입이 맞아야 함 | ☐ |
| 5 | 한결이 **꺼진** 상태에서 같은 파일을 Dock / 앱 아이콘에 드롭 | 기동 + 해당 문서 창. 제자리 열기(in-place) — iCloud 아님, 샌드박스 user-selected | ☐ |
| 6 | hub-A를 **문서 창** 위로 드롭 | 점선 오버레이(`L10n.dropToOpen`) 후 열림. `AppDelegate` `registerForDraggedTypes(.fileURL)` + SwiftUI `onDrop` | ☐ |
| 7 | **F14** `fixtures/14_wrong_ext_hwpx.pdf` 를 **문서 창**에 드롭 | ErrorSheet **`.unsupportedType`** (`unsupportedType:14_wrong_ext_hwpx.pdf`). 무음 무시 금지. 내용이 HWPX여도 `.corrupt` 가 아님 | ☐ |
| 8 | F14를 Finder에서 더블클릭 | 한결이 `.pdf` Owner가 아님 → Preview 등이 연다. **실패가 아님.** 한결 ErrorSheet를 보려면 7번(창 드롭) | ☐ |
| 9 | F14를 Dock 아이콘에 드롭 | Launch Services가 선언되지 않은 타입을 거절(바운스)할 수 있음. ErrorSheet 보장은 **창 드롭** | ☐ |
| 10 | **F16** `fixtures/16_corrupt_truncated.hwpx` 더블클릭 또는 창 드롭 | 확장자는 `.hwpx` 이므로 가드 통과. ErrorSheet **`.corrupt`**. Mock도 삼키지 않음 (`HangyeolOpenBytes` / PR #31) | ☐ |
| 11 | hub-A를 연 뒤 종료 → 파일 → 최근 문서에서 재열기 | 샌드박스 북마크(`withSecurityScope`)로 다시 열림. 권한 시트 없이 본문 복구 | ☐ |
| 12 | 최근 문서 항목의 파일을 Finder에서 옮긴 뒤 재열기 | `.bookmarkFailed` 또는 열기 실패 시트. 무음 금지 | ☐ |

`AppDelegate.applicationShouldOpenUntitledFile` 가 true 라서, 파일로 기동해도 **빈 문서 창이 하나 더** 생길 수 있다. 스모크 실패로 보지 않는다 (EmptyState UX).

---

## 단위 테스트 (Mac `HangyeolTests`)

Linux에서는 `xcodebuild` 불가. 개발자2:

```text
Apps/Hangyeol/Hangyeol.xcodeproj → HangyeolTests
```

관련 케이스:

- `FileOpeningTests.testHangyeolSupportsHwpxAndHwpOnly`
- `testInfoPlistExportedUTIsMatchSwiftAndLaunchServicesKeys` — 소스 Info.plist ↔ export Owner / import HOP·한컴 / `hangyeolReadableTypes`
- `testReadableTypesIncludeExportedUTIs` — import + `UTType(filenameExtension:)` 바인딩
- `HangyeolDocumentTests.testFileTypeMapsImportedHopHwpxWithoutRequiringHopInstalled` — HOP 미설치에서도 hop UTI → `.hwpx`
- `testFilenameExtensionBoundTypesAreReadableAndMapToDocumentFileType`
- `testHangyeolSupportsUsesPathExtensionNotBytes` — F14 false, F16/hub-A true
- `testHandleDropReturnsFalseWhenNoFileURLProviders`
- `HangyeolOpenFailureTests.testWrongExtPdfFilenameIsUnsupportedType`
- `testMockOpenCorruptTruncatedFixtureDoesNotSwallow` / `testHangyeolDocumentOpenCorruptThrowsCorrupt`

---

## 범위 밖 (다음 PR)

week-7/8 내부 배포·insert/delete/표/`listImages` 회귀는 [week7-internal-regression.md](week7-internal-regression.md). Finder/Dock 단계는 이 문서가 정본.

- ErrorSheet 카피·도움말 알려진 한계 (PR #30 등 UI 트랙)
- XCFramework 커밋 / engine ABI
- WYSIWYG, Quick Look, 기본 앱 강제 (`lsregister` 자동화)
- F13 `.dat` (COMMIT_OK HWP 없음, detect 게이트는 F14)
