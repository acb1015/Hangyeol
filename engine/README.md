# hangyeol_engine

Thin Rust **cdylib** wrapping **`rhwp::document_core::DocumentCore`** only.

- **rustc ≥ 1.89** (product pin after PR #9: pinned rhwp cargo graph / `aes 0.9.3`)
- `Cargo.toml` `rust-version` is still `1.88` (crate field only). Do not build the engine below 1.89.
- CI uses **1.93.1** (`.github/workflows/engine.yml`; matches rhwp `rust-toolchain.toml`).
- parser / serial / edit via DocumentCore
- **no** Hangyeol-owned OLE/HWP binary parser
- **no** ZIP/XML hand-edit product path
- **no** renderer / layout / WASM UI **FFI** exports (product ABI today; `hg_render_*` not opened). §8 Path B spike tests call DocumentCore SVG APIs only: [renderer-spike-s8-results.md](../docs/engine/renderer-spike-s8-results.md). Design: [renderer-spike-1pager.md](../docs/engine/renderer-spike-1pager.md)

Pinned rhwp git rev (verified in this crate):
`cac9b4f7cc743535cd7c00fe4f286abd67e7145b`

## C ABI

Header: [`include/hangyeol_engine.h`](include/hangyeol_engine.h)

This header is a **superset** of HangyeolKit
`Packages/HangyeolKit/Sources/CHangyeolEngine/include/hangyeol_engine.h`
(Kit `hg_open` / `hg_save` / `hg_free_buffer` / `hg_close`) plus kickoff freeze
edit symbols (`hg_plain_text` / `hg_replace_text` / `hg_save_hwpx` /
`hg_insert_text` / `hg_delete_range` / `hg_list_tables` / `hg_set_cell_text` /
`hg_list_images` / `hg_last_error`). Same names — not a third scheme. `hg_insert_text` /
`hg_delete_range` are product gates (known para/offset → `hg_plain_text` →
`hg_save_hwpx` clear-before-save → 0 `hp:linesegarray` → reopen).

`hg_list_tables` / `hg_set_cell_text` walk DocumentCore IR only. Kit maps
`hg_table_info.index` + `rows`/`cols` onto TableBlock cell addressing.

`hg_list_images` walks `Control::Picture` (body, then nested cell pictures) and
returns index + size/format meta (`hg_image_info`). Hub-B list gate. Not a
BinData extract API. Keep-on-save of ZIP `BinData/` on the existing
`hg_save_hwpx` clear-before-save path is a hub-B **product gate**
([image-meta.md](../docs/engine/image-meta.md)).

| Freeze code | Kit `hg_status` |
|-------------|-----------------|
| `ENCRYPTED` | `HG_PASSWORD` |
| `UNSUPPORTED_VERSION` | `HG_UNSUPPORTED` |
| `SAVE_REJECTED` | `HG_UNSUPPORTED` |
| `CORRUPT` | `HG_CORRUPT` |

F16 truncated / unknown magic → **`CORRUPT` / `HG_CORRUPT`**, not a vague unsupported passthrough.

### Clear-before-save

`hg_save(..., HG_FILE_HWPX, ...)` and `hg_save_hwpx` walk
`DocumentCore::document_mut()` sections → body paragraphs → table cell
paragraphs and call `line_segs.clear()`, then `export_hwpx_native`.
Default rhwp export **leaves** `hp:linesegarray`; Hangyeol requires 0 after save.
Kit `hg_save` **must** use this HWPX path (it does in this cdylib).

`.hwp` write is `SAVE_REJECTED` / `HG_UNSUPPORTED` (HWPX-only save).

## Build / test

```bash
# rustc ≥ 1.89 (CI: 1.93.1)
rustc --version

cargo test --manifest-path engine/Cargo.toml
# §8 SVG spike (DocumentCore APIs, no hg_render_*):
cargo test --manifest-path engine/Cargo.toml --test render_spike
```

### Mac Hangul smoke artifacts

| Location | Path |
|----------|------|
| Owner Downloads (already copied) | `~/Downloads/SimpleTable-rhwp-replaced-cleared.hwpx` |
| Repo generate path (gitignored) | `engine/testdata/out/SimpleTable-cleared-replaced.hwpx` |
| Insert product gate (gitignored) | `engine/testdata/out/SimpleTable-inserted.hwpx` |
| Delete product gate (gitignored) | `engine/testdata/out/SimpleTable-deleted.hwpx` |
| Hub-B keep-on-save product gate (gitignored) | `engine/testdata/out/SimplePicture-keep-on-save.hwpx` |

Regenerate without the full suite:

```bash
cargo test --manifest-path engine/Cargo.toml hub_a_replace_clear_before_save_roundtrip -- --exact
cargo test --manifest-path engine/Cargo.toml hub_a_insert_text_clear_before_save_roundtrip -- --exact
cargo test --manifest-path engine/Cargo.toml hub_a_delete_range_clear_before_save_roundtrip -- --exact
cargo test --manifest-path engine/Cargo.toml hub_b_image_keep_on_save_clear_before_save_roundtrip -- --exact
cargo test --manifest-path engine/Cargo.toml --test render_spike
```

The derived HWPX is Apache-2.0 (hub-A / hwpxlib). It is **not** committed. Hangul open smoke is Mac-manual on the Downloads copy (or copy the generated file onto the Mac).

### Apple Silicon XCFramework / staticlib

macOS `aarch64-apple-darwin` (Mac host required; Linux CI cannot emit Apple binaries):
[docs/engine/xcframework.md](../docs/engine/xcframework.md).
When `hg_*` symbols change, rebuild Vendor locally — **do not commit binaries**:
[docs/engine/vendor-rebuild.md](../docs/engine/vendor-rebuild.md).
If `libhangyeol_engine.a` lands only under `release/deps/`, copy or symlink it to `release/` before `xcodebuild -create-xcframework` (`engine/scripts/copy-staticlib-to-release.sh`).

## Layout

```
engine/
  Cargo.toml
  src/lib.rs          # FFI + DocumentCore wrapper
  src/error.rs        # freeze ↔ Kit mapping
  include/hangyeol_engine.h
  tests/gates.rs      # hub-A replace/insert/delete/table+clear, hub-B image list + keep-on-save, F14, F16
  tests/render_spike.rs  # §8 Path B: hub-A SVG + render-then-save (no FFI)
  testdata/out/       # gitignored generated HWPX / spike SVG
  scripts/copy-staticlib-to-release.sh  # deps → release .a (macOS XCFramework)
  scripts/measure-staticlib-size.sh     # §8 release .a size table (host or --target)
```
