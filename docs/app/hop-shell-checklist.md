# HOP desktop shell → Hangyeol (Path B)

역할: **개발자2** — 네이티브 `DocumentGroup` 셸.  
참고: [golbin/hop](https://github.com/golbin/hop) **셸 패턴만**. 소스를 벤더하지 않는다. **Tauri로 바꾸지 않는다.**

**렌더 경로 (팀장3 LOCKED):** Hangyeol 제품 임베드는 HOP의 rhwp studio **webview가 아니다.**  
Path B = `DocumentCore` → UTF-8 SVG (`hg_render_page_svg`) → **SwiftUI/AppKit NativePageHost**. PNG / native-skia 없음.  
상세: [renderer-embed-slot.md](renderer-embed-slot.md).

상태 값: **DONE** / **PARTIAL** / **TODO**.

프론트 IA 스케치(PR **#46**): [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md) · `RenderHostView`.  
호스트 구현(PR **#50**): [native-page-host-phase1.md](native-page-host-phase1.md) · `Render/NativePageRenderHost`. 기본 UX: Real Preview → NativePage. Edit → StructuredTextView.

---

## 하지 않는 것

- HOP `apps/desktop` / `apps/studio-host` 복제, Tauri 의존성
- WKWebView · rhwp studio · `postMessage` 브리지
- `notarytool` / `stapler` / 업로드 (공증은 [notarization-prep.md](notarization-prep.md) 문서만)
- Vendor `.xcframework` 커밋, `listImages` 세션 API 확장
- Views 크롬 재디자인 (프론트 소유)

---

## 매핑

| 주제 | HOP (cite, no vendor) | Hangyeol | 상태 |
|------|----------------------|----------|------|
| 문서 세션 | `apps/desktop/src-tauri/src/state.rs` (`AppState` / session map), `commands.rs` `create_document` / `open_document_tracking` / `close_document` | `DocumentSession` 창당 `hg_engine*` (`HangyeolDocument`). `EngineClient.current`는 프로브 시임 | **DONE** |
| Atomic save | `commands.rs` `prepare_staged_hwp_save` + `commit_staged_hwp_save` — sibling `.hop-save-*.tmp` 후 커밋. `state.rs` 세션 IR | FileDocument `fileWrapper` → 세션 `save` / live `hg_save_hwpx` (clear-before-save). HOP식 `.tmp` 스테이징은 없음. Untitled Real(IR 없음)은 Mock JSON `.hwpx`를 **쓰지 않음** | **PARTIAL** |
| Open routing | `lib.rs` macOS `RunEvent::Opened` → `queue_open_paths` / `hop-open-paths`; `pending_open.rs`; `commands.rs` `take_pending_open_paths` / `prepare_document_open` | Finder/Dock는 **DocumentGroup + Info.plist**. `AppDelegate.application(_:open:)` 없음 (week-2 SIGSEGV). 패널·드롭·최근문서는 `FileOpening` | **DONE** |
| DnD | `windows.rs` `attach_document_drop_handler` (`DragDropEvent::Drop` → `hop-open-paths`, `.hwp`/`.hwpx`만) | `AppDelegate` `registerForDraggedTypes(.fileURL)` + `FileOpening.handleDrop` + `UTType.hangyeolSupports` | **DONE** |
| Multi-window | `windows.rs` `create_editor_window` / `create_editor_window_with_label`; `commands.rs` `create_editor_window` | `DocumentGroup` 네이티브 문서 창. 창마다 `DocumentSession` | **DONE** |
| PDF | `pdf_export.rs` + `commands.rs` `export_pdf` / `export_pdf_from_hwp_path` (native SVG→PDF) | Phase1: `PDFExporter` **plainText**. 웹뷰 인쇄/SVG PDF 교체 **없음** | **PARTIAL** |
| Print | `commands.rs` `print_webview` (`WebviewWindow.print`) | Phase1: `PrintCoordinator` **plainText** `NSPrintOperation`. HOP webview print 안 씀 | **PARTIAL** |
| 렌더 본문 | studio-host 웹 에디터 + Tauri webview | **Path B** `#50` `Render/NativePageRenderHost` + `NativePageHostView`. Real Preview → NativePage (`hg_render_page_svg`). 같은 창 Edit → `StructuredTextView`. Mock/fail → 세그먼트 숨김 + StructuredText. WKWebView / PNG / skia 금지 | **DONE** (Preview \| Edit) |
| UTI / 파일 연결 | HOP export `net.golbin.hop.hwp` / `.hwpx` | Hangyeol **Owner** `org.hangyeol.*` + HOP UTI **import**. [uti-finder-dock-smoke.md](uti-finder-dock-smoke.md) | **DONE** |
| 공증 | HOP는 자격 후 signed/notarized dmg (DEVELOPMENT.md) | 문서만. owner `.p8`+Team ID 전까지 실행 금지 | **TODO** (docs) |

HOP 경로 링크 (main, 벤더 없음):

- [docs/DEVELOPMENT.md](https://github.com/golbin/hop/blob/main/docs/DEVELOPMENT.md) — atomic save, open routing, 새 창, DnD, SVG-to-PDF, webview print
- [apps/desktop/src-tauri/src/lib.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/lib.rs)
- [apps/desktop/src-tauri/src/commands.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/commands.rs)
- [apps/desktop/src-tauri/src/state.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/state.rs)
- [apps/desktop/src-tauri/src/pending_open.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/pending_open.rs)
- [apps/desktop/src-tauri/src/windows.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/windows.rs)
- [apps/desktop/src-tauri/src/pdf_export.rs](https://github.com/golbin/hop/blob/main/apps/desktop/src-tauri/src/pdf_export.rs)

---

## 기본 엔진 (Mock 함정)

| | 값 |
|--|----|
| Default | **Real + Vendor XCFramework** (`KitRealEngine`) |
| `HANGYEOL_USE_MOCK` | **OFF** (scheme에 키 없음. `1`/`true`/`YES`만 강제) |
| Welcome 샘플 | `Resources/Sample/welcome.mock.json` — Mock JSON. `.hwpx`가 아님. Real 성공으로 적지 말 것 |

Live 회귀(insert/delete/표/`listImages`)는 Real만 SMOKE_OK. [week7-internal-regression.md](week7-internal-regression.md).

---

## 다음 (이 PR 밖)

1. HOP식 sibling temp + rename 저장 (샌드박스 제자리 저장과 맞출 것)
2. Owner 자격 후 공증 실행
3. 찾기/표 UX를 렌더 세션 API에 맞추는 큰 리라이트 (이 PR 밖)
