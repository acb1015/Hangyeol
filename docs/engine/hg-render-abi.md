# `hg_render_page_svg` ABI (1-pager)

**Audience:** 개발자1 (engine) · 개발자2 (Views follow-up) · 팀장  
**Date:** 2026-09-18  
**Status:** product FFI. Spike PASS: [renderer-spike-s8-results.md](renderer-spike-s8-results.md).

Read-only **UTF-8 SVG** page preview on the same `hg_engine*`. **PNG / native-skia forbidden.** Save stays `hg_save` / `hg_save_hwpx` clear-before-save. App shell wiring: `KitRealEngine` / `DocumentSession.renderPageSvg` / `NativePageRaster.previewProvider` — **same document session only**, never `EngineClient.current`.

## One product symbol

§8 on hub-A: `render_page_svg_native(0)` and `render_page_svg_layer_with_profile_native(0, Screen)` were **byte-identical**. Screen is the product profile (print-equivalent layer path). **No second FFI** for legacy `render_page_svg_native` — that API is env-gated (`RHWP_RENDER_PATH`) and WASM-legacy; it is not a product switch.

```c
/* Read-only page preview. Does not mutate IR for save; save still clears line_segs. */
hg_status hg_render_page_svg(
    hg_engine *engine,
    uint32_t page_index,   /* 0-based */
    uint8_t **out_bytes,
    size_t *out_length     /* name matches hg_plain_text / hg_save, not out_len */
);
```

| Decision | Choice |
|----------|--------|
| Map | `DocumentCore::render_page_svg_layer_with_profile_native(page, RenderProfile::Screen)` |
| Buffer | Same as `hg_plain_text`: engine `leak_buffer` → caller `hg_free_buffer` |
| Session | Same `hg_engine*` (non-const pointer, like other read APIs). Not a second IR / `from_bytes` copy |
| Save | Unchanged. Render must not skip `line_segs.clear()` |
| OOR page | **`HG_CORRUPT` / `CORRUPT`** — addressing error, same as invalid insert/delete indexes. `HG_UNSUPPORTED` is format/version/HWP-write, not a bad index |
| PNG/skia | Not in the header. Do not enable `native-skia` |
| Kit | Header copy + Linux C stub. `RealEngine.renderPageSvg` is ABI coverage. App shell: `NativePageRaster` on this `DocumentSession` |

## Ownership

1. `hg_open` → one live `DocumentCore`.
2. `hg_render_page_svg` derives SVG from that IR. Layout caches may fill; **disk write is still only** `hg_save`(HWPX) / `hg_save_hwpx`.
3. On `HG_OK`, `*out_bytes` / `*out_length` are valid UTF-8 SVG (`<svg`…). Empty buffer length 0 is still `hg_free_buffer`-able.
4. Null engine / render failure (including `PageOutOfRange`) → `HG_CORRUPT`; out-params null/0.

## Vendor

`.xcframework` / `.a` / `.dylib` **not committed**. After this symbol lands, Mac: rebuild staticlib → XCFramework → **symlink** Vendor ([vendor-rebuild.md](vendor-rebuild.md)). Linux CI: C stub. `nm` must show `hg_render_page_svg` and must **not** show `hg_render_page_png` / skia product symbols.

## Non-goals (this PR)

- `hg_render_page_png` / `PngExportOptions` / `native-skia`
- `hg_render_page_svg_native` second symbol
- Hangyeol 셸 WYSIWYG / IME on the page canvas
- Vendor binary commits
