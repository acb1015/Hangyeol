#ifndef HANGYEOL_ENGINE_H
#define HANGYEOL_ENGINE_H

/*
 * Hangyeol engine C ABI — rhwp DocumentCore thin cdylib.
 *
 * Two layers, one naming scheme (no third set of symbols):
 *
 *   1) HangyeolKit draft (Packages/HangyeolKit/.../hangyeol_engine.h)
 *      hg_open / hg_save / hg_free_buffer / hg_close
 *      hg_status: HG_OK | HG_UNSUPPORTED | HG_CORRUPT | HG_PASSWORD
 *
 *   2) Kickoff freeze edit API
 *      hg_plain_text / hg_replace_text / hg_save_hwpx
 *      plus product hg_insert_text / hg_delete_range
 *      plus table: hg_list_tables / hg_set_cell_text
 *      plus image-meta list: hg_list_images (see docs/engine/image-meta.md)
 *      plus page preview: hg_render_page_svg (UTF-8 SVG; see
 *      docs/engine/hg-render-abi.md)
 *
 * Kit mapping (tables):
 *   hg_list_tables     → TableBlock addressing. `hg_table_info.index` is the
 *                        `table` argument to hg_set_cell_text. `rows`/`cols`
 *                        size the grid. `section`/`paragraph`/`control` locate
 *                        the DocumentCore table control for top-level tables.
 *   hg_set_cell_text   → cell plain-text write at (table, row, col). Merged
 *                        cells are addressed at any covered grid coordinate
 *                        (anchor via DocumentCore `cell_grid`).
 *
 * Kit mapping (images):
 *   hg_list_images     → ImageBlock addressing. `hg_image_info.index` is the
 *                        document-order picture id. `section`/`paragraph`/
 *                        `control` locate the DocumentCore `Control::Picture`.
 *                        `width`/`height` + `format` / `bin_data_id` / `href`
 *                        are size/format meta (no BinData extract API).
 *
 * Kit mapping (page preview):
 *   hg_render_page_svg → UTF-8 SVG for `page_index` (0-based). Maps to
 *                        layer + RenderProfile::Screen. Caller frees with
 *                        hg_free_buffer. Out of range → HG_CORRUPT. PNG /
 *                        native-skia are not exported. Views are frontend-owned.
 *
 * Freeze string codes ↔ Kit hg_status (1:1):
 *   ENCRYPTED            ↔ HG_PASSWORD
 *   UNSUPPORTED_VERSION  ↔ HG_UNSUPPORTED   (HWP 3.x, DRM, HML, out-of-scope format)
 *   SAVE_REJECTED        ↔ HG_UNSUPPORTED   (e.g. hg_save(..., HG_FILE_HWP) — HWPX-only write)
 *   CORRUPT              ↔ HG_CORRUPT       (truncated / unknown / malformed; F16)
 *
 * Engine: rhwp DocumentCore (parser / serial / edit) plus read-only SVG
 * page preview (`hg_render_page_svg` → layer + RenderProfile::Screen).
 * rustc ≥ 1.88. PNG / native-skia are not exported. No WASM UI.
 *
 * Save contract: hg_save (HWPX) and hg_save_hwpx MUST clear every paragraph
 * and table-cell `line_segs` before serialize so the ZIP XML contains 0
 * `hp:linesegarray` nodes. Kit `hg_save` is that same HWPX clear-before-save
 * path (not a second writer).
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Exactly four status kinds (HangyeolKit draft).
 *
 * HG_OK          — Success. The call completed; out-params are valid.
 * HG_UNSUPPORTED — Format, version, or operation is out of scope
 *                  (freeze: UNSUPPORTED_VERSION | SAVE_REJECTED).
 * HG_CORRUPT     — Truncated or malformed container (OLE2/ZIP/OWPML).
 *                  Freeze: CORRUPT. F16 truncated/unknown is CORRUPT, not a
 *                  vague unsupported passthrough.
 * HG_PASSWORD    — Encrypted / password-protected. Decrypt and DRM bypass
 *                  are forbidden. Freeze: ENCRYPTED.
 */
typedef enum hg_status {
    HG_OK = 0,
    HG_UNSUPPORTED = 1,
    HG_CORRUPT = 2,
    HG_PASSWORD = 3,
} hg_status;

typedef enum hg_file_type {
    HG_FILE_HWPX = 0,
    HG_FILE_HWP = 1,
} hg_file_type;

/** Opaque engine session. Caller owns it and must pass it to hg_close. */
typedef struct hg_engine hg_engine;

/**
 * One table in document order (body, then nested cell tables).
 *
 * Kit: map to a TableBlock. Pass `index` as `table` to hg_set_cell_text.
 * `rows` / `cols` are DocumentCore `row_count` / `col_count`.
 */
typedef struct hg_table_info {
    uint32_t index;      /* 0-based document order; hg_set_cell_text `table` */
    uint32_t section;    /* DocumentCore section index */
    uint32_t paragraph;  /* body paragraph that owns the (outer) table */
    uint32_t control;    /* control index in that paragraph (or cell para) */
    uint32_t rows;
    uint32_t cols;
} hg_table_info;

/**
 * One picture in document order (body, then nested cell pictures).
 *
 * Kit: map to an ImageBlock. `index` addresses the picture. `width`/`height`
 * are `img_dim` when set, else common object size (HWPUNIT). `format` is a
 * NUL-terminated extension (`jpg` / `png` / …). `href` is Picture.href or a
 * BinData path / `image{N}` id. Not an extract or keep-on-save API.
 */
typedef struct hg_image_info {
    uint32_t index;         /* 0-based document order */
    uint32_t section;       /* DocumentCore section index */
    uint32_t paragraph;     /* body paragraph that owns the (outer) picture */
    uint32_t control;       /* control index in that paragraph (or cell para) */
    uint32_t width;         /* img_dim.0, else common.width */
    uint32_t height;        /* img_dim.1, else common.height */
    uint32_t byte_len;      /* BinData IR length; 0 if unknown */
    uint32_t bin_data_id;   /* ImageAttr.bin_data_id */
    char format[16];        /* NUL-terminated; empty if unknown */
    char href[128];         /* NUL-terminated; empty if unknown */
} hg_image_info;

/* -------------------------------------------------------------------------- */
/* HangyeolKit layer (signatures match Packages/HangyeolKit header)           */
/* -------------------------------------------------------------------------- */

/**
 * Open a document from a memory buffer.
 *
 * Format is detected from **bytes**, not the path / extension and not `type`.
 * `type` is accepted for Kit ABI compatibility (F14: `.pdf` name, HWPX bytes).
 *
 * On HG_OK, *out_engine is non-NULL and the caller must hg_close() it.
 * On any error, *out_engine is NULL (if out_engine itself is non-NULL).
 */
hg_status hg_open(
    const uint8_t *bytes,
    size_t length,
    hg_file_type type,
    hg_engine **out_engine
);

/**
 * Serialize the open session.
 *
 * HWPX (`HG_FILE_HWPX`): clear-before-save, then DocumentCore export.
 * HWP (`HG_FILE_HWP`): HG_UNSUPPORTED / freeze SAVE_REJECTED (HWPX-only write).
 *
 * On HG_OK, *out_bytes is an engine-owned buffer of *out_length bytes;
 * free with hg_free_buffer.
 */
hg_status hg_save(
    hg_engine *engine,
    hg_file_type type,
    uint8_t **out_bytes,
    size_t *out_length
);

/** Release a buffer returned by hg_save / hg_plain_text / hg_render_page_svg.
 *  NULL is a no-op. */
void hg_free_buffer(uint8_t *bytes);

/** Release an engine session. NULL is a no-op. */
void hg_close(hg_engine *engine);

/* -------------------------------------------------------------------------- */
/* Kickoff freeze edit API                                                    */
/* -------------------------------------------------------------------------- */

/**
 * Concatenate body + table-cell paragraph text (UTF-8).
 * On HG_OK, *out_bytes / *out_length as hg_save; free with hg_free_buffer.
 */
hg_status hg_plain_text(
    hg_engine *engine,
    uint8_t **out_bytes,
    size_t *out_length
);

/**
 * Replace every occurrence of `find` with `replace` (UTF-8, DocumentCore
 * `replace_all_native`, including table cells).
 * On HG_OK, *out_count is the number of replacements (may be 0).
 */
hg_status hg_replace_text(
    hg_engine *engine,
    const char *find,
    const char *replace,
    size_t *out_count
);

/**
 * Write HWPX to `path` (UTF-8 filesystem path). Same clear-before-save
 * as Kit `hg_save(..., HG_FILE_HWPX, ...)`.
 */
hg_status hg_save_hwpx(
    hg_engine *engine,
    const char *path
);

/**
 * Insert UTF-8 `text` at (section, paragraph, char_offset) in the body.
 * Product gate: plain_text shows the string; hg_save_hwpx clear-before-save
 * ZIP has 0 hp:linesegarray; reopen still contains it.
 * Invalid section/paragraph → HG_CORRUPT / CORRUPT.
 */
hg_status hg_insert_text(
    hg_engine *engine,
    uint32_t section,
    uint32_t paragraph,
    uint32_t char_offset,
    const char *text
);

/**
 * Delete `count` characters at (section, paragraph, char_offset).
 * Product gate: plain_text drops the range; hg_save_hwpx clear-before-save
 * ZIP has 0 hp:linesegarray; reopen stays without it.
 * Invalid section/paragraph → HG_CORRUPT / CORRUPT.
 */
hg_status hg_delete_range(
    hg_engine *engine,
    uint32_t section,
    uint32_t paragraph,
    uint32_t char_offset,
    uint32_t count
);

/**
 * List tables (DocumentCore IR walk — no ZIP/XML parser).
 *
 * Writes min(capacity, table count) entries into `out_tables`.
 * On HG_OK, *out_count is the total table count (may exceed capacity).
 * Pass capacity 0 / out_tables NULL to query the count only.
 *
 * Kit: use `index` + `rows`/`cols` to address cells via hg_set_cell_text.
 */
hg_status hg_list_tables(
    hg_engine *engine,
    hg_table_info *out_tables,
    size_t capacity,
    size_t *out_count
);

/**
 * List pictures (DocumentCore IR walk — no ZIP/XML parser, no BinData extract).
 *
 * Writes min(capacity, image count) entries into `out_images`.
 * On HG_OK, *out_count is the total picture count (may exceed capacity).
 * Pass capacity 0 / out_images NULL to query the count only.
 *
 * Kit: use `index` + `section`/`paragraph`/`control` + size/format meta
 * (`width`/`height`/`format`/`bin_data_id`/`href`) to address images.
 */
hg_status hg_list_images(
    hg_engine *engine,
    hg_image_info *out_images,
    size_t capacity,
    size_t *out_count
);

/**
 * Set cell plain text at (table, row, col).
 *
 * `table` is `hg_table_info.index` from hg_list_tables.
 * Replaces that cell's plain text (first paragraph; extra cell paragraphs
 * cleared). Merged cells: any covered (row, col) hits the anchor cell.
 *
 * Kit: TableBlock cell edit. Invalid table/row/col → HG_CORRUPT / CORRUPT.
 */
hg_status hg_set_cell_text(
    hg_engine *engine,
    uint32_t table,
    uint32_t row,
    uint32_t col,
    const char *text
);

/**
 * Read-only page preview as UTF-8 SVG (layer + RenderProfile::Screen).
 *
 * Does not mutate IR for save; `hg_save` / `hg_save_hwpx` still clear
 * `line_segs`. Same buffer ownership as hg_plain_text: on HG_OK, *out_bytes
 * is an engine-owned buffer of *out_length bytes; free with hg_free_buffer.
 *
 * `page_index` is 0-based. Out of range → HG_CORRUPT / CORRUPT (same four
 * statuses as invalid insert/delete indexes — not HG_UNSUPPORTED).
 *
 * PNG / native-skia are not exported. See docs/engine/hg-render-abi.md.
 */
hg_status hg_render_page_svg(
    hg_engine *engine,
    uint32_t page_index,
    uint8_t **out_bytes,
    size_t *out_length
);

/**
 * Freeze string code for the last failed call on this thread, or NULL after
 * success: "UNSUPPORTED_VERSION" | "ENCRYPTED" | "CORRUPT" | "SAVE_REJECTED".
 */
const char *hg_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* HANGYEOL_ENGINE_H */
