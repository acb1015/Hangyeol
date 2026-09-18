# 엔진 우선순위 (2026-09-10)

**CONFIRMED** (팀장). 스파이크 증거: [rhwp 코어 서브셋 게이트 표](rhwp-core-subset-gate.md) · [openhwp PoC 게이트 보고](openhwp-poc-gate-report.md).

## 확정

- **1순위**: rhwp `DocumentCore` 코어 서브셋 (parser / serial / edit only).
- **제품 핀**: rustc **≥ 1.89** (PR #9 이후; pinned rhwp cargo graph / `aes 0.9.3`). `engine/Cargo.toml` `rust-version` 필드는 1.88로 남아 있으나 **1.89 미만 엔진 빌드 금지**. CI는 **1.93.1**.
- Apple Silicon XCFramework / staticlib 절차: [engine/xcframework.md](engine/xcframework.md) (Mac 호스트 필수).
- **저장 전 필수**: Hangyeol wrapper에서 **linesegarray clear REQUIRED** (기본 export는 `hp:linesegarray` 잔존 → FAIL; clear API로 회복).
- **F16**: 열기 실패·패닉 없음. rhwp `UNSUPPORTED_FILE_FORMAT` → Hangyeol FFI **`CORRUPT`** 매핑.
- **openhwp**: **백업 전용**. stable rustc 1.85 크레이트 빌드 **FAIL** (`const_vec_string_slice`).

## 금지

- 렌더러 · 조판 · WASM UI 임베드 없음. *(당시 freeze. 2026-09-18 팀장: 금지 해제, 설계 우선 — [renderer-spike-1pager.md](engine/renderer-spike-1pager.md). 이 문서는 2026-09-10 엔진 범위 기록.)*
- ZIP/XML 폴백 **제품화 금지** (스파이크 증거일 뿐 제품 엔진이 되면 안 됨).

## Mac 한/글 큐

한/글 개봉 스모크는 **Mac 수동**. clear-before-save 아티팩트 위치:

| 위치 | 경로 |
|------|------|
| Owner Downloads (이미 복사됨) | `~/Downloads/SimpleTable-rhwp-replaced-cleared.hwpx` |
| 레포 생성 경로 (gitignore) | `engine/testdata/out/SimpleTable-cleared-replaced.hwpx` |

```bash
cargo test --manifest-path engine/Cargo.toml hub_a_replace_clear_before_save_roundtrip -- --exact
```

Apple 바이너리 빌드(`.a` / `.dylib` / XCFramework)는 Linux에서 불가. Mac 절차: [engine/xcframework.md](engine/xcframework.md).
