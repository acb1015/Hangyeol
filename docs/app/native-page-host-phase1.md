# Native page host Phase1 (Path B)

역할: **개발자2 (셸)** — `HangyeolRenderHosting` 구현.  
정본 프로토콜: `Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift` (**#48**, 재정의하지 않음).  
엔진 스파이크 배경: [renderer-spike-1pager.md](../engine/renderer-spike-1pager.md). IA: [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md).  
ABI: [hg-render-abi.md](../engine/hg-render-abi.md) (`hg_render_page_svg`).

## Path B

`DocumentCore` → **UTF-8 SVG** → SwiftUI/AppKit **네이티브 페이지 호스트**.

- 임베드: `NSViewRepresentable` (`NativePageHostView`) + `NativePageRenderHost`
- **아님:** WKWebView, rhwp studio, postMessage bridge, **native-skia**, **PNG FFI**
- 문서 진실: `DocumentSession` + `hg_engine*` 하나. 호스트는 파생 미리보기만. **`EngineClient.current` 금지**
- PDF/인쇄 Phase1: 현행 plainText exporter (**변경 없음**)
- `showsRenderHostSketch` 기본 **false** → `StructuredTextView` 회귀 유지 (플래그 on 스모크는 별도)
- Views 크롬/L10n 리라이트 없음 · notarytool 없음

## 주입

`DocumentWindow`가 비어 있지 않은 문서에서 플래그가 켜지면:

`NativePageHostFactory.renderHostView(document:onOpenFailure:)` → `RenderHostView(host:)` + 오버레이로 셸 `NSViewRepresentable`.

플래그 off(기본)에서는 호스트를 만들지 않고 기존 본문을 쓴다.

## SVG preview (`hg_render_page_svg`)

`NativePageRaster.previewProvider` 제품 기본은 **같은 문서 세션**의 `DocumentSession.renderPageSvg(pageIndex: 0)` → Kit `RealEngine.renderPageSvg` → `hg_render_page_svg`.

버퍼는 Kit `HangyeolEngineSupport.takeBuffer`가 복사한 뒤 **`hg_free_buffer`**. 앱은 C 버퍼를 직접 free하지 않는다.

| 상태 | 동작 |
|------|------|
| attach | `onLoadingChange(true → false)`. 성공 시 `onReady` |
| 빈 문서 | `surface = empty`, 크래시 없음, `onOpenFailure` 없음 |
| `session.lastOpenError` | `onOpenFailure` 후 throw. `surface = failed` |
| Mock / 세션 미오픈 / `canRenderPagePreview == false` | provider `nil` → **placeholder** |
| throw / 빈 버퍼 / UTF-8 SVG 아님 | provider `nil` → **placeholder** (크래시 없음) |
| non-empty UTF-8 SVG (`<svg`) | `surface = .svg(data)` |
| PNG/SVG bytes (`presentPageImage`) | 테스트·프리뷰 주입. SVG 디코드 실패 시 placeholder |
| find/reveal | 표시용. 치환은 DocumentSession |
| 테스트 | `previewProvider` 주입 가능. `tearDown`은 제품 provider로 리셋 |

**native-skia forbidden.** PNG FFI 없음. C ABI를 앱에서 재정의하지 않음.

XCFramework 바이너리는 커밋하지 않는다. Mac에서 Vendor 재빌드 후 심링크 + `nm` `_hg_render_page_svg` ([vendor-rebuild.md](../engine/vendor-rebuild.md)).
