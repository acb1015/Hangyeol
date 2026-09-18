//! §8 Path B native SVG spike (lead-approved). DocumentCore render APIs.
//!
//! Product C ABI `hg_render_page_svg` lives in `render_ffi.rs` (SVG only).
//! This file keeps the original DocumentCore spike (no app wiring).
//! rhwp pin: `cac9b4f7cc743535cd7c00fe4f286abd67e7145b`.

use hangyeol_engine::{
    insert_text, list_images, open_bytes, plain_text, replace_text, save_hwpx_bytes, HgImageInfo,
};
use rhwp::paint::RenderProfile;
use std::io::Read;
use std::path::PathBuf;

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures")
}

fn testdata_out() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/out")
}

fn read_fixture(name: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(name)).unwrap_or_else(|e| panic!("read {name}: {e}"))
}

fn hub_a() -> Vec<u8> {
    read_fixture("hub_hwpxlib_SimpleTable.hwpx")
}

fn hub_b() -> Vec<u8> {
    read_fixture("hub_hwpxlib_SimplePicture.hwpx")
}

fn count_linesegarray(hwpx: &[u8]) -> usize {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(hwpx)).expect("zip");
    let mut total = 0usize;
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).expect("entry");
        if !file.name().ends_with(".xml") {
            continue;
        }
        let mut xml = String::new();
        file.read_to_string(&mut xml).expect("xml");
        total += xml.matches("hp:linesegarray").count();
    }
    total
}

fn zip_bindata_entries(hwpx: &[u8]) -> Vec<(String, Vec<u8>)> {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(hwpx)).expect("zip");
    let mut out = Vec::new();
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).expect("entry");
        let name = file.name().to_string();
        if !name.starts_with("BinData/") {
            continue;
        }
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes).expect("bindata");
        out.push((name, bytes));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn assert_svg_non_empty(label: &str, svg: &str) {
    assert!(!svg.trim().is_empty(), "{label}: SVG must be non-empty");
    let head: String = svg.chars().take(120).collect();
    assert!(
        svg.contains("<svg"),
        "{label}: expected an <svg> root, got prefix {head:?}"
    );
}

fn write_out(name: &str, bytes: &[u8]) {
    let dir = testdata_out();
    std::fs::create_dir_all(&dir).expect("testdata/out");
    std::fs::write(dir.join(name), bytes).unwrap_or_else(|e| panic!("write {name}: {e}"));
}

fn assert_image_meta_valid(infos: &[HgImageInfo]) {
    assert!(
        !infos.is_empty(),
        "hub-B SimplePicture must list ≥1 image, got {}",
        infos.len()
    );
    let img = &infos[0];
    assert_eq!(img.index, 0);
    assert!(
        img.width > 0 && img.height > 0,
        "size meta width={} height={}",
        img.width,
        img.height
    );
    let fmt = img.format_str();
    assert!(
        matches!(fmt, "jpg" | "jpeg" | "png" | "gif" | "bmp"),
        "format meta {fmt:?}"
    );
    assert!(
        img.bin_data_id > 0 || !img.href_str().is_empty(),
        "Kit addressing needs bin_data_id or href"
    );
}

/// Product header exports SVG preview only (PNG / native-skia stay closed).
/// Full FFI gates live in `render_ffi.rs`; this keeps the §8 spike file.
#[test]
fn ffi_header_svg_only_no_png() {
    let header = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("include/hangyeol_engine.h");
    let text = std::fs::read_to_string(&header).expect("hangyeol_engine.h");
    assert!(
        text.contains("hg_render_page_svg"),
        "product ABI must export hg_render_page_svg in {header:?}"
    );
    assert!(
        !text.contains("hg_render_page_png"),
        "PNG FFI must stay closed in {header:?}"
    );
}

/// hub-A page 0: both DocumentCore SVG APIs return non-empty SVG.
#[test]
fn hub_a_page0_svg_native_and_layer_screen_non_empty() {
    let bytes = hub_a();
    let core = open_bytes(&bytes).expect("open hub-A");

    let legacy = core
        .render_page_svg_native(0)
        .expect("render_page_svg_native(0)");
    assert_svg_non_empty("render_page_svg_native", &legacy);
    write_out("hub-A-page0-svg-native.svg", legacy.as_bytes());

    let layer = core
        .render_page_svg_layer_with_profile_native(0, RenderProfile::Screen)
        .expect("render_page_svg_layer_with_profile_native(0, Screen)");
    assert_svg_non_empty("render_page_svg_layer_with_profile_native Screen", &layer);
    write_out("hub-A-page0-svg-layer-screen.svg", layer.as_bytes());
}

/// Render must not bypass Hangyeol clear-before-save. hub-A replace then
/// `save_hwpx_bytes` still emits 0 `hp:linesegarray`.
#[test]
fn hub_a_render_then_replace_clear_before_save() {
    let bytes = hub_a();
    assert!(
        count_linesegarray(&bytes) > 0,
        "hub-A fixture must contain hp:linesegarray so the clear gate is meaningful"
    );

    let mut core = open_bytes(&bytes).expect("open hub-A");
    let svg = core
        .render_page_svg_native(0)
        .expect("render_page_svg_native(0)");
    assert_svg_non_empty("pre-save legacy SVG", &svg);
    let layer = core
        .render_page_svg_layer_with_profile_native(0, RenderProfile::Screen)
        .expect("layer Screen");
    assert_svg_non_empty("pre-save layer SVG", &layer);

    let count = replace_text(&mut core, "1", "HGPOC99").expect("replace");
    assert!(count >= 1, "expected at least one replacement, got {count}");

    let saved = save_hwpx_bytes(&mut core).expect("clear-before-save");
    assert_eq!(
        count_linesegarray(&saved),
        0,
        "render then hg_save recipe must still emit 0 hp:linesegarray"
    );
    write_out("SimpleTable-render-then-cleared.hwpx", &saved);

    let reopened = open_bytes(&saved).expect("reopen");
    let text = plain_text(&reopened);
    assert!(
        text.contains("HGPOC99"),
        "replacement token must survive export, got {text:?}"
    );
}

/// hub-B: render page 0, then keep-on-save (insert + clear-before-save) stays green.
#[test]
fn hub_b_render_then_keep_on_save() {
    let bytes = hub_b();
    let original_bins = zip_bindata_entries(&bytes);
    assert!(!original_bins.is_empty(), "hub-B must contain BinData/");

    let mut core = open_bytes(&bytes).expect("open hub-B");
    let before = list_images(&core);
    assert_image_meta_valid(&before);

    let svg = core
        .render_page_svg_native(0)
        .expect("render_page_svg_native(0) hub-B");
    assert_svg_non_empty("hub-B legacy SVG", &svg);
    let layer = core
        .render_page_svg_layer_with_profile_native(0, RenderProfile::Screen)
        .expect("hub-B layer Screen");
    assert_svg_non_empty("hub-B layer SVG", &layer);

    insert_text(&mut core, 0, 0, 0, "HGIMG99").expect("insert");
    assert!(plain_text(&core).contains("HGIMG99"));

    let exported = save_hwpx_bytes(&mut core).expect("clear-before-save");
    assert_eq!(
        count_linesegarray(&exported),
        0,
        "hub-B render-then-save must emit 0 hp:linesegarray"
    );

    let saved_bins = zip_bindata_entries(&exported);
    assert_eq!(saved_bins.len(), original_bins.len());
    assert_eq!(saved_bins, original_bins);

    let reopened = open_bytes(&exported).expect("reopen");
    let after = list_images(&reopened);
    assert_image_meta_valid(&after);
    assert_eq!(after.len(), before.len());
    assert_eq!(after[0].width, before[0].width);
    assert_eq!(after[0].height, before[0].height);
    assert_eq!(after[0].format, before[0].format);
    assert_eq!(after[0].bin_data_id, before[0].bin_data_id);
    let again = plain_text(&reopened);
    assert!(
        again.contains("HGIMG99"),
        "inserted token must survive export, got {again:?}"
    );
}
