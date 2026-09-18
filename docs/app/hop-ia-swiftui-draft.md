# Hangyeol SwiftUI 정보구조 초안 (HOP 기준)

> 상태: **합의용 초안** (대형 UI 리라이트 금지 단계)
> 참고: [HOP / Open HWP](https://github.com/golbin/hop) — rhwp 스튜디오 웹 에디터 위 얇은 데스크톱 셸
> 목표: 구조화 plainText(`StructuredTextView`)만 보이는 상태를 끝내고, **rhwp 렌더 화면**을 문서 본문 호스트로 둔다.

## 1. 현재 Hangyeol (As-Is)

| 영역 | 구현 | 비고 |
|------|------|------|
| 창 셸 | `DocumentWindow` + DocumentGroup | 열기/드롭/최근문서 |
| 본문 | `StructuredTextView` | 문단·표 블록 구조화 텍스트 |
| 크롬 | `DocumentChromeState`, toolbar | 편집됨, 찾기, PDF, 인쇄 |
| 찾기/바꾸기 | `FindReplaceBar` | 세션 `replaceText` |
| 표/문단 편집 | 셀·문단 커밋 → 세션 API | 렌더 전 임시 UX |
| 빈 상태 | `EmptyStateView` | 샘플/열기/최근 |
| 오류 | `ErrorSheet` / 저장·내보내기 실패 시트 | encrypted/corrupt/… |
| 도움말 | `HelpSheet` 「알려진 한계」 | week-6 확정 카피 |
| 이미지 | `listImages` 세션 API만 (UI 후순위) | 렌더가 그림을 그리면 UI 목록 불필요 |

## 2. HOP에서 가져올 제품 흐름 (참고, 복제 금지)

HOP는 Tauri 셸 + rhwp studio webview:

1. 문서 열기 / DnD / 다중 창
2. 페이지·캔버스 중심 편집 (웹 에디터)
3. 저장 / 다른 이름으로 저장
4. PDF 내보내기 · 인쇄
5. 네이티브 메뉴 ↔ 파일·편집 명령

Hangyeol은 **네이티브 macOS DocumentGroup + SwiftUI 크롬**을 유지하고, 본문만 **렌더 호스트**로 교체한다 (한컴 UI 복제 금지).

## 3. 목표 정보구조 (To-Be)

```
DocumentWindow
├── FindReplaceBar          (크롬; 렌더 세션 API에 맞춰 재설계 예정)
├── Toolbar / Commands      (저장·다른이름·PDF·인쇄·도움말 — 프론트)
├── Content
│   ├── EmptyStateView      (문서 없음)
│   └── RenderHostView      ★ 본문 호스트 (개발자2: WKWebView/렌더 세션 주입)
│       └── (fallback) StructuredTextView  # 플래그 off 시 현행 유지
└── Sheets                  (Error / SaveFailure / ExportProgress / Help)
```

| 구역 | 소유 | 설명 |
|------|------|------|
| 메뉴·툴바·네비 타이틀·편집됨 | **프론트** | 한국어 카피, a11y |
| Find/Replace 바 | **프론트** | 렌더 세션 API 확정 후 재설계 |
| RenderHostView | **프론트 자리 + 개발자2 주입** | 컨테이너·a11y; WKWebView는 셸 |
| 빈/오류/도움말 시트 | **프론트** | 원인+다음 행동 |
| PDF/인쇄 트리거 | **프론트** | Export/Print 코디네이터 호출 |
| listImages UI | **후순위** | 렌더가 그림을 그리면 생략 가능 |

## 4. 소유권 경계

| 관심사 | 프론트 | 개발자2 |
|--------|--------|---------|
| SwiftUI 크롬·시트·L10n·a11y | ✅ | |
| `RenderHostView` API / placeholder | ✅ 스케치 | 구현체 주입 |
| WKWebView · rhwp/studio 로드 | | ✅ |
| DocumentSession / Kit / RealEngine | | ✅ |
| 렌더 세션 공개 API | 소비·UX 재설계 | ✅ 정의·구현 |
| UTI / 샌드박스 / 공증 | | ✅ |

## 5. RenderHostView 스케치 계약

- `showsRenderHostSketch == false`(기본) → 현행 `StructuredTextView` (회귀 없음)
- `true` → `RenderHostView.placeholder` 또는 개발자2 주입 content
- Views는 RealEngine을 직접 호출하지 않음

## 6. 단계

| Phase | 내용 |
|-------|------|
| **0 (본 PR)** | IA 문서 + `RenderHostView` placeholder + 플래그 기본 off |
| 1 | 개발자2 WKWebView 주입 · 로드/빈/오류 브리지 |
| 2 | 렌더 세션 API에 찾기/표 UX 재설계 |
| 3 | StructuredTextView를 fallback/디버그로 격하 |

## 7. 비목표 (합의 전)

- 한컴/HOP 픽셀 복제, WYSIWYG 레이아웃 엔진
- Quick Look / Sparkle
- Views에서 RealEngine 직접 호출
- listImages 전용 갤러리 UI

## 8. 열린 질문

1. 렌더 호스트 주입: `NSViewRepresentable` 형태?
2. 찾기/선택/표 편집: 웹 postMessage vs 네이티브 세션 API?
3. PDF/인쇄: 웹뷰 프린트 vs 기존 plainText exporter 병행?
