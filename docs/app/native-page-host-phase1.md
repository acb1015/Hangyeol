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
- `showsRenderHostSketch` 기본 **false** → `StructuredTextView` 회귀 유지
- listImages 세션 확장 없음 · Views 크롬/L10n 리라이트 없음 · notarytool 없음
- **PNG FFI / native-skia 금지**

## 주입

`DocumentWindow`가 비어 있지 않은 문서에서 플래그가 켜지면:

`NativePageHostFactory.renderHostView(document:onOpenFailure:)` → `RenderHostView(host:)` + 오버레이로 셸 `NSViewRepresentable`.

플래그 off(기본)에서는 호스트를 만들지 않고 기존 본문을 쓴다.

## Page preview (`hg_render_page_svg`)

제품 미리보기: `NativePageRaster.previewProvider` (앱 기동 시 설치; 테스트는 tearDown에서 `nil`로 되돌림).  
`preview(from:)`는 훅이 `nil`이면 같은 제품 경로로 폴백한다.

**같은 문서 세션만.** `HangyeolDocument.session` / 그 창의 `KitRealEngine` `hg_engine*`. **`EngineClient.current` 금지.**

| 상태 | 동작 |
|------|------|
| attach | `onLoadingChange(true → false)`. 성공 시 `onReady` |
| 빈 문서 | `surface = empty`, 크래시 없음, `onOpenFailure` 없음 |
| `session.lastOpenError` | `onOpenFailure` 후 throw. `surface = failed` |
| Mock / closed / unavailable | `preview` → `nil` → host **`.placeholder`** |
| Open Real, page 0 SVG non-empty | `.svg(data)` |
| empty SVG / throw | `nil` → `.placeholder` |
| PNG/SVG bytes (테스트 주입) | `presentPageImage` / 주입 provider. SVG 디코드 실패 시 placeholder |
| find/reveal | 표시용. 치환은 DocumentSession |

경로: `DocumentSession.renderPageSvg(pageIndex:)` → `KitRealEngine` → Kit `RealEngine.renderPageSvg` → `hg_render_page_svg`.  
버퍼는 기존 Kit `takeBuffer` / `hg_free_buffer`. 앱은 C 심볼을 새로 만들지 않고 PNG FFI를 열지 않는다.

`showsRenderHostSketch`는 **기본 false**로 둔다 (이 배선이 플래그를 켜지 않음).

## Vendor (Mac rebuild + `nm`)

`.xcframework` / `.a` / `.dylib` **커밋하지 않는다.** `hg_render_page_svg`를 쓰려면 Mac에서 staticlib → XCFramework → Vendor **심링크만** 갱신한다. 정본 절차: [vendor-rebuild.md](../engine/vendor-rebuild.md) · [xcframework.md](../engine/xcframework.md).

```bash
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# 기대: _hg_open _hg_save _hg_save_hwpx _hg_plain_text _hg_replace_text
#       _hg_insert_text _hg_delete_range _hg_list_tables _hg_set_cell_text
#       _hg_list_images _hg_render_page_svg _hg_close _hg_free_buffer _hg_last_error
# 없어야 함: _hg_render_page_png / native-skia 제품 심볼
```
