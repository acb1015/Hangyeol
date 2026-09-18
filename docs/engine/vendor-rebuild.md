# Vendor XCFramework rebuild (when `hg_*` symbols change)

엔진 C ABI 심볼이 바뀌면 HangyeolKit **Vendor XCFramework를 로컬에서 다시 빌드**한다. **`.xcframework` / `.a` / `.dylib` 는 커밋하지 않는다.**

이 문서는 재빌드 *시점*만 적는다. Apple Silicon 빌드·`nm` 재현의 정본은 [xcframework.md 로컬 재현](xcframework.md#로컬-재현-2026-09-10)이다.

## 언제

`engine/include/hangyeol_engine.h` 또는 `engine/src/lib.rs`의 `hg_*` export가 바뀐 뒤, Mac에서 Kit이 live 심볼을 쓰려면 Vendor를 갈아끼운다. Linux CI는 C stub을 유지한다.

`hg_render_page_svg`가 추가되면 **이 절차를 다시 돌린 뒤 Vendor 심링크만** 갱신한다. `.xcframework` / `.a` / `.dylib` 는 커밋하지 않는다. 정본 ABI: [hg-render-abi.md](hg-render-abi.md). 앱 미리보기 배선은 [native-page-host-phase1.md](../app/native-page-host-phase1.md).

## 절차 (Mac)

1. [xcframework.md](xcframework.md) **로컬 재현 (2026-09-10)** 그대로 `aarch64-apple-darwin` staticlib을 만든다 (`MACOSX_DEPLOYMENT_TARGET=14.0`, rustc ≥ 1.89).
2. top-level `.a`가 없으면 `engine/scripts/copy-staticlib-to-release.sh`.
3. `xcodebuild -create-xcframework` → `engine/target/xcframework/HangyeolEngine.xcframework` (gitignore).
4. Vendor에 심볼릭 링크 또는 복사 (바이너리 커밋 금지):

```bash
mkdir -p Packages/HangyeolKit/Vendor
ln -sf /path/to/HangyeolEngine.xcframework \
  Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework
```

5. `nm` 확인 — insert / delete / table / image-list 포함:

```bash
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# 기대: hg_open hg_save hg_save_hwpx hg_plain_text hg_replace_text
#       hg_insert_text hg_delete_range hg_list_tables hg_set_cell_text
#       hg_list_images hg_render_page_svg hg_close hg_free_buffer hg_last_error
# 심볼 이름은 nm에서 `_hg_render_page_svg` 로 보인다.
# PNG / native-skia symbols must stay absent.
```

Linux에서는 Apple 바이너리를 만들지 않는다. 엔진 게이트는 `cargo test --manifest-path engine/Cargo.toml`.
