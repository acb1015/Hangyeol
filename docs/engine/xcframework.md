# Apple Silicon XCFramework / staticlib

Hangyeol 엔진(`engine/`)을 **macOS Apple Silicon**용으로 빌드하는 절차.
렌더러·조판·WASM UI를 **제품에 임베드하지 않는다.** 산출물은 `rhwp::document_core::DocumentCore` thin C ABI (`hg_*`)이며, 페이지 미리보기는 **UTF-8 SVG** `hg_render_page_svg`만 연다. PNG / native-skia는 넣지 않는다 ([hg-render-abi.md](hg-render-abi.md)).

**이 문서는 Mac 빌더용이다.** Cursor Cloud Linux 등 non-Apple 호스트에서는 `aarch64-apple-darwin` / iOS 타깃 바이너리를 만들 수 없다. 아래 명령은 Apple Silicon Mac + Xcode CLT에서 실행한다.

`hg_*` 심볼이 바뀌면 Vendor를 **로컬에서 다시 빌드**한다. 바이너리는 커밋하지 않는다: [vendor-rebuild.md](vendor-rebuild.md).

## Toolchain

| 핀 | 값 | 근거 |
|----|-----|------|
| **제품 rustc** | **≥ 1.89** | PR #9 이후 제품 핀. pinned rhwp (`cac9b4f7…`) cargo graph → `aes 0.9.3` (`rust-version` 1.89) |
| 크레이트 필드 | `engine/Cargo.toml` `rust-version = "1.88"` | 크레이트 메타데이터만. **1.89 미만으로 엔진을 빌드하지 말 것** |
| CI | **1.93.1** | `.github/workflows/engine.yml` (`dtolnay/rust-toolchain`). rhwp `rust-toolchain.toml`과 맞춤 |

```bash
rustc --version   # 1.89.0 or newer (CI image: 1.93.1)
xcodebuild -version
```

`MACOSX_DEPLOYMENT_TARGET`는 앱과 같이 **14.0** (Hangyeol macOS 14+).

## 무엇을 링크하지 않는가

`engine/Cargo.toml`은 이미 `rhwp`를 `default-features = false`로 고정한다. 빌드 때 다음을 **켜거나 링크하지 말 것**:

- rhwp **renderer PNG / Skia** (`native-skia`)
- **WASM** (`wasm32-unknown-unknown`, wasm-bindgen, rhwp WASM UI)
- Hangyeol 자체 OLE/HWP 바이너리 파서, ZIP/XML 손편집 저장 경로

산출 XCFramework / `.a` / `.dylib`에는 `hg_*` DocumentCore FFI만 들어간다. `hg_render_page_svg`는 기본 rhwp 레이아웃/SVG 경로를 쓰며 **`native-skia`를 켜지 않는다.**

## 타깃

| 타깃 | 용도 |
|------|------|
| **`aarch64-apple-darwin`** | **1순위.** Hangyeol macOS 데스크톱 앱 |
| `aarch64-apple-ios` | 선택. 디바이스. 한결 앱은 macOS가 제품 타깃 |
| `aarch64-apple-ios-sim` | 선택. Apple Silicon 시뮬레이터 |

`x86_64-apple-darwin`은 Hangyeol 앱 범위 밖. 유니버설이 필요할 때만 아래 lipo 스케치를 쓴다.

```bash
rustup target add aarch64-apple-darwin
# optional:
# rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

## 산출 경로

`Cargo.toml` `[lib] crate-type`은 현재 `cdylib` + `rlib`이다. `engine/target/`은 gitignore.

| 종류 | 명령 | 경로 |
|------|------|------|
| **cdylib** | `cargo build --release --target aarch64-apple-darwin` | `engine/target/aarch64-apple-darwin/release/libhangyeol_engine.dylib` |
| **staticlib** | `cargo rustc … -- --crate-type staticlib` (Cargo.toml 수정 없이 `.a` 추가) | `engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a` — 없을 때 `…/release/deps/libhangyeol_engine.a`를 copy/symlink |
| **헤더 (정본 ABI)** | 손작성. cbindgen 불필요 | `engine/include/hangyeol_engine.h` |
| **XCFramework** | `xcodebuild -create-xcframework` | `engine/target/xcframework/HangyeolEngine.xcframework` (`engine/target/` 아래라 커밋되지 않음) |

Kit 쪽 헤더 복사본(`Packages/HangyeolKit/.../hangyeol_engine.h`)은 엔진 ABI와 같이 이 모노레포에서 동기화한다. XCFramework `Headers/`는 `engine/include/hangyeol_engine.h`에서 온다.

## macOS Apple Silicon 빌드

리포 루트에서:

```bash
export MACOSX_DEPLOYMENT_TARGET=14.0

# 1) cdylib (.dylib) — Cargo.toml crate-type 그대로
cargo build --release --target aarch64-apple-darwin --manifest-path engine/Cargo.toml

# 2) staticlib (.a) — rustc에 crate-type 추가 (Cargo.toml 변경 없음)
cargo rustc --release --target aarch64-apple-darwin --manifest-path engine/Cargo.toml -- --crate-type staticlib
```

확인:

```bash
file engine/target/aarch64-apple-darwin/release/libhangyeol_engine.dylib
file engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a
lipo -info engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a
# 기대: arm64 only

# top-level .a 가 없으면 아래 로컬 재현의 deps → release copy/symlink 후:
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# 기대: hg_open hg_save hg_save_hwpx hg_plain_text hg_replace_text
#       hg_insert_text hg_delete_range hg_list_tables hg_set_cell_text
#       hg_list_images hg_render_page_svg hg_close hg_free_buffer hg_last_error
# PNG / native-skia 심볼은 없어야 한다.
```

`.dylib`를 XCFramework에 넣을 경우 id를 `@rpath`로 맞춘다:

```bash
install_name_tool -id @rpath/libhangyeol_engine.dylib \
  engine/target/aarch64-apple-darwin/release/libhangyeol_engine.dylib
```

앱에 임베드할 때는 **staticlib XCFramework가 더 단순**하다 (`@rpath` / embed-and-sign 없음).

## 로컬 재현 (2026-09-10)

Apple Silicon Mac의 리포 체크아웃에서 확인 (rustc **1.93.1**, `MACOSX_DEPLOYMENT_TARGET=14.0`):

```bash
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo rustc --release --target aarch64-apple-darwin --manifest-path engine/Cargo.toml -- --crate-type=staticlib
```

**주의:** `.a`가 `engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a`에 없고 `engine/target/aarch64-apple-darwin/release/deps/libhangyeol_engine.a`에만 있을 수 있다. `xcodebuild -create-xcframework` 전에 top-level 경로가 없으면 copy 또는 symlink 한다:

```bash
# top-level .a 가 없을 때만 (deps → release)
engine/scripts/copy-staticlib-to-release.sh
# 수동 동일 작업:
# cp engine/target/aarch64-apple-darwin/release/deps/libhangyeol_engine.a \
#   engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a
# 또는: ln -sf deps/libhangyeol_engine.a engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a
```

XCFramework 산출 (커밋하지 않음): `engine/target/xcframework/HangyeolEngine.xcframework`

```bash
nm -gU engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a | grep ' _hg_'
# 확인됨: hg_open hg_save hg_save_hwpx hg_plain_text hg_replace_text
#         hg_insert_text hg_delete_range hg_list_tables hg_set_cell_text
#         hg_list_images hg_render_page_svg hg_close hg_free_buffer hg_last_error
# PNG / native-skia 심볼은 없어야 한다.
```

## XCFramework 생성

`xcodebuild -create-xcframework`는 **Mac + Xcode**가 필요하다.

### staticlib (권장, macOS arm64 단독)

top-level `release/libhangyeol_engine.a`가 없으면 위에서처럼 `release/deps/`에서 copy/symlink 한 뒤:

```bash
mkdir -p engine/target/xcframework

xcodebuild -create-xcframework \
  -library engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a \
  -headers engine/include \
  -output engine/target/xcframework/HangyeolEngine.xcframework
```

### cdylib

```bash
mkdir -p engine/target/xcframework

xcodebuild -create-xcframework \
  -library engine/target/aarch64-apple-darwin/release/libhangyeol_engine.dylib \
  -headers engine/include \
  -output engine/target/xcframework/HangyeolEngine.xcframework
```

한 디렉터리에 static과 dylib XCFramework를 동시에 두지 말 것. `-output` 경로가 이미 있으면 `xcodebuild`가 실패한다.

### lipo 스케치 (유니버설이 필요할 때만)

Hangyeol 앱은 Apple Silicon이 1순위라 **지금은 lipo 불필요**. Intel macOS를 나중에 넣을 때:

```bash
# x86_64-apple-darwin 을 같은 rustc≥1.89 / MACOSX_DEPLOYMENT_TARGET=14.0 으로 빌드한 뒤:
lipo -create \
  engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a \
  engine/target/x86_64-apple-darwin/release/libhangyeol_engine.a \
  -output engine/target/universal/libhangyeol_engine.a

xcodebuild -create-xcframework \
  -library engine/target/universal/libhangyeol_engine.a \
  -headers engine/include \
  -output engine/target/xcframework/HangyeolEngine.xcframework
```

XCFramework는 slice별로 아카이브를 받는 편이 더 낫다. 유니버설 `.a`와 slice `.a`를 섞지 말 것.

## iOS (선택, 한결 앱 비제품)

macOS 데스크톱이 제품 타깃이다. iOS는 동일 `hg_*` staticlib을 쓸 때만, **Mac**에서:

```bash
export IPHONEOS_DEPLOYMENT_TARGET=17.0

cargo rustc --release --target aarch64-apple-ios \
  --manifest-path engine/Cargo.toml -- --crate-type staticlib

cargo rustc --release --target aarch64-apple-ios-sim \
  --manifest-path engine/Cargo.toml -- --crate-type staticlib

xcodebuild -create-xcframework \
  -library engine/target/aarch64-apple-darwin/release/libhangyeol_engine.a \
  -headers engine/include \
  -library engine/target/aarch64-apple-ios/release/libhangyeol_engine.a \
  -headers engine/include \
  -library engine/target/aarch64-apple-ios-sim/release/libhangyeol_engine.a \
  -headers engine/include \
  -output engine/target/xcframework/HangyeolEngine.xcframework
```

iOS 링크는 SDK/`xcrun` 이슈가 흔하다. 실패해도 Hangyeol macOS 앱 게이트가 아니다.

## 저장 전 clear (`hg_save` / `hg_save_hwpx`)

XCFramework는 이 크레이트와 **같은** 구현을 담는다. 링크 플래그로 lineseg를 지우는 것이 아니다.

- `hg_save(..., HG_FILE_HWPX, ...)` 와 `hg_save_hwpx` 는 serialize 전에 모든 문단·표 셀 `line_segs`를 clear한다.
- 기본 rhwp export는 `hp:linesegarray`를 남긴다. Hangyeol 저장본은 **0개**여야 한다.
- `.hwp` 쓰기는 `HG_UNSUPPORTED` / `SAVE_REJECTED` (HWPX-only).
- 앱·Kit는 이 두 심볼로만 저장해야 한다. rhwp 기본 export나 ZIP/XML 손편집 경로를 제품에 넣지 말 것.

한/글 개봉 스모크 파일 위치는 문서 하단 **Mac 한/글 스모크 아티팩트**.

## HangyeolKit / Apps 가 나중에 쓰는 법

HangyeolKit **`RealEngine`** 은 Kit 패키지에 있다. XCFramework는 **커밋하지 않는다.** 산출·`nm hg_*` 재현은 위 **로컬 재현 (2026-09-10)** (PR #14). 심볼이 바뀌면 [vendor-rebuild.md](vendor-rebuild.md). Kit Vendor:

```bash
mkdir -p Packages/HangyeolKit/Vendor
ln -s /Users/acb/Hangyeol-xcf-build/engine/target/xcframework/HangyeolEngine.xcframework \
  Packages/HangyeolKit/Vendor/HangyeolEngine.xcframework
# or: export HANGYEOL_ENGINE_XCFRAMEWORK=…/HangyeolEngine.xcframework
```

`Package.swift`가 Vendor/env를 보면 `binaryTarget` 또는 링커 플래그로 live `hg_*`를 연결하고, 없으면 C stub / `notLinked`로 남는다. 자세한 내용: `Packages/HangyeolKit/README.md`.

**앱 링크 (week-3 PR2):** `Apps/Hangyeol`은 로컬 SPM으로 HangyeolKit을 연결한다. Kit이 Vendor XCFramework를 링크하면 `KitRealEngine`이 기본 엔진이다. 없으면 Mock. Mock 롤백: `EngineClient.resetToMock()`, 실행 환경 `HANGYEOL_USE_MOCK=1`, 또는 UserDefaults `HANGYEOL_USE_MOCK`.

앱 링크 후 확인:

1. HangyeolKit은 Xcode 제품이다. Kit이 이미 Vendor XCFramework를 링크한다. **바이너리는 커밋하지 않는다.**
2. C ABI 정본은 `engine/include/hangyeol_engine.h` (XCFramework `Headers/`에 복사됨). Kit 헤더 미러는 같은 모노레포에서 엔진과 동기화한다.
3. Rust `staticlib`를 앱에 넣을 때 링커가 `iconv` / `System` 정도를 요구할 수 있다. **렌더러·WASM 라이브러리로 메우지 말 것.**
4. cdylib를 쓸 경우 `@rpath` + Embed & Sign.
5. Mac 스모크: `fixtures/hub_hwpxlib_SimpleTable.hwpx` (manifest **`hub-A`**) 열기 → `1`을 `HGPOC99`로 바꾸기 → HWPX 저장 → `hp:linesegarray` = 0.

## Mac 한/글 스모크 아티팩트

한/글 개봉은 **Mac 수동**. 엔진 바이너리(XCFramework)와 별개로, clear-before-save 된 HWPX가 필요하다.

| 위치 | 경로 | 비고 |
|------|------|------|
| Owner Downloads (이미 복사됨) | `~/Downloads/SimpleTable-rhwp-replaced-cleared.hwpx` | 한/글에서 이 파일을 연다 |
| 레포 생성물 (gitignore) | `engine/testdata/out/SimpleTable-cleared-replaced.hwpx` | 아래 테스트가 씀 |

재생성 (rustc ≥ 1.89, 리포 루트; Linux CI에서도 파일은 만들 수 있으나 한/글 개봉은 Mac):

```bash
cargo test --manifest-path engine/Cargo.toml hub_a_replace_clear_before_save_roundtrip -- --exact
```

허브-A (`fixtures/hub_hwpxlib_SimpleTable.hwpx`, Apache-2.0)를 치환(`1` → `HGPOC99`)한 뒤 `hg_save` / `hg_save_hwpx`로 lineseg clear 한다. 파생 HWPX는 커밋하지 않는다.
