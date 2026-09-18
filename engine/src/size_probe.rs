//! Optional linker probes for the §8 `.a` size table.
//!
//! Compiled only with `svg-size-probe` / `native-skia`. Not C ABI — there is
//! no `hg_render_*`. Default product features do not include this module.

use crate::HangyeolError;
use rhwp::document_core::DocumentCore;

/// Reference both hub-A spike SVG APIs so SvgRenderer is kept in the staticlib.
#[cfg(feature = "svg-size-probe")]
pub fn spike_link_svg_page0(core: &DocumentCore) -> Result<(usize, usize), HangyeolError> {
    use rhwp::paint::RenderProfile;
    let legacy = core
        .render_page_svg_native(0)
        .map_err(|_| HangyeolError::Corrupt)?;
    let layer = core
        .render_page_svg_layer_with_profile_native(0, RenderProfile::Screen)
        .map_err(|_| HangyeolError::Corrupt)?;
    Ok((legacy.len(), layer.len()))
}

/// Reference `render_page_png_native` so `native-skia` objects land in the `.a`.
#[cfg(feature = "native-skia")]
pub fn spike_link_png_page0(core: &DocumentCore) -> Result<usize, HangyeolError> {
    let png = core
        .render_page_png_native(0)
        .map_err(|_| HangyeolError::Corrupt)?;
    Ok(png.len())
}
