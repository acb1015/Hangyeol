# Known limitations

손실·미지원 메모. **Engine 절은 week-6 확정** (기존 게이트·문서 기준). 앱 UX 카피는 Views / L10n이 담당한다. 아래 **앱**은 셸 범위, **Engine**은 코어 범위다.

## 앱

- **조판**: 한/글(Hangul)과 픽셀 단위로 같지 않다. WYSIWYG가 아니다. 화면은 본문·표 블록을 구조화해 보여 준다.
- **`.hwp` 저장**: 거절한다. 엔진 freeze `SAVE_REJECTED` → `HangyeolError.saveRejected`. HWPX로 저장하도록 안내한다. `.hwp` 읽기는 가능하다.
- **암호화/암호 문서**: 복호화하지 않는다. freeze `ENCRYPTED` → `HangyeolError.encrypted`.
- **손상·미지원 열기**: freeze `CORRUPT` / `UNSUPPORTED_VERSION`과 앱 `unsupportedType`이 ErrorSheet로 올라온다 (`HangyeolError.corrupt` / `.unsupported` / `.unsupportedType` / `.emptyFile`).
- **표·셀·문단**: 엔진이 받치는 서브셋만 편집한다 (`listTables` / `setCellText` / `insertText` / `deleteRange`). 이미지·메타는 앱에서 렌더하지 않으며, 엔진 목록 API는 [engine/image-meta.md](engine/image-meta.md)를 본다.
- **Mock vs Real**: XCFramework가 있으면 `KitRealEngine`(Real)이 기본. 롤백: `EngineClient.resetToMock()`, 실행 환경 `HANGYEOL_USE_MOCK=1` (`true` / `YES`), UserDefaults `HANGYEOL_USE_MOCK`. 절차: [week3-ffi-checklist.md](week3-ffi-checklist.md).
- **PDF/인쇄**: 문단+표 셀 `plainText`(구조화 텍스트)다. 한/글 조판 인쇄가 아니다.
- **공증 / Sparkle / Quick Look**: MVP 밖. week-6 초안: [app/notarization-prep.md](app/notarization-prep.md). week-7/8 내부 배포·회귀: [app/week7-internal-regression.md](app/week7-internal-regression.md). 실제 공증은 owner가 ASC `.p8` + Team ID를 주기 전까지 **문서만**.

## Engine (확정)

기존 게이트·문서에서 확인된 **손실·미지원**. BinData extract API·ZIP 폴백 writer·자체 바이너리 파서는 추가하지 않는다. 렌더러는 **현재 엔진에 없음**(아래). 완성 트랙 설계만: [engine/renderer-spike-1pager.md](engine/renderer-spike-1pager.md).

- **HWP write**: `hg_save(..., HG_FILE_HWP)` → `SAVE_REJECTED` / `HG_UNSUPPORTED`. 저장은 HWPX만. 게이트: `hwp_save_is_rejected`.
- **Decrypt**: 암호 문서는 `ENCRYPTED` / `HG_PASSWORD`. 복호화·DRM bypass 금지. 메시지 매핑만 (`encrypted_open_message_maps_to_password`); Hangul 암호 픽스처는 요구하지 않는다.
- **DRM / HWP 3.x / HML**: `UNSUPPORTED_VERSION`. 편집용으로 열지 않는다.
- **Corrupt / truncated**: `CORRUPT` (F16). 미지원으로 조용히 통과시키지 않는다. 게이트: `f16_truncated_is_corrupt_not_unsupported`.
- **Renderer**: 렌더러·조판·WASM UI 없음. `hg_plain_text`는 IR 본문+표 셀 텍스트만. 픽셀 디코드·화면 배치 없음. 제품 완성 트랙(설계, 코드 없음): [engine/renderer-spike-1pager.md](engine/renderer-spike-1pager.md).
- **Clear-before-save**: Hangyeol 경로는 섹션/본문 문단/표 셀 문단의 `line_segs`를 비운 뒤 `export_hwpx_native`. 저장본 `hp:linesegarray`는 **0**. 기본 rhwp export는 lineseg를 남기며 Hangyeol 경로가 아니다. 게이트: hub-A replace/insert/delete/table + hub-B keep-on-save.
- **Image keep-on-save (제품 게이트)**: hub-B (`fixtures/hub_hwpxlib_SimplePicture.hwpx`) 열기 → DocumentCore FFI 텍스트 편집 → `hg_save_hwpx` clear-before-save → 재오픈. ZIP `BinData/` **파일 수·바이트 보존**, `hg_list_images` 개수/메타 유효, `hp:linesegarray`=0. 범위는 기존 DocumentCore export의 hub-B 왕복이다. 게이트: `hub_b_image_keep_on_save_clear_before_save_roundtrip`. 상세: [engine/image-meta.md](engine/image-meta.md).
- **Image API 한계**: `hg_list_images`는 `Control::Picture` 목록/메타만 (본문 후 중첩 셀). 그림 insert/delete 없음. BinData **extract API 없음** (바이트를 제품 API로 꺼내지 않음). `byte_len`은 IR 길이 힌트일 뿐이다.
- **Table API 한계**: `hg_list_tables` / `hg_set_cell_text`만. `(table, row, col)` 셀 평문 쓰기. 행·열 추가/삭제, 병합/해제, 셀 스타일 API 없음. 범위 밖 인덱스는 `CORRUPT`. 중첩 표는 문서 순서로 목록에 오르지만 freeze 편집면은 셀 텍스트다.
- **본문 편집**: `hg_insert_text` / `hg_delete_range` / `hg_replace_text` (`replace_all_native`는 표 셀 포함). 잘못된 인덱스 → `CORRUPT`.
- **Headers / footers / equations / shapes**: freeze 편집면(본문+표 셀 텍스트) 밖.
- **ZIP-fallback writer / Hangyeol-owned binary parser**: 범위 밖. 엔진은 rhwp `DocumentCore`만.
