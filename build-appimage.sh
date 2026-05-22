#!/bin/bash
# Build a dosemu2 AppImage by installing the upstream PPA's `dosemu2` package
# (plus its DOS-side deps) into a build container, staging the installed files
# into an AppDir, and running linuxdeploy + appimagetool over it.
#
# This script is meant to be run inside the andy5995/linuxdeploy:v3-jammy
# container, via the top-level docker-compose.yml.

set -ev

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [ -z "$DOCKER_BUILD" ]; then
  echo "This script is only meant to run inside the linuxdeploy build container."
  echo "See docker-compose.yml."
  exit 1
fi

if [[ "$WORKSPACE" != /* ]]; then
  echo "WORKSPACE must be absolute."
  exit 1
fi
test -d "$WORKSPACE"

APPDIR=${APPDIR:-"/tmp/$USER-AppDir"}
[ -d "$APPDIR" ] && rm -rf "$APPDIR"
mkdir -v -p "$APPDIR"

cd "$WORKSPACE"

# ---------------------------------------------------------------------------
# Install dosemu2 from the upstream Ubuntu PPA
# ---------------------------------------------------------------------------

sudo DEBIAN_FRONTEND=noninteractive sh -c '
  apt-get update && \
  apt-get install -y --no-install-recommends \
      software-properties-common ca-certificates gnupg \
      imagemagick patchelf file && \
  add-apt-repository -y ppa:dosemu2/ppa && \
  apt-get update && \
  apt-get install -y --no-install-recommends dosemu2 comcom32
'

# ---------------------------------------------------------------------------
# Resolve the AppImage version from the installed dosemu2 package
# ---------------------------------------------------------------------------
#
# By default the AppImage label / release tag mirrors the upstream dosemu2
# version we just installed from the PPA — so e.g. "2.0pre9-1ppa9~jammy1"
# becomes "2.0pre9". The full deb version is preserved separately for the
# workflow to surface in release notes. Callers can still set VERSION in
# the env to override (handy for local testing).

DOSEMU2_DEB_VERSION=$(dpkg-query -W -f='${Version}' dosemu2)
# Drop the Debian/PPA suffix ("-10134-a7002fd9f+...") and strip the
# tilde Debian uses for pre-release ordering, so "2.0~pre9-1ppa..."
# becomes "2.0pre9" — matching upstream's tagging convention and
# producing a clean git/release tag.
DOSEMU2_VERSION="${DOSEMU2_DEB_VERSION%%-*}"
DOSEMU2_VERSION="${DOSEMU2_VERSION//\~/}"

if [ -z "$VERSION" ]; then
  VERSION="$DOSEMU2_VERSION"
fi
echo "Building AppImage for dosemu2 $DOSEMU2_DEB_VERSION (label: $VERSION)"

# ---------------------------------------------------------------------------
# Stage dosemu2's installed files into the AppDir
# ---------------------------------------------------------------------------
#
# The dosemu2 deb pulls fdpp, comcom64, dj64dev, and libdosemu2-0 as
# dependencies. Enumerate the file lists of every dosemu2-related package
# and copy them, preserving paths and symlinks. Skip docs/lintian/menu noise
# that bloats the AppImage without doing anything useful.

DOSEMU_PKGS=$(dpkg-query -W -f='${Package}\n' \
  | grep -E '^(dosemu2|libdosemu2|fdpp|comcom32|comcom64|dj64|djdev64)' || true)
if [ -z "$DOSEMU_PKGS" ]; then
  echo "ERROR: no dosemu2 packages installed; PPA install must have failed."
  exit 1
fi
echo "Staging files from: $DOSEMU_PKGS"

for pkg in $DOSEMU_PKGS; do
  dpkg -L "$pkg"
done | sort -u | while read -r path; do
  # Skip directories and anything that isn't a real file or symlink.
  [ -f "$path" ] || [ -L "$path" ] || continue
  case "$path" in
    /usr/share/doc/*|/usr/share/lintian/*|/usr/share/menu/*) continue ;;
  esac
  mkdir -p "$APPDIR$(dirname "$path")"
  cp -P "$path" "$APPDIR$path"
done

# Sanity-check the main binary made it.
DOSEMU_BIN="$APPDIR/usr/libexec/dosemu2/dosemu2.bin"
if [ ! -f "$DOSEMU_BIN" ]; then
  echo "ERROR: $DOSEMU_BIN missing after staging."
  exit 1
fi

# Patch dosemu2.bin's rpath so it finds libdosemu2.so.0.1 (and other bundled
# libs) without us having to export LD_LIBRARY_PATH from AppRun. Exporting it
# leaks the AppDir's bundled libreadline/libtinfo/etc. into child shells
# that dosemu2 spawns, breaking commands like `bash` and `sh` with symbol
# lookup errors. linuxdeploy patches the bundled libraries' rpath but not
# the main executable when it lives in /usr/libexec rather than /usr/bin.
# The relative jumps are two levels deep because libexec/dosemu2/ is three
# directories under usr (usr/libexec/dosemu2/dosemu2.bin → usr/lib/).
patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN/../../lib/x86_64-linux-gnu' \
  "$DOSEMU_BIN"
# Plugin rpath gets fixed AFTER linuxdeploy runs (see below) — linuxdeploy
# relies on the PPA's `/usr/lib/fdpp:...` rpath entries to find libfdpp.so
# during its dependency scan, so we mustn't strip them yet.

# ---------------------------------------------------------------------------
# Desktop file + icon
# ---------------------------------------------------------------------------
#
# The PPA ships /usr/share/applications/dosemu.desktop (already copied above).
# linuxdeploy needs both a desktop file and an icon file. dosemu2 ships an
# XPM icon at /usr/share/dosemu/etc/dosemu.xpm; convert it to PNG for tools
# that don't accept XPM (the appimage spec requires PNG for the embedded
# .DirIcon).

DESKTOP_SRC="$APPDIR/usr/share/applications/dosemu.desktop"
if [ ! -f "$DESKTOP_SRC" ]; then
  echo "WARNING: dosemu.desktop not installed by PPA; writing a fallback."
  mkdir -p "$APPDIR/usr/share/applications"
  cat > "$DESKTOP_SRC" <<EOF
[Desktop Entry]
Name=DOSEMU
Comment=DOS Emulator
Exec=dosemu
Icon=dosemu
Type=Application
Categories=Emulator;System;
Terminal=true
EOF
fi

# The PPA's dosemu.desktop ships Icon=/usr/share/dosemu/icons/dosemu.xpm
# (absolute path), which appimagetool rejects — it wants a bare icon name
# resolvable against the staged hicolor theme. Rewrite to Icon=dosemu.
sed -i 's|^Icon=.*|Icon=dosemu|' "$DESKTOP_SRC"

XPM_ICON=$(find "$APPDIR/usr/share/dosemu" -name '*.xpm' 2>/dev/null | head -1)
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
ICON_FILE="$APPDIR/usr/share/icons/hicolor/256x256/apps/dosemu.png"
if [ -n "$XPM_ICON" ]; then
  # The `!` forces exact dimensions, ignoring aspect ratio — required because
  # appimagetool's icon validation fails if x and y resolution differ.
  convert "$XPM_ICON" -resize '256x256!' "$ICON_FILE"
else
  # Last-resort placeholder: solid square. Without an icon, appimagetool fails.
  convert -size 256x256 xc:'#1a1a1a' \
    -fill white -gravity center -pointsize 96 -annotate +0+0 'DOS' \
    "$ICON_FILE"
fi

# ---------------------------------------------------------------------------
# Run linuxdeploy to bundle shared libs and finalise the AppDir
# ---------------------------------------------------------------------------

OUT_DIR="$WORKSPACE/out"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

export LINUXDEPLOY_OUTPUT_VERSION="$VERSION"

# `--executable` is the binary linuxdeploy scans for shared-lib deps.
# We point it at the real dosemu2.bin (not the /usr/bin/dosemu launcher
# script), so its NEEDED libs — including libdosemu2.so.0.1 — get bundled.
linuxdeploy \
  --appdir "$APPDIR" \
  --executable "$DOSEMU_BIN" \
  --desktop-file "$DESKTOP_SRC" \
  --icon-file "$ICON_FILE" \
  --icon-filename dosemu \
  --custom-apprun "$WORKSPACE/AppRun"

# Fix plugin rpaths now that linuxdeploy has staged libfdpp.so.* / libsearpc.so.*
# into $APPDIR/usr/lib. The PPA-built plugins carry an rpath of
# `/usr/lib/fdpp:.../:$ORIGIN` which doesn't reach the bundled libs at
# $APPDIR/usr/lib (one level above $APPDIR/usr/lib/dosemu where the plugins
# live). Replace with `$ORIGIN/..:$ORIGIN` so dlopen succeeds at AppImage-run
# time. This must happen AFTER linuxdeploy — its dependency scan relies on
# the absolute-path rpath entries to locate libfdpp.so.* in the build env.
for plugin in "$APPDIR/usr/lib/dosemu/"libplugin_*.so; do
  [ -f "$plugin" ] || continue
  patchelf --set-rpath '$ORIGIN/..:$ORIGIN' "$plugin"
done

# ---------------------------------------------------------------------------
# Pack the AppImage with auto-update info pointing at this repo's releases
# ---------------------------------------------------------------------------

ARCH=$(uname -m)
OUT_APPIMAGE="dosemu2-$VERSION-$ARCH.AppImage"

REPO="${GITHUB_REPOSITORY_NAME:-dosemu-appimage}"
GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-theimpossibleastronaut}"
# zsync's update tag follows the release tag — which is just $VERSION now
# that we publish one release per dosemu2 PPA version (no more snapshots).
UPINFO="gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|$REPO|$VERSION|*$ARCH.AppImage.zsync"

appimagetool \
  --comp zstd \
  --mksquashfs-opt -Xcompression-level \
  --mksquashfs-opt 20 \
  -u "$UPINFO" \
  "$APPDIR" "$OUT_APPIMAGE"

sha256sum "$OUT_APPIMAGE" > "$OUT_APPIMAGE.sha256sum"
cat "$OUT_APPIMAGE.sha256sum"

# Emit the resolved dosemu2 version next to the artifacts so the workflow
# can pick it up for the release tag/title without re-querying the PPA.
printf '%s\n' "$VERSION" > "$OUT_DIR/DOSEMU2_VERSION"
printf '%s\n' "$DOSEMU2_DEB_VERSION" > "$OUT_DIR/DOSEMU2_DEB_VERSION"

exit 0
