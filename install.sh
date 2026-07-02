#!/usr/bin/env bash
# install.sh — link the extracted Claude Desktop into place and register it as
# a Fedora GUI app (icon entry in the apps list). Safe to re-run for updates.
#
#   ./install.sh                      setuid chrome-sandbox (default, full isolation)
#   ./install.sh --sandbox namespace  use unprivileged user namespaces instead
#   ./install.sh --sandbox none       disable the sandbox (not recommended)
#   ./install.sh --help
#
# Run ./download.sh first to populate ./extract. Uses sudo for /opt and /usr.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

SANDBOX="setuid"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox)   SANDBOX="${2:-}"; shift 2 ;;
    --sandbox=*) SANDBOX="${1#*=}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done
case "$SANDBOX" in setuid|namespace|none) ;; *) die "invalid --sandbox: $SANDBOX" ;; esac

ensure_root "$@"

[[ -d "$EXTRACT_DIR" ]] || die "no extract/ — run ./download.sh first"
PAYLOAD_DIR="$(detect_payload "$EXTRACT_DIR")" \
  || die "could not find the app payload in extract/ — re-run ./download.sh --force"
ICON_NAME="$(detect_icon_name "$EXTRACT_DIR")"
info "Payload:   $PAYLOAD_DIR"
info "Icon name: $ICON_NAME"

# --- 1) sync payload into /opt ---------------------------------------------
info "Installing payload to $OPT_DIR ..."
if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$OPT_DIR"
  rsync -a --delete "$PAYLOAD_DIR"/ "$OPT_DIR"/
else
  rm -rf "$OPT_DIR"; mkdir -p "$OPT_DIR"
  cp -a "$PAYLOAD_DIR"/. "$OPT_DIR"/
fi

# --- 2) sandbox ------------------------------------------------------------
if [[ "$SANDBOX" == "setuid" ]]; then
  if [[ -e "$OPT_DIR/chrome-sandbox" ]]; then
    chown root:root "$OPT_DIR/chrome-sandbox"
    chmod 4755 "$OPT_DIR/chrome-sandbox"
    info "Configured setuid chrome-sandbox"
  else
    warn "chrome-sandbox not present; falling back to namespace sandbox"
    SANDBOX="namespace"
  fi
fi
case "$SANDBOX" in
  setuid)    FLAG="" ;;
  namespace) FLAG="--disable-setuid-sandbox"
             ns="$(sysctl -n user.max_user_namespaces 2>/dev/null || echo 0)"
             [[ "${ns:-0}" -gt 0 ]] 2>/dev/null \
               || warn "unprivileged user namespaces look disabled (user.max_user_namespaces=$ns); if it won't start, use --sandbox none" ;;
  none)      FLAG="--no-sandbox" ;;
esac

# --- 3) CLI entry ----------------------------------------------------------
mkdir -p "$(dirname "$BIN_LINK")"
if [[ -z "$FLAG" ]]; then
  ln -sfn "$OPT_DIR/claude-desktop" "$BIN_LINK"
  info "Linked $BIN_LINK -> $OPT_DIR/claude-desktop"
else
  cat > "$BIN_LINK" <<EOF
#!/usr/bin/env bash
exec "$OPT_DIR/claude-desktop" $FLAG "\$@"
EOF
  chmod +x "$BIN_LINK"
  info "Wrote CLI wrapper $BIN_LINK ($FLAG)"
fi

# --- 4) icons + pixmaps ----------------------------------------------------
if [[ -d "$EXTRACT_DIR/usr/share/icons" ]]; then
  mkdir -p "$ICON_ROOT"
  cp -a "$EXTRACT_DIR/usr/share/icons/." "$ICON_ROOT"/
  info "Installed icons into $ICON_ROOT"
fi
if [[ -d "$EXTRACT_DIR/usr/share/pixmaps" ]]; then
  mkdir -p "$PIXMAPS_DIR"
  cp -a "$EXTRACT_DIR/usr/share/pixmaps/." "$PIXMAPS_DIR"/
fi

# --- 5) desktop entry (prefer the packaged one, rewrite Exec/Icon) ---------
mkdir -p "$APPS_DIR"
SRC_DESKTOP="$(find "$EXTRACT_DIR/usr/share/applications" -name '*.desktop' 2>/dev/null | head -1 || true)"
EXEC_LINE="Exec=$OPT_DIR/claude-desktop${FLAG:+ $FLAG} %U"
if [[ -n "$SRC_DESKTOP" ]]; then
  cp "$SRC_DESKTOP" "$DESKTOP_FILE"
  sed -i -E "s|^Exec=.*|$EXEC_LINE|"                         "$DESKTOP_FILE"
  sed -i -E "s|^TryExec=.*|TryExec=$OPT_DIR/claude-desktop|" "$DESKTOP_FILE"
  if grep -q '^Icon=' "$DESKTOP_FILE"; then
    sed -i -E "s|^Icon=.*|Icon=$ICON_NAME|" "$DESKTOP_FILE"
  else
    printf 'Icon=%s\n' "$ICON_NAME" >> "$DESKTOP_FILE"
  fi
else
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Claude
GenericName=AI Assistant
Comment=Claude Desktop
Exec=$OPT_DIR/claude-desktop${FLAG:+ $FLAG} %U
TryExec=$OPT_DIR/claude-desktop
Icon=$ICON_NAME
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=Claude
Categories=Utility;Development;Network;
EOF
fi
chmod 644 "$DESKTOP_FILE"
info "Installed launcher $DESKTOP_FILE"

# --- 6) refresh caches -----------------------------------------------------
refresh_desktop_caches
info "Done. Find 'Claude' in your apps list, or run: claude-desktop"
