#!/bin/bash
# Build the mkdexe2 AppImage — a tool that wraps DOS games into their
# own runnable AppImages (which themselves invoke a host-installed
# dosemu2 to run the game).
#
# Upstream: https://github.com/dosemu2/mkdexe2
#
# This is a shell-script AppImage; no linuxdeploy library bundling is
# needed — we just stage the upstream `mkdexe` script + its `AppDir/`
# template and let appimagetool pack the result. Still runs inside the
# andy5995/linuxdeploy:v3-jammy container because that's where we
# already have appimagetool + imagemagick available.

set -ev

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [ -z "$DOCKER_BUILD" ]; then
  echo "This script is only meant to run inside the linuxdeploy build container."
  exit 1
fi
if [[ "$WORKSPACE" != /* ]]; then
  echo "WORKSPACE must be absolute."
  exit 1
fi
test -d "$WORKSPACE"

APPDIR=${APPDIR:-"/tmp/$USER-mkdexe2-AppDir"}
[ -d "$APPDIR" ] && rm -rf "$APPDIR"
mkdir -v -p "$APPDIR"

cd "$WORKSPACE"

# ---------------------------------------------------------------------------
# Pull upstream mkdexe2
# ---------------------------------------------------------------------------

rm -rf /tmp/mkdexe2-src
git clone --depth=1 https://github.com/dosemu2/mkdexe2.git /tmp/mkdexe2-src

# Version label = upstream short SHA unless overridden.
MKDEXE2_SHA=$(cd /tmp/mkdexe2-src && git rev-parse --short HEAD)
if [ -z "$VERSION" ]; then
  VERSION="git-${MKDEXE2_SHA}"
fi
echo "Building mkdexe2 AppImage from upstream ${MKDEXE2_SHA} (label: ${VERSION})"

# ---------------------------------------------------------------------------
# Stage the AppDir
# ---------------------------------------------------------------------------

mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/mkdexe2"

# The mkdexe script itself.
install -m 0755 /tmp/mkdexe2-src/mkdexe "$APPDIR/usr/bin/mkdexe"

# The AppDir template mkdexe consumes (it expects an `AppDir/` dir in
# the cwd it's invoked from). Our AppRun symlinks this into a tmp
# working dir before exec'ing mkdexe.
cp -a /tmp/mkdexe2-src/AppDir "$APPDIR/usr/share/mkdexe2/AppDir"

# Desktop file.
mkdir -p "$APPDIR/usr/share/applications"
cat > "$APPDIR/usr/share/applications/mkdexe2.desktop" <<'EOF'
[Desktop Entry]
Name=mkdexe2
Comment=Wrap a DOS program directory into an AppImage that runs under dosemu2
Exec=mkdexe
Icon=mkdexe2
Type=Application
Categories=Development;Utility;
Terminal=true
EOF

# Icon — mkdexe2 only ships an SVG; the builder image has neither
# librsvg (for SVG rasterization) nor system fonts (for text in IM),
# so we generate a plain colored square. appimagetool strictly
# requires *some* PNG; aesthetics aren't on the path.
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
ICON_FILE="$APPDIR/usr/share/icons/hicolor/256x256/apps/mkdexe2.png"
convert -size 256x256 xc:'#3a6cba' "$ICON_FILE"

# AppRun — execs mkdexe with the AppDir template wired into a tmp cwd.
install -m 0755 "$WORKSPACE/mkdexe2/AppRun" "$APPDIR/AppRun"

# Top-level icon + desktop, as appimagetool expects.
cp "$ICON_FILE" "$APPDIR/mkdexe2.png"
cp "$APPDIR/usr/share/applications/mkdexe2.desktop" "$APPDIR/mkdexe2.desktop"

# ---------------------------------------------------------------------------
# Pack with appimagetool
# ---------------------------------------------------------------------------

ARCH=$(uname -m)
OUT_DIR="$WORKSPACE/out"
mkdir -p "$OUT_DIR"
OUT_APPIMAGE="$OUT_DIR/mkdexe2-${VERSION}-${ARCH}.AppImage"

REPO="${GITHUB_REPOSITORY##*/}"
REPO="${REPO:-dosemu2-appimage}"
GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-theimpossibleastronaut}"
UPINFO="gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|$REPO|mkdexe2-latest|mkdexe2-*${ARCH}.AppImage.zsync"

appimagetool \
  --comp zstd \
  --mksquashfs-opt -Xcompression-level \
  --mksquashfs-opt 20 \
  -u "$UPINFO" \
  "$APPDIR" "$OUT_APPIMAGE"

sha256sum "$OUT_APPIMAGE" > "${OUT_APPIMAGE}.sha256sum"
cat "${OUT_APPIMAGE}.sha256sum"

printf '%s\n' "${VERSION}"     > "$OUT_DIR/MKDEXE2_VERSION"
printf '%s\n' "${MKDEXE2_SHA}" > "$OUT_DIR/MKDEXE2_SHA"

exit 0
