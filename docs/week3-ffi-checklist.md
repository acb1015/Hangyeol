# Week-3 FFI integration checklist

HangyeolKit tracks the engine C ABI. Kit **RealEngine** is live. **`Apps/Hangyeol` links HangyeolKit** and defaults to Real via `KitRealEngine` when the XCFramework is present.

`engine/include/hangyeol_engine.h` is the source of truth. Kit copy:
`Packages/HangyeolKit/Sources/CHangyeolEngine/include/hangyeol_engine.h`.

## This week

- [x] **Header sync** — Kit header matches `engine/include/hangyeol_engine.h` on main (symbols, comments, freeze mapping, edit API, `hg_table_info` / `hg_list_tables` / `hg_set_cell_text`, `hg_image_info` / `hg_list_images`, `hg_render_page_svg`).
- [x] Swift FFI stub declarations cover the synced ABI (`hg_plain_text` / `hg_replace_text` / `hg_save_hwpx` / `hg_insert_text` / `hg_delete_range` / `hg_list_tables` / `hg_set_cell_text` / `hg_list_images` / `hg_render_page_svg` / `hg_last_error`). Methods still throw `notLinked`; C stubs return `HG_UNSUPPORTED` / `NULL`. Table/image UI is frontend-owned (ABI only). See [image-meta.md](engine/image-meta.md). App page preview uses the same-session Kit path (`NativePageRaster`).
- [x] C target still compiles with no-op stubs for the new freeze symbols.
- [x] **Mock stays for rollback.** `MockEngine` is unchanged. `EngineClient.resetToMock()` always reinstalls it.

## Kit RealEngine (this package — XCFramework not committed)

- [x] Vendor path for a **local** XCFramework (`Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework` or env `HANGYEOL_ENGINE_XCFRAMEWORK`). Gitignored. Mac **재현 절차** is [docs/engine/xcframework.md — 로컬 재현 (2026-09-10)](engine/xcframework.md#로컬-재현-2026-09-10) (PR #14). Linux CI keeps the C stub.
- [x] HangyeolKit **`RealEngine`**: owns `hg_engine*`; live `hg_*` when the XCFramework is present (`HANGYEOL_ENGINE_LINKED`); `notLinked` fallback when absent. Freeze ↔ Kit mapping in Kit.

## App link + Mock → Real (this PR)

- [x] **Link HangyeolKit** from `Apps/Hangyeol` (xcodeproj local SPM product `HangyeolKit` → `../../Packages/HangyeolKit`). XCFramework still resolves only via Kit Vendor/env. **Do not commit** `.xcframework` / `.a` / `.dylib`.
- [x] **Default engine is Real** when `HangyeolKit.RealEngine.isLinked` (XCFramework present). Otherwise the app **falls back to Mock**.
- [x] App-side adapter **`KitRealEngine`**: holds Kit `RealEngine` session. App `DocumentModel` (blocks/paragraphs/tables) ≠ Kit `HangyeolKit.DocumentModel` (placeholder).
  - `open` → kit `open` + `plainText()` → UTF-8 lines mapped to app **paragraphs** (table cells flattened / plain for now).
  - `save` / `saveHwpx` → kit save on the **live session** (DocumentCore IR, clear-before-save). **Not** a re-encode of app JSON as HWPX.
  - Smoke replace: `EngineClient.replaceText` → kit `replaceText` on the open session. Find/Replace bar is wired when Real is active.

### Mock rollback

| Mechanism | How |
|-----------|-----|
| API | `EngineClient.resetToMock()` (process-level; keeps MockEngine working) |
| Launch env | **Default OFF.** `HANGYEOL_USE_MOCK=1` (also `true` / `YES`) only — Xcode scheme must not set this for normal Run |
| UserDefaults | `defaults write app.hangyeol.mac HANGYEOL_USE_MOCK -bool YES` then relaunch |

`resetToDefault()` restores the factory choice (Real if linked and not forced, else Mock).

### Hub-A Mac smoke (developer2, after merge)

Linux cannot run the app. On a Mac with Vendor XCFramework:

1. Open `fixtures/hub_hwpxlib_SimpleTable.hwpx` (manifest id **`hub-A`**).
2. Replace `1` → `HGPOC99` (Find/Replace, or `EngineClient.replaceText`).
3. Save HWPX (`File > Save` / kit `save` on the live session).
4. Expect `hp:linesegarray` count **0** (engine clear-before-save). Same gate as `engine` test `hub_a_replace_clear_before_save_roundtrip`.

Mac XCFramework 재현(`.a` / `nm hg_*`)은 PR #14 문서.

## Contracts

- **Clear-before-save.** `hg_save(..., HG_FILE_HWPX, ...)` and `hg_save_hwpx` walk DocumentCore sections / body paragraphs / table-cell paragraphs, `line_segs.clear()`, then `export_hwpx_native`. Result: `hp:linesegarray` count **0**. Kit `hg_save` is that same HWPX path, not a second writer. `.hwp` write is `SAVE_REJECTED` / `HG_UNSUPPORTED`.
- **Freeze ↔ Kit.** `ENCRYPTED` → `HG_PASSWORD`; `UNSUPPORTED_VERSION` / `SAVE_REJECTED` → `HG_UNSUPPORTED`; `CORRUPT` → `HG_CORRUPT`. F16 truncated/unknown → **CORRUPT**, not unsupported passthrough.
- **Toolchain.** rustc **≥ 1.89** (Hangyeol product pin).
- **Scope.** DocumentCore parser / serial / edit only. No renderer / layout / WASM UI, no Hangyeol-owned binary parser, no ZIP/XML product writer.

## Forbidden

- Committing `.xcframework` / `.a` / `.dylib`
- Breaking `MockEngine` / removing `EngineClient.resetToMock()`
- Changing `engine/include/hangyeol_engine.h` in the app-link PR
