//! Product FFI: `hg_render_page_svg` (SVG only, layer + Screen).
//!
//! Keeps `gates.rs` and `render_spike.rs` as the existing product / §8
//! suites. This file locks the C ABI: hub-A non-empty SVG, render-then-save
//! still clears `line_segs`, hub-B keep-on-save, out-of-range `HG_CORRUPT`,
//! `nm` shows `hg_render_page_svg` and no PNG/skia product symbols.

use hangyeol_engine::{
    hg_close, hg_engine, hg_free_buffer, hg_insert_text, hg_last_error, hg_list_images, hg_open,
    hg_plain_text, hg_render_page_svg, hg_replace_text, hg_save, HangyeolError, HgImageInfo,
    HgStatus,
};
use std::ffi::CStr;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ptr;

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures")
}

fn testdata_out() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/out")
}

fn read_fixture(name: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(name)).unwrap_or_else(|e| panic!("read {name}: {e}"))
}

fn last_error_str() -> Option<&'static str> {
    let ptr = hg_last_error();
    if ptr.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(ptr) }.to_str().unwrap())
    }
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

fn utf8_from_buf(ptr: *mut u8, len: usize) -> String {
    assert!(!ptr.is_null());
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    String::from_utf8(bytes.to_vec()).expect("utf-8")
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

fn open_bytes(bytes: &[u8]) -> *mut hg_engine {
    let mut engine: *mut hg_engine = ptr::null_mut();
    let status = unsafe { hg_open(bytes.as_ptr(), bytes.len(), 0, &mut engine) };
    assert_eq!(status, HgStatus::Ok, "hg_open {:?}", last_error_str());
    assert!(!engine.is_null());
    engine
}

fn render_svg(engine: *mut hg_engine, page: u32) -> Result<String, HgStatus> {
    let mut out = ptr::null_mut();
    let mut len = 0usize;
    let status = unsafe { hg_render_page_svg(engine, page, &mut out, &mut len) };
    if status != HgStatus::Ok {
        assert!(out.is_null());
        assert_eq!(len, 0);
        return Err(status);
    }
    let svg = utf8_from_buf(out, len);
    unsafe { hg_free_buffer(out) };
    Ok(svg)
}

fn list_images(engine: *mut hg_engine) -> Vec<HgImageInfo> {
    let mut count = 0usize;
    let status = unsafe { hg_list_images(engine, ptr::null_mut(), 0, &mut count) };
    assert_eq!(status, HgStatus::Ok, "list count {:?}", last_error_str());
    if count == 0 {
        return Vec::new();
    }
    let mut infos = vec![HgImageInfo::zeroed(); count];
    let status = unsafe { hg_list_images(engine, infos.as_mut_ptr(), infos.len(), &mut count) };
    assert_eq!(status, HgStatus::Ok, "list fill {:?}", last_error_str());
    infos.truncate(count);
    infos
}

fn plain_text(engine: *mut hg_engine) -> String {
    let mut text_ptr = ptr::null_mut();
    let mut text_len = 0usize;
    let status = unsafe { hg_plain_text(engine, &mut text_ptr, &mut text_len) };
    assert_eq!(status, HgStatus::Ok, "{:?}", last_error_str());
    let text = utf8_from_buf(text_ptr, text_len);
    unsafe { hg_free_buffer(text_ptr) };
    text
}

fn engine_header() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("include/hangyeol_engine.h")
}

fn kit_header() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../Packages/HangyeolKit/Sources/CHangyeolEngine/include/hangyeol_engine.h")
}

/// Engine header and Kit copy stay byte-identical; SVG preview is allowed,
/// PNG / native-skia are not product symbols.
#[test]
fn header_svg_preview_no_png_skia_kit_sync() {
    let engine = std::fs::read_to_string(engine_header()).expect("engine header");
    let kit = std::fs::read_to_string(kit_header()).expect("kit header");
    assert_eq!(
        engine, kit,
        "Kit hangyeol_engine.h must match engine/include/hangyeol_engine.h"
    );
    assert!(
        engine.contains("hg_render_page_svg"),
        "product ABI must export hg_render_page_svg"
    );
    assert!(
        engine.contains("RenderProfile::Screen"),
        "banner/docs in header must name the Screen profile"
    );
    assert!(
        !engine.contains("hg_render_page_png"),
        "PNG FFI is forbidden"
    );
    assert!(
        !engine.to_ascii_lowercase().contains("native-skia")
            || engine.contains("PNG / native-skia are not exported"),
        "native-skia must stay a prohibition, not an export"
    );
    assert!(
        !engine.contains("No renderer / layout / WASM UI is exported"),
        "outdated 'No renderer exported' claim must be gone"
    );
}

/// hub-A page 0 via `hg_render_page_svg` → non-empty UTF-8 SVG.
#[test]
fn hub_a_page0_hg_render_page_svg_non_empty() {
    unsafe {
        let bytes = read_fixture("hub_hwpxlib_SimpleTable.hwpx");
        let engine = open_bytes(&bytes);
        let svg = render_svg(engine, 0).expect("hg_render_page_svg(0)");
        assert_svg_non_empty("hg_render_page_svg hub-A page0", &svg);
        write_out("hub-A-page0-hg-render-page-svg.svg", svg.as_bytes());
        hg_close(engine);
    }
}

/// Out-of-range page index is addressing CORRUPT, not UNSUPPORTED.
#[test]
fn hub_a_render_page_out_of_range_is_corrupt() {
    unsafe {
        let bytes = read_fixture("hub_hwpxlib_SimpleTable.hwpx");
        let engine = open_bytes(&bytes);
        let status = render_svg(engine, 99).unwrap_err();
        assert_eq!(status, HgStatus::Corrupt);
        assert_eq!(last_error_str(), Some("CORRUPT"));
        assert_eq!(HangyeolError::Corrupt.as_str(), "CORRUPT");
        hg_close(engine);
    }
}

/// Render through FFI then hub-A replace + `hg_save` still emits 0 lineseg.
#[test]
fn hub_a_hg_render_then_replace_clear_before_save() {
    unsafe {
        let bytes = read_fixture("hub_hwpxlib_SimpleTable.hwpx");
        assert!(
            count_linesegarray(&bytes) > 0,
            "hub-A fixture must contain hp:linesegarray so the clear gate is meaningful"
        );
        let engine = open_bytes(&bytes);
        let svg = render_svg(engine, 0).expect("pre-save SVG");
        assert_svg_non_empty("pre-save hg_render_page_svg", &svg);

        let find = std::ffi::CString::new("1").unwrap();
        let replace = std::ffi::CString::new("HGPOC99").unwrap();
        let mut count = 0usize;
        let status = hg_replace_text(engine, find.as_ptr(), replace.as_ptr(), &mut count);
        assert_eq!(status, HgStatus::Ok, "{:?}", last_error_str());
        assert!(count >= 1, "expected at least one replacement, got {count}");

        let mut saved_ptr = ptr::null_mut();
        let mut saved_len = 0usize;
        let status = hg_save(engine, 0, &mut saved_ptr, &mut saved_len);
        assert_eq!(status, HgStatus::Ok, "hg_save {:?}", last_error_str());
        let saved = std::slice::from_raw_parts(saved_ptr, saved_len).to_vec();
        hg_free_buffer(saved_ptr);
        hg_close(engine);

        assert_eq!(
            count_linesegarray(&saved),
            0,
            "render then hg_save must still emit 0 hp:linesegarray"
        );
        write_out("SimpleTable-hg-render-then-cleared.hwpx", &saved);

        let engine2 = open_bytes(&saved);
        let text = plain_text(engine2);
        hg_close(engine2);
        assert!(
            text.contains("HGPOC99"),
            "replacement token must survive export, got {text:?}"
        );
    }
}

/// hub-B: FFI render page 0, then keep-on-save stays green.
#[test]
fn hub_b_hg_render_then_keep_on_save() {
    unsafe {
        let bytes = read_fixture("hub_hwpxlib_SimplePicture.hwpx");
        let original_bins = zip_bindata_entries(&bytes);
        assert!(!original_bins.is_empty(), "hub-B must contain BinData/");

        let engine = open_bytes(&bytes);
        let before = list_images(engine);
        assert!(
            !before.is_empty(),
            "hub-B SimplePicture must list ≥1 image, got {}",
            before.len()
        );

        let svg = render_svg(engine, 0).expect("hub-B hg_render_page_svg");
        assert_svg_non_empty("hub-B hg_render_page_svg", &svg);

        let token = std::ffi::CString::new("HGIMG99").unwrap();
        let status = hg_insert_text(engine, 0, 0, 0, token.as_ptr());
        assert_eq!(status, HgStatus::Ok, "insert {:?}", last_error_str());
        assert!(plain_text(engine).contains("HGIMG99"));

        let mut saved_ptr = ptr::null_mut();
        let mut saved_len = 0usize;
        let status = hg_save(engine, 0, &mut saved_ptr, &mut saved_len);
        assert_eq!(status, HgStatus::Ok, "hg_save {:?}", last_error_str());
        let saved = std::slice::from_raw_parts(saved_ptr, saved_len).to_vec();
        hg_free_buffer(saved_ptr);
        hg_close(engine);

        assert_eq!(
            count_linesegarray(&saved),
            0,
            "hub-B render-then-save must emit 0 hp:linesegarray"
        );
        let saved_bins = zip_bindata_entries(&saved);
        assert_eq!(saved_bins.len(), original_bins.len());
        assert_eq!(saved_bins, original_bins);

        let engine2 = open_bytes(&saved);
        let after = list_images(engine2);
        assert_eq!(after.len(), before.len());
        assert_eq!(after[0].width, before[0].width);
        assert_eq!(after[0].height, before[0].height);
        assert_eq!(after[0].format, before[0].format);
        assert_eq!(after[0].bin_data_id, before[0].bin_data_id);
        let again = plain_text(engine2);
        hg_close(engine2);
        assert!(
            again.contains("HGIMG99"),
            "inserted token must survive export, got {again:?}"
        );
    }
}

fn cdylib_path() -> PathBuf {
    let exe = std::env::current_exe().expect("current_exe");
    // cargo test binary: <target>/debug/deps/render_ffi-<hash>
    let debug_dir = exe
        .parent()
        .and_then(Path::parent)
        .expect("debug dir from test exe");
    for name in [
        "libhangyeol_engine.so",
        "libhangyeol_engine.dylib",
        "hangyeol_engine.dll",
        "libhangyeol_engine.a",
    ] {
        let candidate = debug_dir.join(name);
        if candidate.is_file() {
            return candidate;
        }
    }
    panic!("cdylib/staticlib not found next to {debug_dir:?} (exe {exe:?})");
}

fn nm_defined_text(lib: &Path) -> String {
    let output = Command::new("nm")
        .args(["-g", "--defined-only"])
        .arg(lib)
        .output()
        .unwrap_or_else(|e| panic!("nm {lib:?}: {e}"));
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    if text.trim().is_empty() {
        // ELF cdylib: dynamic table
        let dyn_out = Command::new("nm")
            .args(["-D", "--defined-only"])
            .arg(lib)
            .output()
            .unwrap_or_else(|e| panic!("nm -D {lib:?}: {e}"));
        text = String::from_utf8_lossy(&dyn_out.stdout).into_owned();
    }
    text
}

/// `nm` on the product lib: `hg_render_page_svg` present, no PNG FFI, no skia_safe.
#[test]
fn nm_shows_hg_render_page_svg_no_skia() {
    let lib = cdylib_path();
    let nm = nm_defined_text(&lib);
    assert!(
        nm.contains("hg_render_page_svg"),
        "expected hg_render_page_svg in nm of {lib:?}\n{nm}"
    );
    assert!(
        !nm.contains("hg_render_page_png"),
        "PNG FFI must not be exported from {lib:?}"
    );
    let lower = nm.to_ascii_lowercase();
    assert!(
        !lower.contains("skia_safe") && !lower.contains("hg_render_page_png"),
        "native-skia / PNG product symbols must be absent in {lib:?}"
    );
}

/// Default features must not turn on native-skia (belt-and-suspenders with nm).
#[test]
fn cargo_toml_does_not_default_native_skia() {
    let toml =
        std::fs::read_to_string(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml"))
            .expect("Cargo.toml");
    let features = toml
        .split("[features]")
        .nth(1)
        .and_then(|rest| rest.split('[').next())
        .expect("[features]");
    assert!(
        features.contains("default = []"),
        "product default features must stay empty, got {features}"
    );
    assert!(
        features.contains("native-skia = [\"rhwp/native-skia\"]"),
        "native-skia must remain an explicit opt-in"
    );
}
