# HangyeolEngine.xcframework (local, not committed)

Copy or symlink the Mac-built XCFramework here so HangyeolKit links live `hg_*`:

```bash
# from the repo root
mkdir -p Packages/HangyeolKit/Vendor
ln -s /Users/acb/Hangyeol-xcf-build/engine/target/xcframework/HangyeolEngine.xcframework \
  Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework
```

Alternatively set `HANGYEOL_ENGINE_XCFRAMEWORK` to that path.

`Apps/Hangyeol` links HangyeolKit (local SPM). This Vendor path is how that app gets live `hg_*`. Do **not** commit `.xcframework`, `.a`, or `.dylib`. This directory is gitignored except this README.

See `Packages/HangyeolKit/README.md`. Mac 재현 절차 (PR #14): `docs/engine/xcframework.md` 절 **로컬 재현 (2026-09-10)**. `hg_*` 심볼이 바뀌면 [docs/engine/vendor-rebuild.md](../../../docs/engine/vendor-rebuild.md) — **바이너리는 커밋하지 않는다.**

## App SVG preview wiring (Mac checklist)

Path B `NativePageRaster` calls Kit `RealEngine.renderPageSvg` → `_hg_render_page_svg`. After a Mac rebuild, **symlink** Vendor (do not commit the binary) and confirm:

```bash
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# must include: _hg_render_page_svg  and  _hg_free_buffer
# must NOT include: _hg_render_page_png  / native-skia product symbols
```

`nm` 확인에 `hg_insert_text` / `hg_delete_range` / `hg_list_tables` / `hg_set_cell_text` / `hg_list_images` / `hg_render_page_svg` 가 포함돼야 한다. PNG / native-skia 심볼은 없어야 한다.
