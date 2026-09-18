# Bundled Mock preview (not HWP / HWPX)

`welcome.mock.json` is a **MockEngine** snapshot (`metadata.isMockPreview = true`).

- It is **not** a Hangul / DocumentCore document.
- Opening it through `DocumentGroup` + Real (`KitRealEngine`) must **fail** (corrupt / engine error) — never look like a Real HWPX success.
- Load it only via `MockEngine.loadBundledSample()` (Help / 샘플 메뉴, frontend).
- Finder/Dock smoke must use `fixtures/hub_hwpxlib_SimpleTable.hwpx` (COMMIT_OK). There is no COMMIT_OK `.hwp` on main; do **not** rename this JSON to `.hwp` / `.hwpx`.
