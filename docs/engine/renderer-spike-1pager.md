# Renderer spike 1-pager (HOP-guided)

**Audience:** 개발자1 (engine) · 팀장 승인용  
**Date:** 2026-09-18  
**Status:** design only — **코드 실험은 팀장 승인 후**. 이 PR은 문서만.

Hangyeol을 [HOP](https://github.com/golbin/hop) **가이드**로 쓸 수 있는 한글 앱으로 완성하는 트랙. HOP를 fork/치환하지 않는다. Bundle ID `app.hangyeol.mac` · **HWPX 기본 저장** · DocumentCore FFI · clear-before-save는 유지한다. 2026-09-18 팀장: 기존 렌더러/조판/WASM **금지 해제**, rhwp render path를 제품 완성 트랙으로 연다. **대형 재작성 금지** — 합의 전 설계.

## 1. Background / goal / non-goals

**오늘 Hangyeol:** Swift macOS 셸 + Kit `RealEngine` + `engine/` thin cdylib (`hg_*` → `rhwp::document_core::DocumentCore`, pin `cac9b4f7cc743535cd7c00fe4f286abd67e7145b`, `default-features = false`). 화면은 구조화 본문·표 (`hg_plain_text`). 저장은 `hg_save` / `hg_save_hwpx`만 — `line_segs.clear()` 후 `export_hwpx_native` → `hp:linesegarray` = 0. `.hwp` 쓰기는 `SAVE_REJECTED`.

**Goal:** 같은 `hg_engine*` IR에서 **페이지 미리보기**(조판 비트맵/SVG)를 열어, 한/글 앱으로 보이게 하는 **최소 native render 경로**를 스파이크로 합의한다. HOP studio는 **참조/oracle**, 제품 임베드가 아니다.

**Non-goals (스파이크 1):**

- HOP fork, Hangyeol 셸을 HOP/Tauri/WKWebView studio로 교체, Bundle ID 변경
- Hangyeol 셸 WYSIWYG 재작성 · 캐럿 IME를 페이지 캔버스에 올리는 편집기
- 기본 rhwp export / HOP HWP 저장 경로로 Hangyeol HWPX 계약을 바꿈
- Vendor XCFramework 바이너리 커밋 · 대형 `engine/src` 재작성

## 2. HOP rhwp upstream boundary map

HOP `docs/architecture/UPSTREAM.md` · `docs/DEVELOPMENT.md` 기준 (2026-09-18 fetch):

- `third_party/rhwp` = **read-only** submodule → `https://github.com/edwardkim/rhwp.git`. 제품 동작을 이 폴더에 패치하지 않음.
- `apps/desktop/rhwp-adapter` (`hop-rhwp-adapter`) = 유일한 native `rhwp` import. `DocumentCore` re-export, optional feature `native-skia` → `PngExportOptions`, PDF는 `rhwp::renderer::pdf::svgs_to_pdf_with_options`.
- `apps/studio-host` = `rhwp-studio` overlay. Vite alias + `config/rhwp-studio-overrides.json`으로 shadow. HOP 코드는 desktop/studio-host에만.
- `apps/studio-host/src/host/renderer-session.ts` `createRendererSession()`: `{ backend: 'canvas2d', source: 'default' }`. CanvasKit factory는 명시 throw (`CanvasKit is not enabled by the HOP renderer policy`).
- 렌더 프로토콜: upstream이 `CanvasView` / `RendererSession` / overlay·ruler; HOP는 Canvas2D backend 선택 + `prepareDocumentLoad()` → `loadDocument()` lifecycle만.
- 제품 레이어: Tauri 2 셸, native menu, Rust document session, atomic save, SVG→PDF, WebView print. **HOP는 HWPX 저장을 아직 차단** (열기만). Hangyeol과 정반대.
- DEVELOPMENT: 큰 문서는 WASM mirror 구간이 남아 **native-authoritative**가 목표. WASM 재생성은 `apps/studio-host/vendor/rhwp-core` (submodule `wasm-pack`).
- HOP는 upstream `main.ts` 전체를 실행하지 않음 → optional CanvasKit host wiring은 자동 채택하지 않음.

Hangyeol은 submodule/studio overlay가 없다. 동일 rhwp git pin을 Cargo로만 소비한다.

## 3. Path A: rhwp WASM + Canvas (HOP-like WebView / studio overlay)

WKWebView(또는 Tauri)에 `rhwp-studio` + WASM `rhwp-core`를 올리고, HOP처럼 `RendererSession` Canvas2D를 강제하는 경로.

- **장점:** HOP와 같은 시각 oracle에 가깝다. studio caret/overlay/table chrome을 그대로 빌릴 수 있다.
- **단점 (Hangyeol):** Swift `DocumentSession`/`hg_engine*`과 WASM IR이 **이중 소유**. HOP 본인도 WASM mirror를 부채로 적고 있다. HWPX 저장은 native `hg_save*`여야 하므로 WebView 쪽 serializer를 쓰면 계약이 깨진다. IME는 WebKit 한/영 이슈(HOP Linux 노트와 동일 계열). App Store/sandbox에서 WASM·JIT·대용량 `vendor/rhwp-core` 부담. Hangyeol 셸 WYSIWYG 재작성에 가깝다 → 스파이크 1 **제품 임베드 제외**.
- **쓸 곳:** Mac에서 HOP/studio를 **밖으로** 띄워 hub-A/B 스크린샷 oracle. 프로세스 안에 넣지 않음.

## 4. Path B: Native (DocumentCore → SVG/PNG/Skia page bitmaps → SwiftUI/AppKit)

같은 프로세스의 `DocumentCore`에서 페이지를 뽑아 Swift가 표시.

핀된 rhwp `src/document_core/queries/rendering.rs` (검증됨):

| API | Gate | Spike 1 역할 |
|-----|------|----------------|
| `render_page_svg_native` / `render_page_svg_layer_with_profile_native` | 항상 (feature 없음) | **1순위 실험.** layer+`RenderProfile::Screen`이 인쇄 등가에 가깝다. WASM `renderPageSvg`는 env가 없어 **legacy SVG**로 떨어짐. |
| `render_page_png_native` / `PngExportOptions` | `native-skia` + non-wasm | 2순위. HOP adapter가 같은 심볼을 재export. `skia-safe` + `embed-icudtl` → XCFramework 급증. |
| `rhwp::renderer::pdf::svgs_to_pdf_with_options` | native PDF | Hangyeol 인쇄/PDF 후속. 스파이크 1 범위 밖. |

앱 쪽은 `NSImage`/`Image`로 PNG, 또는 SVG → 비트맵. **편집은 기존 `hg_*`**. 페이지 뷰는 derived preview.

## 5. Recommendation: Path B (native page render)

**스파이크 1은 Path B.** Hangyeol 소유권(Swift + `hg_engine*` + HWPX clear-before-save)과 맞고, HOP가 지향하는 native-authoritative와도 같다. Path A studio는 **oracle**로만 둔다.

근거가 Path A로 기울면: pin에서 `render_page_svg_*`가 허브 픽스처에 죽거나, SVG-only 바이너리 증가가 App Store 불가 수준일 때 — 그때도 HOP 임베드가 아니라 **API/핀 재조사**가 먼저다.

**Risks**

- **IME:** 스파이크 1은 미리보기라 본문 IME는 기존 Swift 필드에 남긴다. 비트맵 위 캐럿은 나중 단계. Path A는 WebView 한/영 리스크를 제품에 가져온다.
- **Font:** rhwp 조판은 문서 폰트 + 시스템/경로 폰트. Hangyeol은 **함초롬 무단 번들 금지**. 없으면 대체 글리프·리플로우 불일치. `render_page_png_native_with_fonts` / SVG `--font-path`는 로컬 실험만. HOP PDF fallback은 `Noto Sans KR` — Hangyeol이 그걸 넣을지는 별 정책.
- **Dual ownership:** WASM mirror + `DocumentCore` 동시 편집 금지. 렌더는 같은 `hg_engine` IR의 읽기 뷰.
- **HWPX vs HOP:** HOP는 HWPX 저장 차단·HWP 저장. Hangyeol은 HWPX 기본 + `hp:linesegarray` = 0. 렌더가 `line_segs`를 채워도 **저장은 반드시 `hg_save` / `hg_save_hwpx`**. 기본 `export_hwpx_native`(clear 없이) 금지.
- **Binary size:** SVG만으로도 layout/pagination/SvgRenderer가 `.a`에 산다 (지금 unused면 LTO로 떨어질 수 있음). `native-skia`는 스파이크 1 기본값 아님. 켜기 전 size delta 측정.
- **macOS App Store / sandbox:** staticlib Path B가 WASM/CanvasKit/WKWebView 제품 임베드보다 단순. 폰트 디렉터리 읽기는 entitlement. `wasm32` / wasm-bindgen을 XCFramework에 넣지 말 것. JIT WASM은 리뷰 리스크.

## 6. DocumentCore edit API ↔ render session: single byte ownership

**산식:** 창 하나 = `DocumentSession` 하나 = `hg_engine*` 하나 = live `DocumentCore` IR 하나.

| 역할 | 소유 | 금지 |
|------|------|------|
| Live 문서 | `hg_open` 이후 `hg_engine.core` | 디스크 바이트를 live로 취급, WASM 미러, 앱 JSON 재인코드 |
| Render | IR에서 페이지 SVG/PNG **파생**. 캐시 키 = engine ptr + generation | 렌더 세션이 별도 `from_bytes` 복사본을 오래 붙잡고 편집과 어긋남 |
| Save | **`hg_save`(HWPX) / `hg_save_hwpx`만** (clear-before-save) | rhwp 기본 export, HOP HWP save, ZIP/XML, studio format-save |

**Invalidate / rebind:** 성공한 `hg_insert_text` / `hg_delete_range` / `hg_replace_text` / `hg_set_cell_text` 마다 generation++ → 페이지 캐시 drop → 다음 render는 **같은** `hg_engine`에서 재조회. 편집 API 시그니처 변경 없음.

렌더는 저장이 아니다. 조판이 `line_segs`를 채워도 디스크에 쓰는 경로는 clear-before-save 한 곳.

## 7. Vendor XCFramework policy

변함없음. `.xcframework` / `.a` / `.dylib` **커밋 금지**. Mac 로컬 심링크만.

절차 정본: [xcframework.md](xcframework.md) · [vendor-rebuild.md](vendor-rebuild.md) · `Packages/HangyeolKit/Vendor/README.md`.

`hg_render_*`(가칭)를 나중에 열면 Mac에서 Vendor **재빌드 후 심링크**. Linux CI는 C stub. `native-skia`를 켜도 산출물은 gitignore.

## 8. Spike verification plan (lead 승인 후, 최소 코드)

이 문서는 구현이 아니다. 승인 후 **작은** 실험만:

1. `engine/` 임시 테스트(제품 `hg_*` 헤더 동결 유지): hub-A에 `render_page_svg_native(0)` 및 `render_page_svg_layer_with_profile_native(0, Screen)` → SVG non-empty. **FFI/앱 연결 없음.**
2. 같은 픽스처를 HOP studio Canvas2D(또는 rhwp-studio)와 눈으로 대조 — oracle, embed 아님.
3. 렌더 **직후** 기존 `hub_a_replace_clear_before_save_roundtrip` / hub-B keep-on-save: `hp:linesegarray` = 0 유지.
4. release `.a` size: 현재 vs SVG 호출 링크 vs (참고) `native-skia`. 기본 실험은 SVG.
5. 하지 않음: Vendor 커밋, WKWebView studio 임베드, Bundle ID/`hg_save` 계약 변경, Hangyeol 셸 WYSIWYG.

합격: SVG 페이지 1장 + 저장 게이트 유지 + size 숫자. 그다음 FFI 심볼은 별도 합의.

## 9. Sources

**HOP (fetch 2026-09-18, `main`):**

- [README.md](https://github.com/golbin/hop/blob/main/README.md)
- [docs/DEVELOPMENT.md](https://github.com/golbin/hop/blob/main/docs/DEVELOPMENT.md) — HWPX save 차단, WASM mirror, native-authoritative
- [docs/architecture/UPSTREAM.md](https://github.com/golbin/hop/blob/main/docs/architecture/UPSTREAM.md)
- `apps/desktop/rhwp-adapter/src/lib.rs`, `Cargo.toml` (`native-skia`, `rhwp::renderer::pdf`)
- `apps/studio-host/src/host/renderer-session.ts` (Canvas2D, CanvasKit disabled)
- `.gitmodules` → `third_party/rhwp`

**Hangyeol:**

- [engine/README.md](../../engine/README.md) · [xcframework.md](xcframework.md) · [vendor-rebuild.md](vendor-rebuild.md) · [image-meta.md](image-meta.md)
- [known-limitations.md](../known-limitations.md) · [rhwp-core-subset-gate.md](../rhwp-core-subset-gate.md) · [engine-priority-2026-09-10.md](../engine-priority-2026-09-10.md)
- `engine/src/lib.rs` (`hg_save` / `hg_save_hwpx` clear-before-save), `engine/Cargo.toml` (rhwp pin)
- 팀장 2026-09-18: renderer ban lift, HOP-guided, no HOP fork, HWPX default, no binary commits

**rhwp pin `cac9b4f7…`:** `src/document_core/queries/rendering.rs` — `render_page_svg_native`, layer+profile SVG, `native-skia` PNG (`PngExportOptions`).
