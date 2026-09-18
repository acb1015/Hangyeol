# Hangyeol SwiftUI 정보구조 초안 (HOP 기준)

> 상태: **#46 IA 사인오프 완료** · Phase0b 프로토콜 스텁 (#48)
> 참고: [HOP / Open HWP](https://github.com/golbin/hop) — 제품 흐름 참고(복제 금지)
> 엔진: **Path B 확정** — 본문은 **네이티브 SVG/페이지 미리보기**. HOP studio **WKWebView 임베드 아님**.
> 목표: 구조화 plainText(`StructuredTextView`)만 보이는 상태를 끝내고, **렌더 페이지 영역**을 문서 본문 호스트로 둔다.
> 갱신: 2026-09-18 — 팀장3 사인오프·Path B · 개발자2 경계 합의 반영.

## 1. 현재 Hangyeol (As-Is)

| 영역 | 구현 | 비고 |
|------|------|------|
| 창 셸 | `DocumentWindow` + DocumentGroup | 열기/드롭/최근문서 |
| 본문 | `StructuredTextView` | 문단·표 블록 구조화 텍스트 |
| 크롬 | `DocumentChromeState`, toolbar | 편집됨, 찾기, PDF, 인쇄 |
| 찾기/바꾸기 | `FindReplaceBar` | 세션 `replaceText` (찾기-next 미배선) |
| 표/문단 편집 | 셀·문단 커밋 → 세션 API | 렌더 전 임시 UX |
| 빈 상태 | `EmptyStateView` | 샘플/열기/최근 |
| 오류 | `ErrorSheet` / 저장·내보내기 실패 시트 | encrypted/corrupt/… |
| 도움말 | `HelpSheet` 「알려진 한계」 | week-6 확정 카피 |
| 이미지 | `listImages` 세션 API만 (UI 후순위) | 렌더가 그림을 그리면 UI 목록 불필요 |

## 2. HOP에서 가져올 제품 흐름 (참고, 복제 금지)

1. 문서 열기 / DnD / 다중 창
2. 페이지·캔버스 중심 편집
3. 저장 / 다른 이름으로 저장
4. PDF 내보내기 · 인쇄
5. 네이티브 메뉴 ↔ 파일·편집 명령

Hangyeol은 **네이티브 macOS DocumentGroup + SwiftUI 크롬**을 유지하고, 본문만 **렌더 호스트(Path B)** 로 교체한다 (한컴 UI 복제 금지).

## 3. 목표 정보구조 (To-Be)

```
DocumentWindow
├── FindReplaceBar          (크롬; 렌더 세션 API에 맞춰 재설계 예정)
├── Toolbar / Commands      (저장·다른이름·PDF·인쇄·도움말 — 프론트)
├── Content
│   ├── EmptyStateView      (문서 없음)
│   └── RenderHostView      ★ 본문 슬롯 (크롬·a11y·placeholder)
│       ├── host: HangyeolRenderHosting?   # 셸 주입 (네이티브 SVG/페이지 뷰)
│       └── (fallback) StructuredTextView  # showsRenderHostSketch=false 시 현행
└── Sheets                  (Error / SaveFailure / ExportProgress / Help)
```

| 구역 | 소유 | 설명 |
|------|------|------|
| 메뉴·툴바·네비 타이틀·편집됨 | **프론트** | 한국어 카피, a11y |
| Find/Replace 바 | **프론트** | `find`/`reveal` + `document.replaceText` |
| `RenderHostView` placeholder·콜백 구독 | **프론트** | 로딩/빈/오류 시트만 · **content 슬롯** |
| `HangyeolRenderHosting` 구현·네이티브 렌더 뷰 | **개발자2** | Path B SVG/페이지 · Kit/Session 브리지 |
| 빈/오류/도움말 시트 | **프론트** | 원인+다음 행동 (`onOpenFailure`) |
| PDF/인쇄 트리거 | **프론트** | Phase1 현행 plainText exporter 유지 |
| listImages UI | **후순위** | 렌더가 그림을 그리면 생략 가능 |

## 4. 소유권 경계 (합의)

| 관심사 | 프론트 | 개발자2 |
|--------|--------|---------|
| SwiftUI 크롬·시트·L10n·a11y | ✅ | |
| `RenderHostView` content 슬롯·placeholder | ✅ | |
| Path B 네이티브 SVG/페이지 Representable · 호스트 구현 | | ✅ |
| DocumentSession / Kit / RealEngine | | ✅ (Views는 document/session만) |
| listImages 세션 | | 렌더 그림 전 **추가 변경 없음** |
| UTI / 샌드박스 / 공증 | | ✅ |

## 5. 렌더 세션 API (`HangyeolRenderHosting`)

Views는 **이것만** 본다. Kit/RealEngine 직접 호출 금지.
편집은 **기존 `DocumentSession`**. 웹 postMessage가 있다면 **호스트 내부만** — Views는 postMessage 직접 호출 금지. DocumentSession이 문서 진실.

코드 스텁: `HangyeolRenderHosting.swift` (프로토콜 + selection/find/viewport 타입 + `onLoadingChange` 프론트 제안).

### RenderHostView 계약

- `showsRenderHostSketch == false`(기본) → `StructuredTextView`
- `true` → `RenderHostView(host:)` — `host == nil`이면 placeholder
- 프론트는 셸이 주입하는 네이티브 렌더 뷰를 **직접 감싸지 않음**

## 6. 단계

| Phase | 내용 |
|-------|------|
| **0a (#46)** | IA + placeholder + 플래그 off — **머지·사인오프** |
| **0b (#48)** | `HangyeolRenderHosting` 스텁 · Path B 문구 |
| 1 | 개발자2 Path B 호스트 스텁·주입 · 로드/빈/오류 브리지 |
| 2 | 찾기/표 UX를 렌더 세션 API에 맞춰 재설계 |
| 3 | StructuredTextView → fallback/디버그 |

## 7. 비목표 (현재)

- 한컴/HOP 픽셀 복제, WYSIWYG 레이아웃 엔진
- Quick Look / Sparkle
- Views에서 RealEngine 직접 호출
- HOP studio **WKWebView 임베드** (Path B 아님)
- listImages 전용 갤러리 UI
- 프론트 대형 UI 리라이트 (크롬/카피만)

## 8. 결정됨 (팀장3 · 개발자2)

| # | 결정 |
|---|------|
| 1 주입 | 셸이 content/팩토리로 네이티브 렌더 뷰(`NSViewRepresentable`) 주입. `RenderHostView`는 **슬롯·a11y·placeholder만**. Path B = SVG/페이지 미리보기 (studio WKWebView 임베드 아님). |
| 2 찾기/선택/표 | **DocumentSession이 진실**. UI 이벤트 → 세션 API. Views는 postMessage 금지. |
| 3 PDF/인쇄 | Phase1 **현행 plainText exporter/인쇄 유지·병행**. 이후 렌더 인쇄는 품질 게이트 후 옵션 추가. 메뉴 시그니처는 프론트 그대로. |
