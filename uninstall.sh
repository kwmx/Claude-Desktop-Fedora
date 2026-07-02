#!/usr/bin/env bash
# uninstall.sh — undo install.sh and remove everything download.sh fetched.
#
#   ./uninstall.sh              remove system install + local deb/ and extract/
#   ./uninstall.sh --keep-local remove the system install only, keep deb/extract
#   ./uninstall.sh --purge      also delete THIS user's app data (config/cache/
#                               share) + claude:// mimeapps association
#   ./uninstall.sh --help
#
# Uses sudo for /opt and /usr. Does not touch the scripts themselves.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

PURGE=0; KEEP_LOCAL=0
for a in "$@"; do
  case "$a" in
    --purge)      PURGE=1 ;;
    --keep-local) KEEP_LOCAL=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) die "unknown option: $a (try --help)" ;;
  esac
done

ensure_root "$@"

info "Removing Claude Desktop system files"
declare -a ICON_NAMES=()

# 1) launcher(s) whose Exec points at our /opt payload (grab Icon= name first)
if [[ -d "$APPS_DIR" ]]; then
  while IFS= read -r -d '' df; do
    n="$(awk -F= '/^Icon=/{print $2; exit}' "$df" 2>/dev/null || true)"
    [[ -n "$n" ]] && ICON_NAMES+=("$n")
    rm -f -- "$df"; info "removed $df"
  done < <(grep -rlZ -- "$OPT_DIR" "$APPS_DIR" 2>/dev/null || true)
fi

# 2) CLI entry (symlink or wrapper) + the /opt payload
for p in "$BIN_LINK" "$OPT_DIR"; do
  if [[ -e "$p" || -L "$p" ]]; then rm -rf -- "$p"; info "removed $p"; fi
done

# 3) icons + pixmaps, by captured Icon name(s) plus the conventional fallback
ICON_NAMES+=("$PKG_NAME")
mapfile -t ICON_NAMES < <(printf '%s\n' "${ICON_NAMES[@]}" | awk 'NF && !seen[$0]++')
for name in "${ICON_NAMES[@]}"; do
  if [[ -d "$ICON_ROOT/hicolor" ]]; then
    while IFS= read -r -d '' f; do rm -f -- "$f"; info "removed $f"; done \
      < <(find "$ICON_ROOT/hicolor" -type f -name "$name.*" -print0 2>/dev/null || true)
  fi
  if [[ -d "$PIXMAPS_DIR" ]]; then
    while IFS= read -r -d '' f; do rm -f -- "$f"; info "removed $f"; done \
      < <(find "$PIXMAPS_DIR" -maxdepth 1 -type f -name "$name.*" -print0 2>/dev/null || true)
  fi
done

refresh_desktop_caches

# 4) local download/extract artifacts
if [[ "$KEEP_LOCAL" -eq 0 ]]; then
  for d in "$EXTRACT_DIR" "$DEB_DIR"; do
    if [[ -d "$d" ]]; then rm -rf -- "$d"; info "removed $d"; fi
  done
else
  info "kept local deb/ and extract/ (--keep-local)"
fi

# 5) optional per-user data
if [[ "$PURGE" -eq 1 ]]; then
  info "--purge: removing per-user data for $REAL_USER"
  for d in \
    "$REAL_HOME/.config/Claude"       "$REAL_HOME/.config/claude-desktop" \
    "$REAL_HOME/.cache/Claude"        "$REAL_HOME/.cache/claude-desktop" \
    "$REAL_HOME/.local/share/Claude"  "$REAL_HOME/.local/share/claude-desktop"; do
    if [[ -e "$d" ]]; then rm -rf -- "$d"; info "removed $d"; fi
  done
  # strip the claude:// scheme-handler association the app may have written into
  # the user's mimeapps.list (rewrite in place to preserve owner/permissions).
  for m in \
    "$REAL_HOME/.config/mimeapps.list" \
    "$REAL_HOME/.local/share/applications/mimeapps.list"; do
    [[ -f "$m" ]] || continue
    grep -q 'claude-desktop\.desktop' "$m" 2>/dev/null || continue
    tmp="$(mktemp)"
    grep -v 'claude-desktop\.desktop' "$m" > "$tmp" || true
    cat "$tmp" > "$m"   # truncate-write keeps the original inode's owner/mode
    rm -f "$tmp"
    info "cleaned claude scheme handler from $m"
  done
fi

info "Done — Claude Desktop uninstalled."
[[ "$PURGE" -eq 0 ]] && info "(Per-user settings kept; use --purge to remove them.)"
