//! Thin Hangyeol FFI over `rhwp::document_core::DocumentCore`.
//!
//! No OLE/HWP binary parser of our own, no ZIP/XML product writer, no
//! renderer / layout / WASM UI **FFI** exports (`hg_render_*` is not in the
//! header). §8 spike tests call DocumentCore SVG APIs directly. Save always
//! clears `line_segs` (verified Hangyeol recipe) before `export_hwpx_native`.
//!
//! Image-meta *list* (`hg_list_images`) walks `Control::Picture` in document
//! order and returns index + `href` / `img_dim` / format meta. No BinData
//! extract API. Keep-on-save of ZIP `BinData/` through clear-before-save is a
//! hub-B product gate. Fixture: hub-B.

mod error;
#[cfg(any(feature = "svg-size-probe", feature = "native-skia"))]
mod size_probe;

pub use error::{HangyeolError, HgFileType, HgStatus};
#[cfg(feature = "svg-size-probe")]
pub use size_probe::spike_link_svg_page0;
#[cfg(feature = "native-skia")]
pub use size_probe::spike_link_png_page0;

use error::{clear_last_error, last_error_c_str, set_last_error};
use rhwp::document_core::DocumentCore;
use rhwp::error::HwpError;
use rhwp::model::control::Control;
use rhwp::model::document::Document;
use rhwp::model::image::Picture;
use rhwp::model::paragraph::Paragraph;
use rhwp::model::table::{Cell, Table};
use rhwp::parser::{detect_format, FileFormat};
use std::ffi::{c_char, CStr};
use std::panic::{self, AssertUnwindSafe};
use std::path::Path;
use std::ptr;
use std::slice;
use std::sync::Mutex;

/// C `hg_table_info`. Kit uses `index` as `hg_set_cell_text`'s `table`.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HgTableInfo {
    pub index: u32,
    pub section: u32,
    pub paragraph: u32,
    pub control: u32,
    pub rows: u32,
    pub cols: u32,
}

/// C `hg_image_info` format / href buffer sizes (must match the header).
pub const HG_IMAGE_FORMAT_LEN: usize = 16;
pub const HG_IMAGE_HREF_LEN: usize = 128;

/// C `hg_image_info`. Kit uses `index` + size/format meta to address pictures.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HgImageInfo {
    pub index: u32,
    pub section: u32,
    pub paragraph: u32,
    pub control: u32,
    pub width: u32,
    pub height: u32,
    pub byte_len: u32,
    pub bin_data_id: u32,
    pub format: [u8; HG_IMAGE_FORMAT_LEN],
    pub href: [u8; HG_IMAGE_HREF_LEN],
}

impl HgImageInfo {
    pub fn zeroed() -> Self {
        Self {
            index: 0,
            section: 0,
            paragraph: 0,
            control: 0,
            width: 0,
            height: 0,
            byte_len: 0,
            bin_data_id: 0,
            format: [0; HG_IMAGE_FORMAT_LEN],
            href: [0; HG_IMAGE_HREF_LEN],
        }
    }

    pub fn format_str(&self) -> &str {
        c_fixed_str(&self.format)
    }

    pub fn href_str(&self) -> &str {
        c_fixed_str(&self.href)
    }
}

fn c_fixed_copy(dst: &mut [u8], src: &str) {
    dst.fill(0);
    let bytes = src.as_bytes();
    let n = bytes.len().min(dst.len().saturating_sub(1));
    dst[..n].copy_from_slice(&bytes[..n]);
}

fn c_fixed_str(buf: &[u8]) -> &str {
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    std::str::from_utf8(&buf[..end]).unwrap_or("")
}

/// Opaque session pointer type for the C ABI (`typedef struct hg_engine hg_engine`).
#[allow(non_camel_case_types)]
pub struct hg_engine {
    core: DocumentCore,
}

struct AllocBuf {
    bytes: Vec<u8>,
}

static BUFFERS: Mutex<Vec<AllocBuf>> = Mutex::new(Vec::new());

fn fail(err: HangyeolError) -> HgStatus {
    set_last_error(err);
    err.status()
}

fn ok() -> HgStatus {
    clear_last_error();
    HgStatus::Ok
}

/// Map rhwp open failures onto Hangyeol freeze codes.
///
/// Truncated / unknown / malformed containers become **CORRUPT** (F16),
/// not a vague `UNSUPPORTED_FILE_FORMAT` passthrough.
pub fn map_open_format(format: FileFormat) -> Result<(), HangyeolError> {
    match format {
        FileFormat::Hwp | FileFormat::Hwpx => Ok(()),
        FileFormat::Hwp3 | FileFormat::Hml => Err(HangyeolError::UnsupportedVersion),
        FileFormat::DrmProtected => Err(HangyeolError::UnsupportedVersion),
        FileFormat::Empty | FileFormat::Unknown => Err(HangyeolError::Corrupt),
    }
}

/// Classify an open-path error message (HwpError Display / ParseError text).
/// Design-only ENCRYPTED mapping — no encrypted fixture is required.
pub fn map_open_message(msg: &str) -> HangyeolError {
    if msg.contains("EncryptedDocument")
        || msg.contains("비밀번호")
        || msg.contains("암호 문서")
        || msg.contains("암호화된 문서")
    {
        return HangyeolError::Encrypted;
    }
    if msg.contains("UNSUPPORTED_HWP3")
        || msg.contains("HWP 3.0")
        || msg.contains("UNSUPPORTED_HML")
    {
        return HangyeolError::UnsupportedVersion;
    }
    if msg.contains("DRM_PROTECTED") {
        return HangyeolError::UnsupportedVersion;
    }
    // Includes UNSUPPORTED_FILE_FORMAT (truncated ZIP / unknown magic) → CORRUPT.
    HangyeolError::Corrupt
}

fn map_open_hwp_error(err: HwpError) -> HangyeolError {
    map_open_message(&err.to_string())
}

/// Verified Hangyeol clear-before-save recipe (hub-A gate):
/// after `replace_all_native`, walk `document_mut` **sections / paras /
/// table cell paras** and `line_segs.clear()`, then `export_hwpx_native`.
/// Default rhwp export leaves `hp:linesegarray`.
pub fn clear_all_line_segs(core: &mut DocumentCore) {
    let document = core.document_mut();
    for section in &mut document.sections {
        for para in &mut section.paragraphs {
            para.line_segs.clear();
            for control in &mut para.controls {
                if let Control::Table(table) = control {
                    for cell in &mut table.cells {
                        for cell_para in &mut cell.paragraphs {
                            cell_para.line_segs.clear();
                        }
                    }
                }
            }
        }
    }
}

fn collect_plain_text(document: &Document) -> String {
    let mut out = String::new();
    for section in &document.sections {
        for para in &section.paragraphs {
            append_para_text(para, &mut out);
        }
    }
    out
}

fn append_para_text(para: &Paragraph, out: &mut String) {
    let trimmed = para.text.trim();
    if !trimmed.is_empty() {
        if !out.is_empty() {
            out.push('\n');
        }
        out.push_str(trimmed);
    }
    for control in &para.controls {
        if let Control::Table(table) = control {
            for cell in &table.cells {
                for cell_para in &cell.paragraphs {
                    append_para_text(cell_para, out);
                }
            }
        }
    }
}

/// Document-order tables (body, then nested cell tables). `index` is the
/// `table` argument for `hg_set_cell_text`.
pub fn list_tables(core: &DocumentCore) -> Vec<HgTableInfo> {
    collect_tables(core.document())
}

fn collect_tables(document: &Document) -> Vec<HgTableInfo> {
    let mut out = Vec::new();
    for (sec_i, section) in document.sections.iter().enumerate() {
        for (para_i, para) in section.paragraphs.iter().enumerate() {
            collect_tables_in_para(para, sec_i, para_i, &mut out);
        }
    }
    for (i, info) in out.iter_mut().enumerate() {
        info.index = i as u32;
    }
    out
}

fn collect_tables_in_para(
    para: &Paragraph,
    section: usize,
    paragraph: usize,
    out: &mut Vec<HgTableInfo>,
) {
    for (ctrl_i, control) in para.controls.iter().enumerate() {
        if let Control::Table(table) = control {
            out.push(HgTableInfo {
                index: out.len() as u32,
                section: section as u32,
                paragraph: paragraph as u32,
                control: ctrl_i as u32,
                rows: u32::from(table.row_count),
                cols: u32::from(table.col_count),
            });
            for cell in &table.cells {
                for cell_para in &cell.paragraphs {
                    collect_tables_in_para(cell_para, section, paragraph, out);
                }
            }
        }
    }
}

/// Document-order pictures (body, then nested cell pictures). `index` is the
/// Kit addressing id for `hg_list_images`.
pub fn list_images(core: &DocumentCore) -> Vec<HgImageInfo> {
    collect_images(core.document())
}

fn collect_images(document: &Document) -> Vec<HgImageInfo> {
    let mut out = Vec::new();
    for (sec_i, section) in document.sections.iter().enumerate() {
        for (para_i, para) in section.paragraphs.iter().enumerate() {
            collect_images_in_para(document, para, sec_i, para_i, &mut out);
        }
    }
    for (i, info) in out.iter_mut().enumerate() {
        info.index = i as u32;
    }
    out
}

fn collect_images_in_para(
    document: &Document,
    para: &Paragraph,
    section: usize,
    paragraph: usize,
    out: &mut Vec<HgImageInfo>,
) {
    for (ctrl_i, control) in para.controls.iter().enumerate() {
        match control {
            Control::Picture(pic) => {
                out.push(image_info_from_picture(
                    document, pic, section, paragraph, ctrl_i,
                ));
            }
            Control::Table(table) => {
                for cell in &table.cells {
                    for cell_para in &cell.paragraphs {
                        collect_images_in_para(document, cell_para, section, paragraph, out);
                    }
                }
            }
            _ => {}
        }
    }
}

fn image_info_from_picture(
    document: &Document,
    pic: &Picture,
    section: usize,
    paragraph: usize,
    control: usize,
) -> HgImageInfo {
    let (width, height) = if pic.img_dim.0 > 0 && pic.img_dim.1 > 0 {
        pic.img_dim
    } else {
        (pic.common.width, pic.common.height)
    };
    let (byte_len, format, href) = image_bin_meta(document, pic);
    let mut info = HgImageInfo::zeroed();
    info.section = section as u32;
    info.paragraph = paragraph as u32;
    info.control = control as u32;
    info.width = width;
    info.height = height;
    info.byte_len = byte_len;
    info.bin_data_id = u32::from(pic.image_attr.bin_data_id);
    c_fixed_copy(&mut info.format, &format);
    c_fixed_copy(&mut info.href, &href);
    info
}

fn normalize_format(raw: &str) -> String {
    let s = raw.trim().trim_start_matches('.').to_ascii_lowercase();
    if s.is_empty() {
        return String::new();
    }
    s.chars().take(HG_IMAGE_FORMAT_LEN - 1).collect()
}

/// Format / byte length / href from Picture + BinData IR metadata only.
/// Does not copy image bytes out as a product extract API.
fn image_bin_meta(document: &Document, pic: &Picture) -> (u32, String, String) {
    let id = pic.image_attr.bin_data_id;
    let mut byte_len = 0u32;
    let mut ext = String::new();
    let mut href = pic.href.as_deref().unwrap_or("").trim().to_string();

    if let Some(content) = document.bin_data_content.iter().find(|c| c.id == id) {
        byte_len = content.data.len().min(u32::MAX as usize) as u32;
        if !content.extension.trim().is_empty() {
            ext = content.extension.clone();
        }
    } else if let Some(i) = id.checked_sub(1) {
        if let Some(content) = document.bin_data_content.get(i as usize) {
            byte_len = content.data.len().min(u32::MAX as usize) as u32;
            if ext.is_empty() && !content.extension.trim().is_empty() {
                ext = content.extension.clone();
            }
        }
    }

    if let Some(entry) = document
        .doc_info
        .bin_data_list
        .iter()
        .find(|b| b.storage_id == id)
    {
        if ext.is_empty() {
            if let Some(e) = &entry.extension {
                ext = e.clone();
            }
        }
        if href.is_empty() {
            if let Some(rel) = &entry.rel_path {
                href = rel.clone();
            } else if let Some(abs) = &entry.abs_path {
                href = abs.clone();
            }
        }
    }

    let format = normalize_format(&ext);
    if href.is_empty() && id > 0 {
        href = if format.is_empty() {
            format!("image{id}")
        } else {
            format!("BinData/image{id}.{format}")
        };
    } else if format.is_empty() {
        if let Some(found) = Path::new(&href)
            .extension()
            .and_then(|e| e.to_str())
            .map(normalize_format)
        {
            return (byte_len, found, href);
        }
    }

    (byte_len, format, href)
}

fn cell_mut(table: &mut Table, row: u32, col: u32) -> Result<&mut Cell, HangyeolError> {
    let rows = u32::from(table.row_count);
    let cols = u32::from(table.col_count);
    if row >= rows || col >= cols {
        return Err(HangyeolError::Corrupt);
    }
    if !table.cell_grid.is_empty() {
        let grid_i = (row as usize)
            .checked_mul(cols as usize)
            .and_then(|v| v.checked_add(col as usize))
            .ok_or(HangyeolError::Corrupt)?;
        if let Some(Some(idx)) = table.cell_grid.get(grid_i) {
            return table.cells.get_mut(*idx).ok_or(HangyeolError::Corrupt);
        }
    }
    table
        .cells
        .iter_mut()
        .find(|c| u32::from(c.row) == row && u32::from(c.col) == col)
        .ok_or(HangyeolError::Corrupt)
}

/// Replace a cell's plain text via DocumentCore IR (`delete_text_at` /
/// `insert_text_at`). Not a ZIP/XML hand writer.
fn replace_cell_plain_text(cell: &mut Cell, text: &str) -> Result<(), HangyeolError> {
    let (first, rest) = cell
        .paragraphs
        .split_first_mut()
        .ok_or(HangyeolError::Corrupt)?;
    let old_len = first.text.chars().count();
    if old_len > 0 {
        first.delete_text_at(0, old_len);
    }
    if !text.is_empty() {
        first.insert_text_at(0, text);
    }
    for extra in rest {
        let n = extra.text.chars().count();
        if n > 0 {
            extra.delete_text_at(0, n);
        }
    }
    Ok(())
}

fn visit_table_mut(
    para: &mut Paragraph,
    target: usize,
    current: &mut usize,
    f: &mut dyn FnMut(&mut Table) -> Result<(), HangyeolError>,
) -> Result<bool, HangyeolError> {
    for control in &mut para.controls {
        if let Control::Table(table) = control {
            if *current == target {
                f(table)?;
                return Ok(true);
            }
            *current += 1;
            for cell in &mut table.cells {
                for cell_para in &mut cell.paragraphs {
                    if visit_table_mut(cell_para, target, current, f)? {
                        return Ok(true);
                    }
                }
            }
        }
    }
    Ok(false)
}

pub fn set_cell_text(
    core: &mut DocumentCore,
    table_index: u32,
    row: u32,
    col: u32,
    text: &str,
) -> Result<(), HangyeolError> {
    let document = core.document_mut();
    let mut current = 0usize;
    let mut applied = false;
    {
        let mut apply = |table: &mut Table| {
            let cell = cell_mut(table, row, col)?;
            replace_cell_plain_text(cell, text)?;
            Ok(())
        };
        for section in &mut document.sections {
            for para in &mut section.paragraphs {
                if visit_table_mut(para, table_index as usize, &mut current, &mut apply)? {
                    applied = true;
                    break;
                }
            }
            if applied {
                break;
            }
        }
    }
    if applied {
        Ok(())
    } else {
        Err(HangyeolError::Corrupt)
    }
}

fn parse_replace_count(json: &str) -> usize {
    let Some(rest) = json.split("\"count\":").nth(1) else {
        return 0;
    };
    rest.chars()
        .take_while(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .unwrap_or(0)
}

/// `hg_save_hwpx` / Kit `hg_save(HWPX)`: the verified recipe, then serialize.
fn export_hwpx_cleared(core: &mut DocumentCore) -> Result<Vec<u8>, HangyeolError> {
    clear_all_line_segs(core);
    core.export_hwpx_native()
        .map_err(|_| HangyeolError::SaveRejected)
}

fn leak_buffer(mut bytes: Vec<u8>) -> (*mut u8, usize) {
    if bytes.is_empty() {
        bytes.push(0);
        let ptr = {
            let mut guard = BUFFERS.lock().expect("buffer lock");
            guard.push(AllocBuf { bytes });
            guard.last_mut().unwrap().bytes.as_mut_ptr()
        };
        return (ptr, 0);
    }
    let len = bytes.len();
    let mut guard = BUFFERS.lock().expect("buffer lock");
    guard.push(AllocBuf { bytes });
    let ptr = guard.last_mut().unwrap().bytes.as_mut_ptr();
    (ptr, len)
}

fn take_engine<'a>(ptr: *mut hg_engine) -> Result<&'a mut hg_engine, HangyeolError> {
    if ptr.is_null() {
        return Err(HangyeolError::Corrupt);
    }
    Ok(unsafe { &mut *ptr })
}

fn c_str<'a>(ptr: *const c_char) -> Result<&'a str, HangyeolError> {
    if ptr.is_null() {
        return Err(HangyeolError::Corrupt);
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| HangyeolError::Corrupt)
}

fn write_out_engine(out: *mut *mut hg_engine, value: *mut hg_engine) {
    if !out.is_null() {
        unsafe {
            *out = value;
        }
    }
}

fn write_out_buf(out_bytes: *mut *mut u8, out_len: *mut usize, bytes: *mut u8, len: usize) {
    if !out_bytes.is_null() {
        unsafe {
            *out_bytes = bytes;
        }
    }
    if !out_len.is_null() {
        unsafe {
            *out_len = len;
        }
    }
}

fn open_bytes_inner(bytes: &[u8]) -> Result<DocumentCore, HangyeolError> {
    map_open_format(detect_format(bytes))?;
    DocumentCore::from_bytes(bytes).map_err(map_open_hwp_error)
}

fn ffi_status(f: impl FnOnce() -> Result<HgStatus, HangyeolError>) -> HgStatus {
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(status)) => status,
        Ok(Err(err)) => fail(err),
        Err(_) => fail(HangyeolError::Corrupt),
    }
}

/// Open HWP/HWPX bytes via `DocumentCore::from_bytes` (extension-agnostic).
pub fn open_bytes(bytes: &[u8]) -> Result<DocumentCore, HangyeolError> {
    open_bytes_inner(bytes)
}

/// Plain text from IR body + table cells (no renderer).
pub fn plain_text(core: &DocumentCore) -> String {
    collect_plain_text(core.document())
}

/// `replace_all_native` including table cells. Returns replacement count.
pub fn replace_text(
    core: &mut DocumentCore,
    find: &str,
    replace: &str,
) -> Result<usize, HangyeolError> {
    if find.is_empty() {
        return Ok(0);
    }
    let json = core
        .replace_all_native(find, replace, true)
        .map_err(|_| HangyeolError::Corrupt)?;
    Ok(parse_replace_count(&json))
}

/// Insert UTF-8 `text` at body `(section, paragraph, char_offset)`.
///
/// DocumentCore `insert_text_native` only. Invalid index / IR failure →
/// **CORRUPT** (no new error kinds). Persist with `save_hwpx_bytes` /
/// `hg_save_hwpx` (clear-before-save).
pub fn insert_text(
    core: &mut DocumentCore,
    section: u32,
    paragraph: u32,
    char_offset: u32,
    text: &str,
) -> Result<(), HangyeolError> {
    core.insert_text_native(
        section as usize,
        paragraph as usize,
        char_offset as usize,
        text,
    )
    .map_err(|_| HangyeolError::Corrupt)?;
    Ok(())
}

/// Delete `count` characters at body `(section, paragraph, char_offset)`.
///
/// DocumentCore `delete_text_native` only. Invalid index / IR failure →
/// **CORRUPT** (no new error kinds). Persist with `save_hwpx_bytes` /
/// `hg_save_hwpx` (clear-before-save).
pub fn delete_range(
    core: &mut DocumentCore,
    section: u32,
    paragraph: u32,
    char_offset: u32,
    count: u32,
) -> Result<(), HangyeolError> {
    core.delete_text_native(
        section as usize,
        paragraph as usize,
        char_offset as usize,
        count as usize,
    )
    .map_err(|_| HangyeolError::Corrupt)?;
    Ok(())
}

/// Clear `line_segs` then `export_hwpx_native`.
pub fn save_hwpx_bytes(core: &mut DocumentCore) -> Result<Vec<u8>, HangyeolError> {
    export_hwpx_cleared(core)
}

fn parse_file_type(file_type: i32) -> Result<HgFileType, HangyeolError> {
    match file_type {
        0 => Ok(HgFileType::Hwpx),
        1 => Ok(HgFileType::Hwp),
        _ => Err(HangyeolError::UnsupportedVersion),
    }
}

#[no_mangle]
pub unsafe extern "C" fn hg_open(
    bytes: *const u8,
    length: usize,
    _type: i32,
    out_engine: *mut *mut hg_engine,
) -> HgStatus {
    ffi_status(|| {
        write_out_engine(out_engine, ptr::null_mut());
        if out_engine.is_null() {
            return Err(HangyeolError::Corrupt);
        }
        // `_type` is Kit ABI only. Format is detected from bytes (F14).
        let _ = parse_file_type(_type);
        if bytes.is_null() && length != 0 {
            return Err(HangyeolError::Corrupt);
        }
        let slice = if length == 0 {
            &[][..]
        } else {
            unsafe { slice::from_raw_parts(bytes, length) }
        };
        let core = open_bytes_inner(slice)?;
        let engine = Box::into_raw(Box::new(hg_engine { core }));
        write_out_engine(out_engine, engine);
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_save(
    engine: *mut hg_engine,
    file_type: i32,
    out_bytes: *mut *mut u8,
    out_length: *mut usize,
) -> HgStatus {
    ffi_status(|| {
        write_out_buf(out_bytes, out_length, ptr::null_mut(), 0);
        if parse_file_type(file_type)? != HgFileType::Hwpx {
            return Err(HangyeolError::SaveRejected);
        }
        let engine = take_engine(engine)?;
        let bytes = export_hwpx_cleared(&mut engine.core)?;
        let (ptr, len) = leak_buffer(bytes);
        write_out_buf(out_bytes, out_length, ptr, len);
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_free_buffer(bytes: *mut u8) {
    if bytes.is_null() {
        return;
    }
    let mut guard = match BUFFERS.lock() {
        Ok(g) => g,
        Err(poison) => poison.into_inner(),
    };
    if let Some(idx) = guard.iter().position(|b| b.bytes.as_ptr() == bytes) {
        guard.swap_remove(idx);
    }
}

#[no_mangle]
pub unsafe extern "C" fn hg_close(engine: *mut hg_engine) {
    if engine.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(engine) });
}

#[no_mangle]
pub unsafe extern "C" fn hg_plain_text(
    engine: *mut hg_engine,
    out_bytes: *mut *mut u8,
    out_length: *mut usize,
) -> HgStatus {
    ffi_status(|| {
        write_out_buf(out_bytes, out_length, ptr::null_mut(), 0);
        let engine = take_engine(engine)?;
        let text = collect_plain_text(engine.core.document());
        let (ptr, len) = leak_buffer(text.into_bytes());
        write_out_buf(out_bytes, out_length, ptr, len);
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_replace_text(
    engine: *mut hg_engine,
    find: *const c_char,
    replace: *const c_char,
    out_count: *mut usize,
) -> HgStatus {
    ffi_status(|| {
        if !out_count.is_null() {
            unsafe {
                *out_count = 0;
            }
        }
        let engine = take_engine(engine)?;
        let find = c_str(find)?;
        let replace = c_str(replace)?;
        let count = replace_text(&mut engine.core, find, replace)?;
        if !out_count.is_null() {
            unsafe {
                *out_count = count;
            }
        }
        Ok(ok())
    })
}

/// Freeze `hg_save_hwpx`: same clear-before-save as Kit `hg_save` (HWPX).
/// Sequence: walk `document_mut` sections/paras/table cell paras →
/// `line_segs.clear()` → `export_hwpx_native`.
#[no_mangle]
pub unsafe extern "C" fn hg_save_hwpx(engine: *mut hg_engine, path: *const c_char) -> HgStatus {
    ffi_status(|| {
        let engine = take_engine(engine)?;
        let path = Path::new(c_str(path)?);
        let bytes = export_hwpx_cleared(&mut engine.core)?;
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|_| HangyeolError::SaveRejected)?;
            }
        }
        std::fs::write(path, bytes).map_err(|_| HangyeolError::SaveRejected)?;
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_insert_text(
    engine: *mut hg_engine,
    section: u32,
    paragraph: u32,
    char_offset: u32,
    text: *const c_char,
) -> HgStatus {
    ffi_status(|| {
        let engine = take_engine(engine)?;
        let text = c_str(text)?;
        insert_text(&mut engine.core, section, paragraph, char_offset, text)?;
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_delete_range(
    engine: *mut hg_engine,
    section: u32,
    paragraph: u32,
    char_offset: u32,
    count: u32,
) -> HgStatus {
    ffi_status(|| {
        let engine = take_engine(engine)?;
        delete_range(&mut engine.core, section, paragraph, char_offset, count)?;
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_list_tables(
    engine: *mut hg_engine,
    out_tables: *mut HgTableInfo,
    capacity: usize,
    out_count: *mut usize,
) -> HgStatus {
    ffi_status(|| {
        if out_count.is_null() {
            return Err(HangyeolError::Corrupt);
        }
        let engine = take_engine(engine)?;
        let tables = collect_tables(engine.core.document());
        unsafe {
            *out_count = tables.len();
        }
        if capacity == 0 {
            return Ok(ok());
        }
        if out_tables.is_null() {
            return Err(HangyeolError::Corrupt);
        }
        let n = capacity.min(tables.len());
        for (i, info) in tables.iter().take(n).enumerate() {
            unsafe {
                *out_tables.add(i) = *info;
            }
        }
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_list_images(
    engine: *mut hg_engine,
    out_images: *mut HgImageInfo,
    capacity: usize,
    out_count: *mut usize,
) -> HgStatus {
    ffi_status(|| {
        if out_count.is_null() {
            return Err(HangyeolError::Corrupt);
        }
        let engine = take_engine(engine)?;
        let images = collect_images(engine.core.document());
        unsafe {
            *out_count = images.len();
        }
        if capacity == 0 {
            return Ok(ok());
        }
        if out_images.is_null() {
            return Err(HangyeolError::Corrupt);
        }
        let n = capacity.min(images.len());
        for (i, info) in images.iter().take(n).enumerate() {
            unsafe {
                *out_images.add(i) = *info;
            }
        }
        Ok(ok())
    })
}

#[no_mangle]
pub unsafe extern "C" fn hg_set_cell_text(
    engine: *mut hg_engine,
    table: u32,
    row: u32,
    col: u32,
    text: *const c_char,
) -> HgStatus {
    ffi_status(|| {
        let engine = take_engine(engine)?;
        let text = c_str(text)?;
        set_cell_text(&mut engine.core, table, row, col, text)?;
        Ok(ok())
    })
}

#[no_mangle]
pub extern "C" fn hg_last_error() -> *const c_char {
    last_error_c_str()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    fn hub_a() -> Vec<u8> {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/hub_hwpxlib_SimpleTable.hwpx");
        std::fs::read(path).expect("hub-A")
    }

    fn hub_b() -> Vec<u8> {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/hub_hwpxlib_SimplePicture.hwpx");
        std::fs::read(path).expect("hub-B")
    }

    fn count_linesegarray(hwpx: &[u8]) -> usize {
        let mut archive = zip::ZipArchive::new(std::io::Cursor::new(hwpx)).unwrap();
        let mut total = 0usize;
        for i in 0..archive.len() {
            let mut file = archive.by_index(i).unwrap();
            if !file.name().ends_with(".xml") {
                continue;
            }
            let mut xml = String::new();
            file.read_to_string(&mut xml).unwrap();
            total += xml.matches("hp:linesegarray").count();
        }
        total
    }

    #[test]
    fn unknown_format_is_corrupt_not_unsupported() {
        assert_eq!(
            map_open_format(FileFormat::Unknown),
            Err(HangyeolError::Corrupt)
        );
        assert_eq!(
            map_open_format(FileFormat::Empty),
            Err(HangyeolError::Corrupt)
        );
        assert_eq!(
            map_open_format(FileFormat::Hwp3),
            Err(HangyeolError::UnsupportedVersion)
        );
        assert_eq!(HangyeolError::Encrypted.status(), HgStatus::Password);
        assert_eq!(HangyeolError::SaveRejected.status(), HgStatus::Unsupported);
        assert_eq!(HangyeolError::Corrupt.status(), HgStatus::Corrupt);
    }

    /// Design-only: map password/encrypted open errors → ENCRYPTED / HG_PASSWORD.
    /// Does not commit or read an encrypted fixture.
    #[test]
    fn encrypted_open_message_maps_to_password() {
        let msg = "유효하지 않은 파일: 비밀번호가 필요한 암호 문서입니다 \
                   (parse_document_with_password 또는 parse_hwp_with_password)";
        assert_eq!(map_open_message(msg), HangyeolError::Encrypted);
        assert_eq!(
            map_open_message("EncryptedDocument"),
            HangyeolError::Encrypted
        );
        assert_eq!(HangyeolError::Encrypted.status(), HgStatus::Password);
        assert_eq!(HangyeolError::Encrypted.as_str(), "ENCRYPTED");
    }

    /// Exact verified recipe on DocumentCore (not ZIP/XML edit):
    /// replace_all_native → document_mut sections/paras/table cell paras
    /// `line_segs.clear()` → export_hwpx_native.
    #[test]
    fn document_core_clear_before_save_recipe() {
        let bytes = hub_a();
        assert!(count_linesegarray(&bytes) > 0);

        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-A");
        core.replace_all_native("1", "HGPOC99", true)
            .expect("replace_all_native");

        {
            let document = core.document_mut();
            for section in &mut document.sections {
                for para in &mut section.paragraphs {
                    para.line_segs.clear();
                    for control in &mut para.controls {
                        if let Control::Table(table) = control {
                            for cell in &mut table.cells {
                                for cell_para in &mut cell.paragraphs {
                                    cell_para.line_segs.clear();
                                }
                            }
                        }
                    }
                }
            }
        }

        let exported = core.export_hwpx_native().expect("export_hwpx_native");
        assert_eq!(
            count_linesegarray(&exported),
            0,
            "hp:linesegarray must be 0"
        );

        let reopened = DocumentCore::from_bytes(&exported).expect("reopen");
        let text = collect_plain_text(reopened.document());
        assert!(
            text.contains("HGPOC99"),
            "replacement token must survive export, got {text:?}"
        );
    }

    #[test]
    fn list_tables_and_set_cell_text_on_hub_a() {
        let bytes = hub_a();
        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-A");
        let tables = list_tables(&core);
        assert_eq!(tables.len(), 1, "SimpleTable has one body table");
        assert_eq!(tables[0].index, 0);
        assert_eq!(tables[0].rows, 3);
        assert_eq!(tables[0].cols, 3);

        set_cell_text(&mut core, 0, 0, 0, "HGSET99").expect("set (0,0)");
        // Merged 2×2: grid (0,1) is the same anchor as (0,0).
        let text = collect_plain_text(core.document());
        assert!(
            text.contains("HGSET99"),
            "cell text must update in IR, got {text:?}"
        );
        assert!(
            !text.split('\n').any(|line| line.trim() == "1"),
            "anchor cell '1' should be replaced, got {text:?}"
        );

        let exported = export_hwpx_cleared(&mut core).expect("clear-before-save");
        assert_eq!(count_linesegarray(&exported), 0);
        let reopened = DocumentCore::from_bytes(&exported).expect("reopen");
        let again = collect_plain_text(reopened.document());
        assert!(again.contains("HGSET99"), "got {again:?}");
    }

    fn zip_bindata_entries(hwpx: &[u8]) -> Vec<(String, Vec<u8>)> {
        let mut archive = zip::ZipArchive::new(std::io::Cursor::new(hwpx)).unwrap();
        let mut out = Vec::new();
        for i in 0..archive.len() {
            let mut file = archive.by_index(i).unwrap();
            let name = file.name().to_string();
            if !name.starts_with("BinData/") {
                continue;
            }
            let mut bytes = Vec::new();
            file.read_to_end(&mut bytes).unwrap();
            out.push((name, bytes));
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        out
    }

    #[test]
    fn list_images_on_hub_b() {
        let bytes = hub_b();
        let core = DocumentCore::from_bytes(&bytes).expect("open hub-B");
        let images = list_images(&core);
        assert!(
            !images.is_empty(),
            "SimplePicture / hub-B must list ≥1 picture"
        );
        let img = &images[0];
        assert_eq!(img.index, 0);
        assert!(img.width > 0 && img.height > 0, "size meta {img:?}");
        let fmt = img.format_str();
        assert!(
            matches!(fmt, "jpg" | "jpeg" | "png" | "gif" | "bmp"),
            "format meta {fmt:?}"
        );
        assert!(
            img.bin_data_id > 0 || !img.href_str().is_empty(),
            "Kit addressing needs bin_data_id or href, got {img:?}"
        );
    }

    /// Product gate: hub-B keep-on-save at DocumentCore. Text insert then
    /// clear-before-save must preserve ZIP BinData count/bytes and image meta.
    #[test]
    fn document_core_hub_b_keep_on_save_clear_before_save() {
        let bytes = hub_b();
        let original_bins = zip_bindata_entries(&bytes);
        assert!(!original_bins.is_empty(), "hub-B must contain BinData/");

        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-B");
        let before = list_images(&core);
        assert!(!before.is_empty());

        insert_text(&mut core, 0, 0, 0, "HGIMG99").expect("insert");
        assert!(collect_plain_text(core.document()).contains("HGIMG99"));

        let exported = export_hwpx_cleared(&mut core).expect("clear-before-save");
        assert_eq!(count_linesegarray(&exported), 0, "hp:linesegarray must be 0");

        let saved_bins = zip_bindata_entries(&exported);
        assert_eq!(saved_bins.len(), original_bins.len());
        assert_eq!(saved_bins, original_bins);

        let reopened = DocumentCore::from_bytes(&exported).expect("reopen");
        let after = list_images(&reopened);
        assert_eq!(after.len(), before.len());
        assert_eq!(after[0].width, before[0].width);
        assert_eq!(after[0].height, before[0].height);
        assert_eq!(after[0].format, before[0].format);
        assert_eq!(after[0].bin_data_id, before[0].bin_data_id);
        let again = collect_plain_text(reopened.document());
        assert!(
            again.contains("HGIMG99"),
            "inserted token must survive export, got {again:?}"
        );
    }

    /// Product gate: insert at known (section, para, offset) survives
    /// clear-before-save + reopen. Token is body text, not a ZIP/XML patch.
    #[test]
    fn document_core_insert_text_clear_before_save() {
        let bytes = hub_a();
        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-A");
        insert_text(&mut core, 0, 0, 0, "HGINS99").expect("insert");
        let text = collect_plain_text(core.document());
        assert!(
            text.contains("HGINS99"),
            "inserted token must appear in IR, got {text:?}"
        );

        let exported = export_hwpx_cleared(&mut core).expect("clear-before-save");
        assert_eq!(
            count_linesegarray(&exported),
            0,
            "hp:linesegarray must be 0"
        );

        let reopened = DocumentCore::from_bytes(&exported).expect("reopen");
        let again = collect_plain_text(reopened.document());
        assert!(
            again.contains("HGINS99"),
            "inserted token must survive export, got {again:?}"
        );
    }

    /// Product gate: delete a known body range; absence survives
    /// clear-before-save + reopen.
    #[test]
    fn document_core_delete_range_clear_before_save() {
        let bytes = hub_a();
        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-A");
        insert_text(&mut core, 0, 0, 0, "HGDEL99").expect("seed");
        assert!(collect_plain_text(core.document()).contains("HGDEL99"));

        delete_range(&mut core, 0, 0, 0, 7).expect("delete");
        let text = collect_plain_text(core.document());
        assert!(
            !text.contains("HGDEL99"),
            "deleted token must leave IR, got {text:?}"
        );

        let exported = export_hwpx_cleared(&mut core).expect("clear-before-save");
        assert_eq!(count_linesegarray(&exported), 0);

        let reopened = DocumentCore::from_bytes(&exported).expect("reopen");
        let again = collect_plain_text(reopened.document());
        assert!(
            !again.contains("HGDEL99"),
            "deletion must survive export, got {again:?}"
        );
        assert!(
            again.contains('2') && again.contains('5'),
            "other SimpleTable cells must survive, got {again:?}"
        );
    }

    #[test]
    fn insert_delete_out_of_range_is_corrupt() {
        let bytes = hub_a();
        let mut core = DocumentCore::from_bytes(&bytes).expect("open hub-A");
        assert_eq!(
            insert_text(&mut core, 9, 0, 0, "x"),
            Err(HangyeolError::Corrupt)
        );
        assert_eq!(
            delete_range(&mut core, 0, 99, 0, 1),
            Err(HangyeolError::Corrupt)
        );
        assert_eq!(HangyeolError::Corrupt.as_str(), "CORRUPT");
    }
}
