# Hangyeol (한결)

macOS 14+ 네이티브 앱. `.hwp` / `.hwpx` 열기 · 본문·표 수정 · HWPX 저장.

- Bundle ID: `app.hangyeol.mac`
- 엔진: rhwp `DocumentCore` 코어 서브셋 (`engine/` cdylib, rustc **≥ 1.89**)
- 앱 런타임에 Python 금지
- Engine (Week1): [엔진 비교 초안 + 샘플 목록](docs/week1-engine-comparison.md)
- Engine (Week1): [openhwp PoC 게이트 보고](docs/openhwp-poc-gate-report.md) · [엔진 우선순위 2026-09-10](docs/engine-priority-2026-09-10.md)
- Engine (Week1): [rhwp 코어 서브셋 게이트 표](docs/rhwp-core-subset-gate.md)
- Engine: [Apple Silicon XCFramework / staticlib](docs/engine/xcframework.md) · [Vendor rebuild (symbols)](docs/engine/vendor-rebuild.md)
- Engine (Week3): [FFI 체크리스트 (앱 링크 · Mock→Real)](docs/week3-ffi-checklist.md)
- Engine: [image-meta list](docs/engine/image-meta.md) · [known limitations](docs/known-limitations.md) · [renderer spike 1-pager](docs/engine/renderer-spike-1pager.md)
- App (Week5): [UTI / Finder / Dock smoke](docs/app/uti-finder-dock-smoke.md)
- App (Week6): [공증 준비 체크리스트 초안](docs/app/notarization-prep.md)
- App (Week7/8): [내부 배포 · 회귀 체크리스트](docs/app/week7-internal-regression.md)

## 모노레포 구조

```
Apps/Hangyeol/         # macOS SwiftUI+AppKit 문서 앱 (개발자2)
Packages/HangyeolKit/  # Swift FFI 래퍼
engine/                # Rust + C ABI (개발자1)
fixtures/              # 샘플 코퍼스 · 왕복 기대값
docs/                  # 한계 · API 동결 노트
scripts/               # 회귀 · 추출 CI
```

## 역할

| 역할 | 담당 |
|------|------|
| 팀장 | 범위·일정·엔진·리스크·주간 데모 |
| 개발자1 | 문서 엔진 |
| 개발자2 | macOS 앱 |

## 비고

암호화·DRM·HWP 3.x 미지원. 한컴 상표·함초롬 폰트 무단 번들 금지.
