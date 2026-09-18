# Renderer embed slot — Path B native page host

역할: **개발자2** 셸 설계. 이 PR은 **문서 + Mock 함정만**. 호스트 구현 정본은 **#50**.

| | 경로 | 정본 |
|--|------|------|
| Protocol | [`Views/HangyeolRenderHosting.swift`](../../Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift) | **#48** |
| Implementation | [`Render/NativePageRenderHost.swift`](../../Apps/Hangyeol/Hangyeol/Render/NativePageRenderHost.swift) · [`Render/NativePageHostView.swift`](../../Apps/Hangyeol/Hangyeol/Render/NativePageHostView.swift) · [`Render/NativePageRaster.swift`](../../Apps/Hangyeol/Hangyeol/Render/NativePageRaster.swift) (product `previewProvider` → **`hg_render_page_svg`** on this document's session; **no PNG FFI**, **no native-skia**) | **#50** + SVG wire |
| Phase1 노트 | [native-page-host-phase1.md](native-page-host-phase1.md) | **#50** |

IA: [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md) · 엔진: [renderer-spike-1pager.md](../engine/renderer-spike-1pager.md) · 셸: [hop-shell-checklist.md](hop-shell-checklist.md)

**제품 임베드 = Path B만.** `DocumentCore` → UTF-8 SVG (`hg_render_page_svg`) → AppKit/SwiftUI `NativePageHostView`. PNG FFI / native-skia 없음.  
**금지:** WKWebView, rhwp studio, `postMessage`, Tauri. `HangyeolRenderHosting.swift` / `NativePageRenderHost`를 이 PR에서 복제하지 않는다.

---

## 잠긴 계약

1. **Injection** — 셸 `#50` `NativePageRenderHost` + `NativePageHostView`. 프론트 `RenderHostView(host:)`는 슬롯·placeholder·콜백만. 프론트는 NSView를 생성·래핑하지 않는다. `showsRenderHostSketch = false` 기본.
2. **Truth** — `DocumentSession` + `hg_engine*`. 찾기/선택/표는 세션 API. Views는 Kit/`RealEngine`/`postMessage` 금지. `listImages` 세션 확장 없음 (#44).
3. **PDF/Print Phase1** — plainText `PDFExporter` / `PrintCoordinator`.

---

## DocumentGroup 자리

```
DocumentGroup / HangyeolDocument
└── DocumentWindow
    ├── StructuredTextView                 showsRenderHostSketch == false
    └── RenderHostView(host:)              Views (#48)
            └── NativePageRenderHost       Render/ (#50)
                    └── NativePageHostView `hg_render_page_svg` (page 0); Mock→placeholder
```

`attach(document:)`는 그 창의 `DocumentSession`에만 붙는다.

---

## 프로토콜 (#48, 복제 없음)

`HangyeolRenderHosting`: `attach` / `detach` / `isReady` · zoom/`fitWidth`/`fitPage` · `selection`/`select`/`clearSelection` · `find`/`reveal` · `onReady` / `onSelectionChange` / `onViewportChange` / `onOpenFailure` / **`onLoadingChange` 유지**.

타입: `HangyeolTextSelection` (`utf16Location` / `utf16Length`) · `HangyeolFindOptions` · `HangyeolFindHit` · `HangyeolViewportState` (`fitMode`).

편집은 호스트에 없음 — `DocumentSession.insertText` / `deleteRange` / `replaceText` / `setCellText` / `listTables`.

---

## 비범위 (이 PR)

- `Document/HangyeolNativePageHost*` (제거함 — #50이 정본)
- `HangyeolRenderHosting.swift` 추가/이동
- 풀 SVG 디코더, WKWebView, `notarytool`, Views 크롬/L10n
