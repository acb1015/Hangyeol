# Renderer embed slot — Path B native page host

역할: **개발자2** 셸 설계. 프로토콜 정본은 **PR #48 (main)**.  
이 문서는 DocumentGroup 자리·소유권만 고정한다. **구현 스텁/래스터 없음.**

정본: [`Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift`](../../Apps/Hangyeol/Hangyeol/Views/HangyeolRenderHosting.swift)  
IA: [hop-ia-swiftui-draft.md](hop-ia-swiftui-draft.md) · 엔진 Path B: [renderer-spike-1pager.md](../engine/renderer-spike-1pager.md) · 셸: [hop-shell-checklist.md](hop-shell-checklist.md)

**제품 임베드 = Path B만.** `DocumentCore` → SVG/PNG 페이지 → SwiftUI/AppKit 네이티브 호스트.  
**금지:** WKWebView, rhwp studio, `postMessage`, Tauri.

---

## 잠긴 계약

1. **Injection** — 셸이 네이티브 페이지 뷰(`NSViewRepresentable` + SVG/Image/AppKit)를 소유한다. 프론트 `RenderHostView`는 슬롯·placeholder·콜백 구독만 (`host:`). 프론트는 페이지 호스트를 생성·래핑하지 않는다. `#46` `showsRenderHostSketch = false` 기본.
2. **Truth** — `DocumentSession` + `hg_engine*`가 문서 진실. 찾기/선택/표는 세션 API만. Views는 Kit/`RealEngine`/`postMessage`를 부르지 않는다. `listImages` 세션은 확장하지 않음 (#44).
3. **PDF/Print Phase1** — 기존 plainText `PDFExporter` / `PrintCoordinator`. 웹뷰 인쇄·SVG PDF 교체 없음.

---

## DocumentGroup 자리

```
DocumentGroup / HangyeolDocument
└── DocumentWindow                 프론트 크롬
    ├── EmptyStateView
    ├── StructuredTextView         showsRenderHostSketch == false (기본)
    └── RenderHostView(host:)      프론트 슬롯 (#48)
            └── 셸 NativePageHost  NSViewRepresentable  (Phase1 별 PR)
                    └── SVG/PNG pages from DocumentCore
```

열기·저장·UTI·드롭은 DocumentGroup + `FileOpening`. 호스트는 `attach(document:)`로 그 창의 세션에만 붙는다.

---

## 프로토콜 (정본 = #48, 복제하지 않음)

`HangyeolRenderHosting`: `attach` / `detach` / `isReady` · zoom/fit · selection · `find`/`reveal` · `onReady` / `onSelectionChange` / `onViewportChange` / `onOpenFailure` / `onLoadingChange`.

타입: `HangyeolTextSelection` (`utf16Location` / `utf16Length`) · `HangyeolFindOptions` · `HangyeolFindHit` · `HangyeolViewportState` (`fitMode`).

편집은 호스트에 두지 않는다 — `DocumentSession.insertText` / `deleteRange` / `replaceText` / `setCellText` / `listTables`.

Phase1 호스트 구현(attach 브리지 + 페이지 뷰)은 **별 PR**. 이 PR은 문서 + Mock 함정만.

---

## 비범위

- `HangyeolRenderHosting.swift` 추가/이동 (프론트 Views 정본)
- SVG 래스터라이저, WKWebView, `notarytool`, XCFramework 바이너리
- Views 크롬 리라이트
