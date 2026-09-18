# Week-7/8 internal distribute + regression (app shell)

역할: **개발자2** — 앱 셸 빌드 안정 · 내부 배포 구분 · Mac 회귀 체크리스트.  
**문서만.** Views · Sheets · L10n, XCFramework 커밋, engine ABI, **실제 codesign / notarize / upload는 이 문서 범위 밖.**

상태: week-6 hub-B `listImages` 게이트는 팀장3이 **SMOKE_OK** 후 닫음. 다음 우선순위는 내부 배포 + 회귀 + 빌드 안정.  
공증 실행은 owner가 App Store Connect API 키(`.p8`)와 Team ID를 **주기 전까지 금지**. 초안·자격 표는 [notarization-prep.md](notarization-prep.md) — **여기 반복하지 않음.**

한계 메모: [known-limitations.md](../known-limitations.md). UTI/Finder/Dock 상세: [uti-finder-dock-smoke.md](uti-finder-dock-smoke.md).

---

## ASC `.p8` / Team ID 게이트 (명시)

| | 한다 | 하지 않는다 |
|--|------|-------------|
| **개발자2 (지금)** | 이 체크리스트 유지. Debug/`xcodebuild` 안정. 내부 배포 **구분**을 문서화. | `notarytool submit`, `stapler staple`, Developer ID로 archive 후 업로드, 자격 증명 요청 대행. |
| **owner** | Apple Developer **Team ID**. ASC API 키 (Issuer ID, Key ID, **`.p8`**). Developer ID Application 인증서. | — |

자격 증명이 리포·이슈·PR·환경 변수에 **들어오기 전까지**:

- 공증은 **문서만** ([notarization-prep.md](notarization-prep.md) 개요).
- `xcrun notarytool` / `stapler` / Gatekeeper `spctl --assess` 를 **돌리지 않는다**.
- 서명 스크립트를 추가하지 않는다. stub가 필요하면 “blocked until credentials”를 찍고 **non-zero exit** — 이 PR은 마크다운만.

---

## 누가 무엇을 (개발자2 vs frontend)

`listImages` 세션 API는 **main** (PR #44). 이 PR에서 Document / session / Kit 호출을 **더 바꾸지 않는다.** 그림 UI는 frontend.

| | **개발자2 (셸)** | **frontend (Views)** |
|--|-------------------|----------------------|
| 연다 | `DocumentGroup` / `HangyeolDocument` / `FileOpening` / UTI / sandbox 북마크 | 창 크롬, EmptyState, 도움말 |
| 편집 게이트 | `DocumentSession.canEdit*` / `canListImages` (Real + open `hg_engine*`만 true) | 필드·캡션·a11y. Views는 Kit/`EngineClient.current`를 **직접 호출하지 않음** |
| 그림 | 세션 `listImages()` 읽기 전용 (dirty 아님). Mock → `notYetImplemented` | **listImages UI** (목록 시트·렌더). 화면 그림 없음은 도움말 카피 |
| 실패 UX | freeze → `lastOpenError` / `HangyeolError` 매핑 | ErrorSheet **카피** (`ErrorSheetPresentation`, L10n) |
| 빌드·배포 | scheme `Hangyeol` macOS, 엔타이틀먼트, 내부 배포 구분, 공증 **문서** | UI 변경 없음 (이 트랙) |

범위 밖: WYSIWYG, Sparkle, Quick Look, 그림 insert/delete, BinData extract, 행·열 추가.

---

## Mock vs Real (`HANGYEOL_USE_MOCK`) — 경고

Live 회귀(insert / delete / 표 셀 / `listImages`)는 **Real + Vendor XCFramework** 만 SMOKE_OK로 센다.

| 상태 | 언제 | Live API |
|------|------|----------|
| **Real** | Kit XCFramework 링크, Mock 강제 없음 | `canEdit` / `canListImages` = true |
| **Mock** | Vendor 없음, 또는 `HANGYEOL_USE_MOCK=1` (`true` / `YES`), 또는 `EngineClient.resetToMock()`, 또는 UserDefaults `HANGYEOL_USE_MOCK` | insert / delete / `setCellText` / `listImages` → `notYetImplemented`. **가짜 성공 금지** |

열기 UX만은 Mock으로도 확인 가능 (F16 `.corrupt` 등 Mock도 삼키지 않음). **hub-B `listImages` count를 Mock에서 통과로 적지 말 것.**

도움말 본문에 `HANGYEOL_USE_MOCK` 문자열을 **넣지 않는다** (frontend 카피 계약). 플래그는 개발자2 머신·scheme Environment Variables 전용. 절차: [week3-ffi-checklist.md](../week3-ffi-checklist.md).

Vendor 심볼릭 링크는 [vendor-rebuild.md](../engine/vendor-rebuild.md) — `.xcframework` / `.a` / `.dylib` **커밋 금지**.

```bash
mkdir -p Packages/HangyeolKit/Vendor
ln -sf /path/to/HangyeolEngine.xcframework \
  Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework
```

`hg_*`가 바뀌면 로컬 재빌드. Linux CI는 C stub.

---

## 빌드 안정 (scheme Hangyeol, macOS)

Linux CI / Cloud Agent는 `xcodebuild` 불가. **개발자2 Mac** (macOS 14+, Apple Silicon).

프로젝트: `Apps/Hangyeol/Hangyeol.xcodeproj`  
scheme: **`Hangyeol`** (shared). destination: `generic/platform=macOS`. 배포 타깃 **14.0**. Bundle ID `app.hangyeol.mac`.

```text
xcodebuild -project Apps/Hangyeol/Hangyeol.xcodeproj \
  -scheme Hangyeol \
  -destination 'generic/platform=macOS' \
  -configuration Debug \
  build
```

테스트 (같은 scheme → `HangyeolTests`):

```text
xcodebuild -project Apps/Hangyeol/Hangyeol.xcodeproj \
  -scheme Hangyeol \
  -destination 'platform=macOS' \
  test
```

Debug = Automatic 서명 (로컬 개발). pbxproj의 `CODE_SIGN_STYLE` / Hardened Runtime / sandbox는 [notarization-prep.md](notarization-prep.md) 표. **이 트랙에서 pbxproj를 바꾸지 않는다.**

셸 쪽 회귀 테스트 (Views 재디자인 아님): `HangyeolOpenFailureTests`, `FileOpeningTests`, `HangyeolDocumentTests`, `DocumentSessionTests` (`canListImages` + count, Mock는 throw).

---

## Mac build / smoke 회귀 매트릭스

전제: Real 행은 Vendor XCFramework. 픽스처 라이선스: [fixtures-intake-list.md](../fixtures-intake-list.md). HOLD_LICENSE (F11 등) 쓰지 말 것.

이미 쓰는 경로:

| ID | 경로 |
|----|------|
| hub-A | `fixtures/hub_hwpxlib_SimpleTable.hwpx` |
| hub-B | `fixtures/hub_hwpxlib_SimplePicture.hwpx` |
| Hangul 샘플 (번들) | `Apps/Hangyeol/Hangyeol/Resources/Sample/welcome.mock.json` — **Mock JSON**. Real 성공으로 적지 말 것. Finder 더블클릭은 hub-A. COMMIT_OK `.hwp` 없음 |
| Hangul 작성본 (UTI, 있으면) | owner Downloads `[양식1] …사업계획서_하베스트랩.hwpx` — HOP UTI여도 DocumentGroup이 연다 ([uti-finder-dock-smoke.md](uti-finder-dock-smoke.md) 충돌 절) |

토큰은 엔진 게이트와 동일: insert `HGINS99`, delete `HGDEL99`(길이 7), 셀 `HGSET99`, 치환 `1`→`HGPOC99`.

| # | 단계 | 기대 | 엔진 | 통과 |
|---|------|------|------|------|
| B1 | scheme `Hangyeol` Debug `xcodebuild` build | 성공. Mock 폴백이어도 앱은 기동 | 둘 다 | ☐ |
| B2 | hub-A 열기 | 표 본문 창. HOP 설치 시 “Hangul Word Processor XML document 포맷…” **없음** | Real 권장 | ☐ |
| B3 | hub-B 열기 | 창 열림. **그림은 화면에 안 그려도 됨** (frontend). 셸은 열기만 | Real | ☐ |
| B4 | 번들 `welcome.mock.json` (샘플 메뉴 / `MockEngine.loadBundledSample`) | Mock 미리보기 (`isMockPreview`). DocumentGroup+Real로 `.hwpx`인 척 성공이면 **실패** | Mock only | ☐ |
| E1 | hub-A 첫 문단 insert `HGINS99` 후 HWPX 저장 | 본문에 토큰. `hp:linesegarray` = 0 (clear-before-save) | **Real** | ☐ |
| E2 | hub-A delete `HGDEL99` (seed 후 7자) | 토큰 사라짐. 다른 셀(`2`,`5`) 유지 | **Real** | ☐ |
| E3 | hub-A 표 셀 `(0,0)` ← `HGSET99` | 셀 평문에 토큰. 저장 왕복 | **Real** | ☐ |
| I1 | hub-B `session.canListImages` | `true` (open Real). Mock이면 `false` + throw | **Real** | ☐ |
| I2 | hub-B `listImages()` count + meta | count **≥ 1**, width/height > 0, format jpg/png/… dirty **아님**. UI 없음 | **Real** | ☐ |
| U1 | UTI 열기 (Finder/Dock/창 드롭) | [uti-finder-dock-smoke.md](uti-finder-dock-smoke.md) 수동 칸. 이 표에 단계 복제 안 함 | 둘 다 | ☐ |
| F1 | 열기 실패 ErrorSheet (개요) | 아래 표. 카피 문구는 frontend | 둘 다 | ☐ |

### 열기 실패 ErrorSheet (개요만)

카피·kind id는 frontend. 셸은 **무음 금지** + 케이스 구분.

| 케이스 | 자극 | `HangyeolError` |
|--------|------|-----------------|
| 잘못된 확장자 | F14 `fixtures/14_wrong_ext_hwpx.pdf` **창 드롭** | `.unsupportedType` (내용은 HWPX여도 `.corrupt` 아님) |
| 손상 | F16 truncated / F21 prettyprint-bad `.hwpx` | `.corrupt` |
| 암호 | F22 synthetic / freeze `ENCRYPTED` | `.encrypted` (복호화 없음) |
| 미지원 버전 | DRM · HWP 3.x · HML (COMMIT_OK 픽스처 없음) | `.unsupported` |
| 빈 파일 | 0바이트 | `.emptyFile` |
| 북마크 | 최근 문서 파일을 옮긴 뒤 재열기 | `.bookmarkFailed` |

Finder에서 `.pdf` 더블클릭이 Preview로 가는 것은 **실패가 아님**. UTI 단계 전체는 week-5 문서.

---

## 내부 배포: Debug / ad-hoc vs Developer ID

팀 내부로 `.app`을 돌리는 것과 Gatekeeper용 Developer ID **공증**은 다르다. 후자는 owner 자격이 있을 때만 ([notarization-prep.md](notarization-prep.md)).

| 종류 | 서명 | 어디에 쓰나 | 공증 |
|------|------|-------------|------|
| **Debug** | Automatic, Apple Development | 개발자2 Xcode Run / `xcodebuild` Debug | 없음. 로컬만. |
| **Ad-hoc** | 팀 Ad Hoc 또는 Development 프로필 | 같은 팀 Mac에 직접 복사. SIP/Gatekeeper가 막을 수 있음 | 없음. “내부 스모크”용. **공증된 배포가 아님.** |
| **Developer ID Application** | Developer ID 인증서 (owner, **아직 없음**) | 팀 밖 Direct 배포. App Store 아님 | **필수**이나 `.p8` + Team ID 전까지 **시도하지 않음** |

내부 스모크: Debug 또는 (팀이 있으면) ad-hoc `.app`을 USB/공유 폴더로 넘긴다. 수신 Mac에서 “확인되지 않은 개발자”가 떠도 **공증으로 풀려고 하지 말 것.**

Vendor XCFramework가 없는 빌드를 내부에 넘기면 Mock이다. 넘기기 전에 심볼릭 링크를 확인한다 ([vendor-rebuild.md](../engine/vendor-rebuild.md)).

---

## 체크 (개발자2)

| # | 항목 | 통과 |
|---|------|------|
| 1 | 공증·업로드·`notarytool`을 이 트랙에서 실행하지 않음 | ☐ |
| 2 | ASC `.p8` / Team ID / 인증서가 소스에 없음 | ☐ |
| 3 | Vendor `.xcframework` 미커밋, 로컬 symlink만 | ☐ |
| 4 | Document/session/`listImages` API·Views 변경 없음 (이 PR) | ☐ |
| 5 | Mac에서 scheme `Hangyeol` Debug build (가능하면 test) | ☐ |
| 6 | Real일 때만 E1–E3 · I1–I2를 SMOKE_OK로 기록. Mock이면 경고만 | ☐ |

---

## 범위 밖

- owner 자격 발급, Developer ID archive, `notarytool` / staple / `spctl`
- Sparkle, App Store Connect 앱 레코드, Quick Look
- listImages **UI**, ErrorSheet/Help 카피, XCFramework 커밋, engine freeze 변경
