#!/usr/bin/env bash
# Measure release libhangyeol_engine.a for the §8 renderer spike size table.
#
# Default product path: no extra features (SVG APIs are test-only; this .a is
# the baseline). Optional:
#   --features svg-size-probe          → SVG symbols referenced from the lib
#   --features native-skia             → rhwp Skia/PNG size reference
#
# Host default is the machine triple (Linux CI: x86_64-unknown-linux-gnu).
# Mac aarch64: HANGYEOL_STATICLIB_TARGET=aarch64-apple-darwin on a Mac host.
#
# Does not commit binaries. Does not add hg_render_*.
#
# Linux native-skia: rust-lld may need GCC's libstdc++ directory, e.g.
#   RUSTFLAGS='-C link-arg=-L/usr/lib/gcc/x86_64-linux-gnu/13'
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${HANGYEOL_STATICLIB_PROFILE:-release}"
TARGET="${HANGYEOL_STATICLIB_TARGET:-}"
FEATURES="${HANGYEOL_STATICLIB_FEATURES:-}"
LABEL="${HANGYEOL_STATICLIB_LABEL:-default}"
RUSTC="${HANGYEOL_RUSTC:-1.93.1}"

cd "${ENGINE_DIR}"

target_args=()
if [[ -n "${TARGET}" ]]; then
  target_args+=(--target "${TARGET}")
fi

feature_args=()
if [[ -n "${FEATURES}" ]]; then
  feature_args+=(--features "${FEATURES}")
fi

cargo "+${RUSTC}" rustc --"${PROFILE}" \
  --manifest-path "${ENGINE_DIR}/Cargo.toml" \
  "${target_args[@]}" \
  "${feature_args[@]}" \
  -- --crate-type staticlib

TARGET_DIR="${CARGO_TARGET_DIR:-${ENGINE_DIR}/target}"
if [[ -n "${TARGET}" ]]; then
  REL="${TARGET_DIR}/${TARGET}/${PROFILE}"
else
  REL="${TARGET_DIR}/${PROFILE}"
fi
DEST="${REL}/libhangyeol_engine.a"
DEPS="${REL}/deps"

if [[ ! -f "${DEST}" ]]; then
  SRC=""
  if [[ -f "${DEPS}/libhangyeol_engine.a" ]]; then
    SRC="${DEPS}/libhangyeol_engine.a"
  else
    SRC="$(ls -1t "${DEPS}"/libhangyeol_engine-*.a 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "${SRC}" || ! -f "${SRC}" ]]; then
    echo "no libhangyeol_engine.a under ${REL} or ${DEPS}" >&2
    exit 1
  fi
  cp -f "${SRC}" "${DEST}"
fi

BYTES="$(wc -c < "${DEST}" | tr -d ' ')"
echo "label=${LABEL}"
echo "path=${DEST}"
echo "bytes=${BYTES}"
if command -v nm >/dev/null 2>&1; then
  if nm -g "${DEST}" 2>/dev/null | grep -E ' hg_render_' >/dev/null; then
    echo "hg_render_symbols=PRESENT (FAIL — header/FFI must stay frozen)" >&2
    exit 1
  fi
  echo "hg_render_symbols=absent"
  echo "hg_symbols=$(nm -g "${DEST}" 2>/dev/null | grep -E ' T _?hg_' | sed 's/.* //' | tr '\n' ' ')"
fi
