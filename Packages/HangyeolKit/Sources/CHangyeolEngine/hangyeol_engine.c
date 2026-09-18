#include "hangyeol_engine.h"

/*
 * Stub implementation: always fail. No real parser, no decrypt, no write.
 *
 * Symbols match engine/include/hangyeol_engine.h (source of truth). This .c
 * is NOT the Rust cdylib — Package.swift compiles it only when
 * HangyeolEngine.xcframework is absent (Linux CI / no Vendor). When the
 * XCFramework is present, shim.c is compiled instead so live hg_* come
 * from the binary. Apps/Hangyeol must not depend on HangyeolKit yet;
 * MockEngine stays live in the app.
 */

hg_status hg_open(
    const uint8_t *bytes,
    size_t length,
    hg_file_type type,
    hg_engine **out_engine
) {
    (void)bytes;
    (void)length;
    (void)type;
    if (out_engine) {
        *out_engine = NULL;
    }
    return HG_UNSUPPORTED;
}

hg_status hg_save(
    hg_engine *engine,
    hg_file_type type,
    uint8_t **out_bytes,
    size_t *out_length
) {
    (void)engine;
    (void)type;
    if (out_bytes) {
        *out_bytes = NULL;
    }
    if (out_length) {
        *out_length = 0;
    }
    return HG_UNSUPPORTED;
}

void hg_free_buffer(uint8_t *bytes) {
    (void)bytes;
}

void hg_close(hg_engine *engine) {
    (void)engine;
}

hg_status hg_plain_text(
    hg_engine *engine,
    uint8_t **out_bytes,
    size_t *out_length
) {
    (void)engine;
    if (out_bytes) {
        *out_bytes = NULL;
    }
    if (out_length) {
        *out_length = 0;
    }
    return HG_UNSUPPORTED;
}

hg_status hg_replace_text(
    hg_engine *engine,
    const char *find,
    const char *replace,
    size_t *out_count
) {
    (void)engine;
    (void)find;
    (void)replace;
    if (out_count) {
        *out_count = 0;
    }
    return HG_UNSUPPORTED;
}

hg_status hg_save_hwpx(
    hg_engine *engine,
    const char *path
) {
    (void)engine;
    (void)path;
    return HG_UNSUPPORTED;
}

hg_status hg_insert_text(
    hg_engine *engine,
    uint32_t section,
    uint32_t paragraph,
    uint32_t char_offset,
    const char *text
) {
    (void)engine;
    (void)section;
    (void)paragraph;
    (void)char_offset;
    (void)text;
    return HG_UNSUPPORTED;
}

hg_status hg_delete_range(
    hg_engine *engine,
    uint32_t section,
    uint32_t paragraph,
    uint32_t char_offset,
    uint32_t count
) {
    (void)engine;
    (void)section;
    (void)paragraph;
    (void)char_offset;
    (void)count;
    return HG_UNSUPPORTED;
}

hg_status hg_list_tables(
    hg_engine *engine,
    hg_table_info *out_tables,
    size_t capacity,
    size_t *out_count
) {
    (void)engine;
    (void)out_tables;
    (void)capacity;
    if (out_count) {
        *out_count = 0;
    }
    return HG_UNSUPPORTED;
}

hg_status hg_list_images(
    hg_engine *engine,
    hg_image_info *out_images,
    size_t capacity,
    size_t *out_count
) {
    (void)engine;
    (void)out_images;
    (void)capacity;
    if (out_count) {
        *out_count = 0;
    }
    return HG_UNSUPPORTED;
}

hg_status hg_set_cell_text(
    hg_engine *engine,
    uint32_t table,
    uint32_t row,
    uint32_t col,
    const char *text
) {
    (void)engine;
    (void)table;
    (void)row;
    (void)col;
    (void)text;
    return HG_UNSUPPORTED;
}

hg_status hg_render_page_svg(
    hg_engine *engine,
    uint32_t page_index,
    uint8_t **out_bytes,
    size_t *out_length
) {
    (void)engine;
    (void)page_index;
    if (out_bytes) {
        *out_bytes = NULL;
    }
    if (out_length) {
        *out_length = 0;
    }
    return HG_UNSUPPORTED;
}

const char *hg_last_error(void) {
    return NULL;
}
