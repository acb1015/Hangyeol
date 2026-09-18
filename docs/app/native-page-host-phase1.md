# Native page host Phase1 (Path B stub)

역할: **개발자2 (셸)** — `HangyeolRenderHosting` 구현 스텁.  
정본 프로토콜: `Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift` (**#48**, 재정의하지 않음).  
엔진 스파이크 배경: [renderer-spike-1pager.md](../engine/renderer-spike-1pager.md). IA: [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md).

## Path B

`DocumentCore` → SVG/PNG → SwiftUI/AppKit **네이티브 페이지 호스트**.

- 임베드: `NSViewRepresentable` (`NativePageHostView`) + `NativePageRenderHost`
- **아님:** WKWebView, rhwp studio, postMessage bridge
- 문서 진실: `DocumentSession` + `hg_engine*` 하나. 호스트는 파생 미리보기만
- PDF/인쇄 Phase1: 현행 plainText exporter (**변경 없음**)
- `showsRenderHostSketch` 기본 **false** → `StructuredTextView` 회귀 유지
- listImages 세션 확장 없음 · Views 크롬/L10n 리라이트 없음 · notarytool 없음

## 주입

`DocumentWindow`가 비어 있지 않은 문서에서 플래그가 켜지면:

`NativePageHostFactory.renderHostView(document:onOpenFailure:)` → `RenderHostView(host:)` + 오버레이로 셸 `NSViewRepresentable`.

플래그 off(기본)에서는 호스트를 만들지 않고 기존 본문을 쓴다.

## Phase1 한계

엔진 freeze 헤더에 `hg_render_*` / `render_page_svg_native`가 **없음**.  
`NativePageRaster.preview` **훅은 준비됨** (`Render/NativePageRaster.swift` injection seam). 기본 `previewProvider == nil` → `preview(from:)`는 `nil` → 비어 있지 않은 문서는 **placeholder**(빈 페이지 + SF Symbol).

**FFI wiring blocked** until 개발자1 `hg_render_*` merge. 이 훅에서 C 심볼 import / `hg_render_*` 호출 / 새 Vendor 링크를 하지 않는다.  
**native-skia forbidden** (engine §8 크기 참고용만. 제품 경로는 SVG).

| 상태 | 동작 |
|------|------|
| attach | `onLoadingChange(true → false)`. 성공 시 `onReady` |
| 빈 문서 | `surface = empty`, 크래시 없음, `onOpenFailure` 없음 |
| `session.lastOpenError` | `onOpenFailure` 후 throw. `surface = failed` |
| PNG/SVG bytes | `presentPageImage`가 있으면 `NSImage`로 그림. SVG 디코드 실패 시 placeholder |
| find/reveal | 표시용. 치환은 DocumentSession |
| TODO | 개발자1 `hg_render_*` merge **이후**에만 `previewProvider`에 DocumentCore SVG/PNG 연결. native-skia 금지 |

XCFramework 바이너리는 커밋하지 않는다. 실 래스터는 Vendor 재빌드 후 심링크.
