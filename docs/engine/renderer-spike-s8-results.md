# Renderer spike §8 results (Path B native SVG)

**Date:** 2026-09-18  
**Pin:** rhwp `cac9b4f7cc743535cd7c00fe4f286abd67e7145b` (`default-features = false`)  
**Plan:** [renderer-spike-1pager.md](renderer-spike-1pager.md) §8  
**Verdict:** **PASS** (engine tests + size table). HOP visual oracle remains **Mac-manual**.

FFI header: `hg_render_page_svg` is the follow-on product ABI ([hg-render-abi.md](hg-render-abi.md)). This spike itself did not open FFI. Default product features stay SVG-only (no `native-skia`).

## PASS/FAIL

| # | Gate | Result | Evidence |
|---|------|--------|----------|
| 1 | hub-A page0 `render_page_svg_native(0)` → SVG non-empty | **PASS** | `engine/tests/render_spike.rs` `hub_a_page0_svg_native_and_layer_screen_non_empty`. Artifact (gitignored): `engine/testdata/out/hub-A-page0-svg-native.svg` (5286 bytes, `<svg>` + SimpleTable cells 1–5). |
| 1b | hub-A page0 `render_page_svg_layer_with_profile_native(0, RenderProfile::Screen)` → SVG non-empty | **PASS** | Same test. Artifact: `hub-A-page0-svg-layer-screen.svg` (5286 bytes). On this fixture the two SVGs were **byte-identical**. |
| 2 | HOP studio Canvas2D visual compare (oracle, not embed) | **Mac-manual** | Not in CI. Queue below. Do not vendor HOP / studio. |
| 3 | Render then hub-A replace + clear-before-save → `hp:linesegarray` = 0 | **PASS** | `hub_a_render_then_replace_clear_before_save`. Token `HGPOC99` survives reopen. Existing `hub_a_replace_clear_before_save_roundtrip` still green. |
| 3b | Render then hub-B keep-on-save | **PASS** | `hub_b_render_then_keep_on_save`. BinData names/bytes preserved; image meta stable; `hp:linesegarray` = 0. Existing `hub_b_image_keep_on_save_clear_before_save_roundtrip` still green. |
| 4 | release `.a` size table | **PASS** | Linux `x86_64-unknown-linux-gnu` numbers below. Mac `aarch64-apple-darwin` **not measured** (this host is Linux). |
| 5 | C ABI freeze | **PASS** | `ffi_header_frozen_no_hg_render`. `nm` on all three `.a` builds: `hg_render_*` **absent**. Existing `hg_*` set unchanged. |

Existing `engine/tests/gates.rs` product gates were not modified and still pass.

## `.a` size (Linux x86_64)

**Host:** Linux `x86_64-unknown-linux-gnu` (kernel 6.12.94+), rustc **1.93.1** (`01f6ddf75`).  
**Command:** `engine/scripts/measure-staticlib-size.sh` → `cargo rustc --release -- --crate-type staticlib`.  
**Profile:** hangyeol_engine default release (no crate-level LTO). Binaries are gitignored.

| Label | Features | Path | Bytes | MiB | Δ vs baseline |
|-------|----------|------|-------|-----|----------------|
| baseline (product default) | *(none)* | `engine/target/size-baseline/release/libhangyeol_engine.a` | 102 640 598 | 97.886 | — |
| SVG-linked | `svg-size-probe` | `engine/target/size-svg/release/libhangyeol_engine.a` | 102 641 856 | 97.887 | **+1 258 B** |
| native-skia (reference) | `native-skia,svg-size-probe` | `engine/target/size-skia/release/libhangyeol_engine.a` | 165 160 054 | 157.509 | **+62 519 456 B (~+59.6 MiB)** |

**Notes**

- Product default does **not** enable `svg-size-probe` or `native-skia`. Tests call DocumentCore SVG APIs from `tests/render_spike.rs` only.
- Without LTO, rhwp is a single crate: layout / SvgRenderer already land in the baseline `.a`. Forcing SVG calls adds ~1 KB (the probe itself), not a second renderer.
- `native-skia` is optional size reference only. It pulled `skia-safe` 0.99 (`embed-icudtl`) and grew the `.a` by ~60 MiB. **Do not turn this on for Vendor / XCFramework.**
- Linux `native-skia` link needed `libstdc++`, `libfreetype`, `libfontconfig`, and `RUSTFLAGS=-C link-arg=-L/usr/lib/gcc/x86_64-linux-gnu/13` so rust-lld could find `libstdc++`.
- Mac aarch64 `.a` is still the product Vendor path; re-run the same script on a Mac with `HANGYEOL_STATICLIB_TARGET=aarch64-apple-darwin` when a number is needed for App Store.

Reproduce:

```bash
# baseline
CARGO_TARGET_DIR=engine/target/size-baseline \
  HANGYEOL_STATICLIB_LABEL=baseline \
  engine/scripts/measure-staticlib-size.sh

# SVG-linked (optional probe, not product)
CARGO_TARGET_DIR=engine/target/size-svg \
  HANGYEOL_STATICLIB_LABEL=svg-size-probe \
  HANGYEOL_STATICLIB_FEATURES=svg-size-probe \
  engine/scripts/measure-staticlib-size.sh

# native-skia reference (optional; extra system libs)
CARGO_TARGET_DIR=engine/target/size-skia \
  HANGYEOL_STATICLIB_LABEL=native-skia \
  HANGYEOL_STATICLIB_FEATURES=native-skia,svg-size-probe \
  engine/scripts/measure-staticlib-size.sh
```

## HOP oracle (Mac manual queue)

CI does not run HOP / rhwp-studio. Path A WASM/studio stays **oracle only** — not a product embed.

**Queue (Mac operator):**

1. Regenerate spike SVGs (gitignored):

   ```bash
   cargo test --manifest-path engine/Cargo.toml hub_a_page0_svg_native_and_layer_screen_non_empty -- --exact
   ```

   Outputs: `engine/testdata/out/hub-A-page0-svg-native.svg` and `hub-A-page0-svg-layer-screen.svg`.

2. Open the same fixture in HOP desktop (or rhwp-studio Canvas2D), **outside** Hangyeol: `fixtures/hub_hwpxlib_SimpleTable.hwpx`.

3. Compare page 1 (0-based page 0) against the layer+`Screen` SVG: table grid, cells `1`–`5`, page size. Operator judgment — Hangyeol does not vendor HOP screenshots.

4. Optional: hub-B `fixtures/hub_hwpxlib_SimplePicture.hwpx` picture placement vs Hangyeol SVG (not required for this spike’s PASS).

Do **not** add WKWebView studio, Tauri, or `vendor/rhwp-core` WASM to Hangyeol.

## What this does not open

- Vendor `.xcframework` / `.a` / `.dylib` commits.
- `native-skia` on the default lib.
- Hangyeol 셸 WYSIWYG / IME on the page canvas.

Product FFI after this PASS: [hg-render-abi.md](hg-render-abi.md) (`hg_render_page_svg`).

## Tests

```bash
cargo test --manifest-path engine/Cargo.toml -- --include-ignored
```

Spike-only:

```bash
cargo test --manifest-path engine/Cargo.toml --test render_spike
```
