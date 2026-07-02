#!/usr/bin/env bash
# download.sh — fetch the latest Claude Desktop .deb and extract it locally.
#
# No root required. Writes to ./deb (the .deb) and ./extract (unpacked tree),
# next to these scripts. Re-run any time to pull a newer version.
#
#   ./download.sh            get + extract latest (skips work if already current)
#   ./download.sh --force    re-download and re-extract even if current
#   ./download.sh --install  after extracting, chain into install.sh (uses sudo)
#   ./download.sh --help
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

FORCE=0; RUN_INSTALL=0
for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --install) RUN_INSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $a (try --help)" ;;
  esac
done

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v ar   >/dev/null 2>&1 || die "'ar' is required (dnf install binutils)"

ARCH="$(deb_arch)"
info "Architecture: $ARCH"

# --- fetch the apt Packages index (plain, falling back to gzip) ------------
fetch_index() {
  local base="$APT_BASE/dists/$APT_DIST/$APT_COMP/binary-$ARCH/Packages"
  curl -fsSL "$base" 2>/dev/null && return 0
  curl -fsSL "$base.gz" | gunzip
}

info "Querying apt pool for the latest version..."
INDEX="$(fetch_index)" || die "could not fetch the package index (check network / VPN)"

# newest stanza -> "version filename sha256"
PARSED="$(
  awk -v want="$PKG_NAME" '
    /^Package:/  { pkg=$2 }
    /^Version:/  { ver=$2 }
    /^Filename:/ { fn=$2 }
    /^SHA256:/   { sha=$2 }
    /^[[:space:]]*$/ { if (pkg==want && ver && fn) print ver" "fn" "sha; pkg=ver=fn=sha="" }
    END           { if (pkg==want && ver && fn) print ver" "fn" "sha }
  ' <<<"$INDEX" | sort -V -k1,1 | tail -1
)"
[[ -n "$PARSED" ]] || die "could not parse a .deb entry from the index"
read -r LATEST_VER REL SHA256 <<<"$PARSED"

DEB_URL="$APT_BASE/$REL"
DEB_FILE="$DEB_DIR/$(basename "$REL")"
info "Latest version: $LATEST_VER"
mkdir -p "$DEB_DIR"

# --- download (unless we already have this exact file, and not --force) ----
if [[ -f "$DEB_FILE" && "$FORCE" -eq 0 ]]; then
  info "Already downloaded: $(basename "$DEB_FILE")"
else
  info "Downloading $(basename "$DEB_FILE") ..."
  curl -fSL --progress-bar -o "$DEB_FILE.part" "$DEB_URL"
  mv -f "$DEB_FILE.part" "$DEB_FILE"
  info "Saved to $DEB_FILE"
fi

# --- verify checksum if the index provided one -----------------------------
if [[ -n "${SHA256:-}" ]]; then
  info "Verifying SHA256..."
  if echo "$SHA256  $DEB_FILE" | sha256sum -c - >/dev/null 2>&1; then
    info "checksum OK"
  else
    die "checksum mismatch — delete $DEB_FILE and retry"
  fi
fi

# --- extract (unless extract/ already matches this version, and not --force)
CURRENT_VER=""
[[ -f "$EXTRACT_DIR/.version" ]] && CURRENT_VER="$(cat "$EXTRACT_DIR/.version")"
if [[ "$CURRENT_VER" == "$LATEST_VER" && "$FORCE" -eq 0 ]]; then
  info "extract/ already at $LATEST_VER — nothing to unpack."
else
  info "Extracting into $EXTRACT_DIR ..."
  extract_deb "$DEB_FILE" "$EXTRACT_DIR" || die "extraction failed"
  printf '%s\n' "$LATEST_VER" > "$EXTRACT_DIR/.version"
  info "Extracted version $LATEST_VER"
fi

# --- keep only the current .deb --------------------------------------------
for old in "$DEB_DIR/${PKG_NAME}_"*.deb; do
  [[ -e "$old" ]] || continue
  [[ "$old" == "$DEB_FILE" ]] && continue
  rm -f "$old" && info "removed old $(basename "$old")"
done

# --- optionally chain into install -----------------------------------------
if [[ "$RUN_INSTALL" -eq 1 ]]; then
  info "Chaining into install.sh ..."
  exec "$SCRIPT_DIR/install.sh"
fi
info "Done. Next: ./install.sh   (or re-run this with --install)"
