# HangyeolKit

Swift FFI wrapper around the rhwp DocumentCore thin C ABI (`hg_*`).

**`Apps/Hangyeol` links this product** (local SPM). The app does **not** use Kit types as its document model. It wraps `RealEngine` in `KitRealEngine` (app `DocumentModel` paragraphs from `plainText()`; save is the live `hg_engine*` session). `MockEngine` remains for rollback (`EngineClient.resetToMock()`, `HANGYEOL_USE_MOCK=1`).

Week-3 order: **header sync → XCFramework vendor path → RealEngine (this package) → app link (done).** See [week-3 FFI checklist](../../docs/week3-ffi-checklist.md).

## Engine (팀장3 확정)

- **1순위:** rhwp **DocumentCore** 코어 서브셋 (parser / serial / edit). 페이지 미리보기는 UTF-8 SVG `hg_render_page_svg`만. PNG / native-skia 금지.
- **Toolchain:** rustc **≥ 1.89** (Hangyeol product pin; pinned rhwp cargo graph / `aes 0.9.3`; CI uses 1.93.1)
- **Save:** `hg_save(HWPX)` and freeze `hg_save_hwpx` **must** clear `line_segs` on body + table-cell paragraphs **before** serialize (`hp:linesegarray` count 0). The Rust cdylib implements that; Kit `RealEngine` calls those symbols (it does not re-implement the writer).

## What this package is

| Piece | Path | Role |
|-------|------|------|
| C ABI (synced) | `Sources/CHangyeolEngine/include/hangyeol_engine.h` | Kit: `hg_open` / `hg_save` / `hg_free_buffer` / `hg_close`. Freeze: `hg_plain_text` / `hg_replace_text` / `hg_save_hwpx` / `hg_insert_text` / `hg_delete_range` / `hg_list_tables` / `hg_set_cell_text` / `hg_list_images` / `hg_render_page_svg` / `hg_last_error` (`hg_table_info`, `hg_image_info`) |
| C stub | `Sources/CHangyeolEngine/hangyeol_engine.c` | Compiled **only when the XCFramework is absent**. Returns `HG_UNSUPPORTED` / `NULL` |
| C shim | `Sources/CHangyeolEngine/shim.c` | Compiled **only when the XCFramework is present**. Header-only clang module; no `hg_*` definitions |
| `RealEngine` | `Sources/HangyeolKit/RealEngine.swift` | Owns `hg_engine*`; live `hg_*` when linked; `notLinked` fallback when the stub is compiled in |
| `HangyeolEngineFFI` | `Sources/HangyeolKit/HangyeolEngineFFI.swift` | Stub façade (no session). Use `RealEngine` for live calls |

SPM does not mix Swift and C in one target, so the header lives in a clang target (`CHangyeolEngine`).

## Vendor XCFramework (do not commit the binary)

`Package.swift` links a **local** XCFramework when it finds one. The binary is gitignored.

**Preferred path** (copy or symlink from the Mac build):

```bash
mkdir -p Packages/HangyeolKit/Vendor
ln -s /Users/acb/Hangyeol-xcf-build/engine/target/xcframework/HangyeolEngine.xcframework \
  Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework
```

Or copy the directory to the same Vendor path.

Mac XCFramework **재현 절차** (deps → release copy/symlink, `nm hg_*`): [docs/engine/xcframework.md — 로컬 재현 (2026-09-10)](../../docs/engine/xcframework.md#로컬-재현-2026-09-10) (PR #14). `hg_*` 심볼이 바뀌면 [Vendor rebuild](../../docs/engine/vendor-rebuild.md) — **do not commit binaries**. This README does not duplicate that procedure.

**Env override:** `HANGYEOL_ENGINE_XCFRAMEWORK` — absolute path, or a path relative to `Packages/HangyeolKit`.

```bash
export HANGYEOL_ENGINE_XCFRAMEWORK=/Users/acb/Hangyeol-xcf-build/engine/target/xcframework/HangyeolEngine.xcframework
```

How `Package.swift` wires it:

| XCFramework | C target | Swift |
|-------------|----------|--------|
| Present **inside** this package (Vendor, or env path under `Packages/HangyeolKit`) | `shim.c` (header-only) | SPM `binaryTarget` `HangyeolEngine` + `HANGYEOL_ENGINE_LINKED`; `RealEngine` calls live `hg_*` |
| Present **outside** the package (env absolute path) | `shim.c` | Linker flags (`-L` slice / `-lhangyeol_engine`) + `HANGYEOL_ENGINE_LINKED` (SPM `binaryTarget` cannot escape the package) |
| Absent (Linux CI, clones without Vendor) | `hangyeol_engine.c` stub | `RealEngine` throws `notLinked` |

Never commit `.xcframework` / `.a` / `.dylib`. `Packages/HangyeolKit/Vendor/` is gitignored.

## RealEngine

`RealEngine` owns one `hg_engine*` (`hg_open` → `hg_close` in `deinit` / `close()`):

- `open` / `save` (`HangyeolEngine` protocol)
- `plainText` / `replaceText` / `saveHwpx` / `insertText` / `deleteRange` / `listTables` / `setCellText` / `listImages` / `renderPageSvg` / `lastError`

Error mapping (`hg_status` + `hg_last_error`):

| Freeze `hg_last_error` | Kit `hg_status` / `HangyeolKitError` |
|------------------------|--------------------------------------|
| `ENCRYPTED` | `HG_PASSWORD` / `.password` |
| `UNSUPPORTED_VERSION` | `HG_UNSUPPORTED` / `.unsupported` |
| `SAVE_REJECTED` | `HG_UNSUPPORTED` / `.unsupported` |
| `CORRUPT` | `HG_CORRUPT` / `.corrupt` |

When the real library is linked, `RealEngine` does **not** throw `notLinked`.

Mac XCFramework 재현은 [로컬 재현 (PR #14)](../../docs/engine/xcframework.md#로컬-재현-2026-09-10). Linux cannot run the Apple XCFramework.

`Apps/Hangyeol` links this product and uses `KitRealEngine` when `RealEngine.isLinked`; otherwise Mock. Do not commit `.xcframework` / `.a` / `.dylib`.

## Status kinds (exactly four)

Defined as `hg_status` / `HangyeolStatus`:

| Name | Meaning | Freeze |
|------|---------|--------|
| `HG_OK` / `.ok` | Success | — |
| `HG_UNSUPPORTED` / `.unsupported` | Format, version, or operation out of scope | `UNSUPPORTED_VERSION`, `SAVE_REJECTED` |
| `HG_CORRUPT` / `.corrupt` | Truncated or malformed document (F16 truncated/unknown) | `CORRUPT` |
| `HG_PASSWORD` / `.password` | Encrypted / password-protected (decrypt forbidden) | `ENCRYPTED` |

## Tables (ABI sync only)

`hg_list_tables` / `hg_set_cell_text` (`hg_table_info`) are **ABI coverage** for engine PR #19. Kit maps `index` + `rows`/`cols` onto cell addressing; errors use the freeze ↔ Kit table above (`CORRUPT` for invalid table/row/col).

**Table UI is frontend-owned.** This package does not render TableBlock, edit grids, or change `Apps/Hangyeol` Views / Sheets. Rebuild a local XCFramework from current `engine/` so Vendor exports the new symbols; Linux CI keeps the C stub.

## Images (ABI sync only)

`hg_list_images` (`hg_image_info`) is **ABI coverage** for engine PR #32. Kit `RealEngine.listImages()` maps `index` + `section`/`paragraph`/`control` + size/format meta onto `ImageInfo`. Not a BinData extract or keep-on-save API. See [docs/engine/image-meta.md](../../docs/engine/image-meta.md).

**Image UI is frontend-owned.** This package does not render ImageBlock or change `Apps/Hangyeol` Views / Sheets. After a local Vendor rebuild, Mac `nm` should show `_hg_list_images`.

## Page preview SVG (ABI sync only)

`hg_render_page_svg` is **ABI coverage** for the engine SVG preview FFI. Kit `RealEngine.renderPageSvg(pageIndex:)` maps to layer + Screen. Out-of-range page is `CORRUPT`. PNG / native-skia are not in this header. See [docs/engine/hg-render-abi.md](../../docs/engine/hg-render-abi.md).

**Page canvas UI is frontend-owned.** `Apps/Hangyeol` `NativePageRaster` / `KitRealEngine.renderPageSvg` forward to this method on the **same document session**. After a local Vendor rebuild, Mac `nm` should show `_hg_render_page_svg` and must not show PNG/skia product symbols. Do not commit `.xcframework` / `.a` / `.dylib`.

## What this package is not

- Not a committed XCFramework / `.a` / `.dylib`
- Not the app `DocumentModel` (blocks/tables). Kit `DocumentModel` is a file-type placeholder; the app adapter maps `plainText()`
- Not table UI — Views / TableBlock stay in the app; this is header + Swift wrapper sync only
- Not image UI — Views / ImageBlock stay in the app; this is header + Swift wrapper sync only
- Not page-canvas UI — Views / NativePageHost stay in the app; this is header + Swift wrapper sync only
- Not a replacement that deletes `MockEngine` — the app keeps Mock for rollback
