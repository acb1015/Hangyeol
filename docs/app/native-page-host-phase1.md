# Native page host Phase1 (Path B stub)

역할: **개발자2 (셸)** — `HangyeolRenderHosting` 구현 스텁.  
정본 프로토콜: `Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift` (**#48**, 재정의하지 않음).  
엔진 스파이크 배경: [renderer-spike-1pager.md](../engine/renderer-spike-1pager.md). IA: [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md). ABI: [hg-render-abi.md](../engine/hg-render-abi.md).

## Path B

`DocumentCore` → **UTF-8 SVG** (`hg_render_page_svg`) → SwiftUI/AppKit **네이티브 페이지 호스트**.

- 임베드: `NSViewRepresentable` (`NativePageHostView`) + `NativePageRenderHost`
- **아님:** WKWebView, rhwp studio, postMessage bridge
- 문서 진실: `DocumentSession` + `hg_engine*` 하나. 호스트는 파생 미리보기만
- PDF/인쇄 Phase1: 현행 plainText exporter (**변경 없음**)
- **기본 UX:** Real + `canRenderPagePreview` → NativePage **미리보기** (기본). 같은 창 **미리보기 | 편집** 전환. 편집 = 기존 `StructuredTextView` + 세션 API (Path B SVG는 캔버스 IME가 아님). Mock / closed / open failure → 세그먼트 숨김 + `StructuredTextView`. empty SVG / throw → host `.placeholder`. 디버그 플래그 없음.
- listImages 세션 확장 없음 · Views 크롬/L10n 리라이트 없음 · notarytool 없음
- **PNG FFI / native-skia 금지**
- Linux / Cloud Agent는 `xcodebuild` 불가. `HangyeolTests`는 Mac에서 실행.

## 주입

`DocumentWindow`가 비어 있지 않은 문서에서 **Real + `canRenderPagePreview`**이면 툴바에 **미리보기 | 편집** 세그먼트를 둔다 (기본 미리보기).

- Preview: `NativePageHostFactory.renderHostView(document:onOpenFailure:)` → `RenderHostView(host:)` + 오버레이로 셸 `NSViewRepresentable`.
- Edit: 기존 `StructuredTextView` + 세션 `insertText` / `deleteRange` / `setCellText`.

Mock / cannot preview / open failure에서는 세그먼트를 숨기고 호스트를 만들지 않은 채 `StructuredTextView`만 쓴다. empty SVG / throw는 호스트 `.placeholder`(기존 빈 페이지+심볼)다.

## Page preview (`hg_render_page_svg`)

제품 미리보기: `NativePageRaster.previewProvider` (앱 기동 시 설치; 테스트는 tearDown에서 `nil`로 되돌림).  
`preview(from:)`는 훅이 `nil`이면 같은 제품 경로로 폴백한다.

**같은 문서 세션만.** `HangyeolDocument.session` / 그 창의 `KitRealEngine` `hg_engine*`. **`EngineClient.current` 금지.**

| 상태 | 동작 |
|------|------|
| 빈 문서 (window) | `EmptyStateView`. 호스트·세그먼트 없음 |
| Mock / closed / `lastOpenError` (window) | 세그먼트 숨김. `StructuredTextView` |
| Real + Preview (기본) | `NativePageHostFactory.renderHostView` |
| Real + Edit | 같은 창 `StructuredTextView` + 세션 API |
| attach | `onLoadingChange(true → false)`. 성공 시 `onReady` |
| `session.lastOpenError` (host) | `onOpenFailure` 후 throw. `surface = failed` |
| Open Real, page 0 SVG non-empty | `.svg(data)` |
| empty SVG / throw | `preview` → `nil` → host **`.placeholder`** |
| PNG/SVG bytes (테스트 주입) | `presentPageImage` / 주입 provider. SVG 디코드 실패 시 placeholder |
| find/reveal | 표시용. 치환은 DocumentSession |

경로: `DocumentSession.renderPageSvg(pageIndex:)` → `KitRealEngine` → Kit `RealEngine.renderPageSvg` → `hg_render_page_svg`.  
버퍼는 기존 Kit `takeBuffer` / `hg_free_buffer`. 앱은 C 심볼을 새로 만들지 않고 PNG FFI를 열지 않는다.

제품 기본 UX는 Real 미리보기가 있으면 NativePage를 보여 주고, **편집**으로 기존 StructuredTextView를 되돌린다. `showsRenderHostSketch = false` 같은 디버그 게이트는 없다.

## Vendor (Mac rebuild + `nm`)

`.xcframework` / `.a` / `.dylib` **커밋하지 않는다.** `hg_render_page_svg`를 쓰려면 Mac에서 staticlib → XCFramework → Vendor **심링크만** 갱신한다. 정본 절차: [vendor-rebuild.md](../engine/vendor-rebuild.md) · [xcframework.md](../engine/xcframework.md).

```bash
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# 기대: _hg_open _hg_save _hg_save_hwpx _hg_plain_text _hg_replace_text
#       _hg_insert_text _hg_delete_range _hg_list_tables _hg_set_cell_text
#       _hg_list_images _hg_render_page_svg _hg_close _hg_free_buffer _hg_last_error
# 없어야 함: _hg_render_page_png / native-skia 제품 심볼
```
