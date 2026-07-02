#!/usr/bin/env bash
# shellcheck disable=SC2034  # config vars below are consumed by the scripts that source this file
# lib.sh — shared config + helpers for the Claude Desktop (Fedora) scripts.
#
# Sourced by download.sh, install.sh, and uninstall.sh. Not meant to be run
# on its own. All paths resolve relative to this file's location, so the
# scripts work from any working directory.
#
# Overridable via environment (mostly for testing / non-standard setups):
#   CLAUDE_DESKTOP_ROOT  where deb/ and extract/ live      (default: this dir)
#   OPT_DIR              app payload install path           (/opt/claude-desktop)
#   BIN_LINK             CLI entry                          (/usr/local/bin/claude-desktop)
#   APPS_DIR             .desktop launcher dir              (/usr/share/applications)
#   ICON_ROOT            icon theme root                    (/usr/share/icons)
#   PIXMAPS_DIR          legacy pixmaps dir                 (/usr/share/pixmaps)

# ---- resolve paths relative to this library's location --------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_DESKTOP_ROOT:-$LIB_DIR}"
DEB_DIR="$ROOT/deb"
EXTRACT_DIR="$ROOT/extract"

# ---- system install targets (env-overridable) -----------------------------
OPT_DIR="${OPT_DIR:-/opt/claude-desktop}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-desktop}"
APPS_DIR="${APPS_DIR:-/usr/share/applications}"
ICON_ROOT="${ICON_ROOT:-/usr/share/icons}"
PIXMAPS_DIR="${PIXMAPS_DIR:-/usr/share/pixmaps}"
DESKTOP_FILE="$APPS_DIR/claude-desktop.desktop"

# ---- upstream apt pool ----------------------------------------------------
APT_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
APT_DIST="stable"
APT_COMP="main"
PKG_NAME="claude-desktop"

# ---- invoking user (captured before any sudo re-exec) ---------------------
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[[ -n "$REAL_HOME" ]] || REAL_HOME="$HOME"

# ---- logging --------------------------------------------------------------
if [[ -t 2 ]]; then
  _c_teal=$'\033[38;5;37m'; _c_warn=$'\033[33m'; _c_err=$'\033[31m'; _c_off=$'\033[0m'
else
  _c_teal=""; _c_warn=""; _c_err=""; _c_off=""
fi
info() { printf '%s>>%s %s\n' "$_c_teal" "$_c_off" "$*" >&2; }
warn() { printf '%swarn:%s %s\n' "$_c_warn" "$_c_off" "$*" >&2; }
err()  { printf '%serror:%s %s\n' "$_c_err" "$_c_off" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- helpers --------------------------------------------------------------

# map `uname -m` to the Debian arch string used in the apt pool
deb_arch() {
  case "$(uname -m)" in
    x86_64)  echo amd64 ;;
    aarch64) echo arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

# re-exec the calling script under sudo when not already root
# usage: ensure_root "$@"
ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -- "$0" "$@"
  fi
}

# print the app payload dir inside an extracted tree (the dir holding the
# main binary + electron resources). Prefers the dir containing chrome-sandbox.
detect_payload() {
  local root="$1" p
  p="$(find "$root" -type f -name chrome-sandbox 2>/dev/null | head -1)"
  [[ -n "$p" ]] && { dirname "$p"; return 0; }
  p="$(find "$root" -type f -name "$PKG_NAME" 2>/dev/null | grep -v '/bin/' | head -1)"
  [[ -n "$p" ]] && { dirname "$p"; return 0; }
  return 1
}

# print the themed icon base name shipped in an extracted tree
detect_icon_name() {
  local root="$1" f
  f="$(find "$root/usr/share/icons" "$root/usr/share/pixmaps" -type f \
        \( -name '*.png' -o -name '*.svg' \) 2>/dev/null | head -1)"
  if [[ -n "$f" ]]; then f="$(basename "$f")"; printf '%s\n' "${f%.*}"; else printf '%s\n' "$PKG_NAME"; fi
}

# unpack a .deb's data tree into $2 (handles zstd / xz / gz)
extract_deb() {
  local deb="$1" dest="$2" tmp data
  [[ -f "$deb" ]] || { err "no such .deb: $deb"; return 1; }
  deb="$(readlink -f -- "$deb")"   # absolute: we cd into a tmp dir below
  rm -rf "$dest"; mkdir -p "$dest"
  tmp="$(mktemp -d)"
  ( cd "$tmp" && ar x "$deb" ) || { rm -rf "$tmp"; return 1; }
  data="$(find "$tmp" -maxdepth 1 -name 'data.tar.*' | head -1)"
  [[ -n "$data" ]] || { err "no data.tar.* inside $deb"; rm -rf "$tmp"; return 1; }
  case "$data" in
    *.zst)
      if tar --help 2>/dev/null | grep -q -- '--zstd'; then
        tar --zstd -xf "$data" -C "$dest"
      elif command -v unzstd >/dev/null 2>&1; then
        unzstd -c "$data" | tar -x -C "$dest"
      else
        rm -rf "$tmp"; err "need zstd support (dnf install zstd) to unpack $data"; return 1
      fi ;;
    *) tar -xf "$data" -C "$dest" ;;   # xz / gz autodetected by GNU tar
  esac
  rm -rf "$tmp"
}

# rebuild GNOME's desktop + icon caches so entries appear/disappear at once
refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f "$ICON_ROOT/hicolor" >/dev/null 2>&1 || true
  fi
}
