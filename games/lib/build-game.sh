#!/bin/bash
# Common harness for game-AppImage recipes in games/recipes/.
#
# A recipe sets these env vars (all required unless noted):
#   GAME_NAME       mkdexe2 -N value, no spaces/hyphens (e.g. "Wolf3DShareware")
#   GAME_TAG        GitHub release tag (e.g. "game-wolf3d-shareware")
#   GAME_DISPLAY    human-readable name for the release title and README
#   GAME_URL        URL of the upstream archive to fetch
#   GAME_ARCHIVE    filename to save the download as (used as cache key too)
#   GAME_EXE        mkdexe2 -E value: entry .exe inside the staged dir
#   GAME_CATEGORY   freedesktop category (default "Game")
#   GAME_LICENSE    short license / redistribution statement included in the
#                   release notes. Required — if a game can't be legally
#                   redistributed, don't add a recipe for it.
#
# Then defines a function:
#   stage()         arg1 = path to downloaded archive
#                   arg2 = empty staging dir to populate with the .WL1 / .EXE
#                   / etc. files mkdexe2 will package
#
# Finally sources this file. We do the rest:
#   1. fetch GAME_URL into a cache dir if not already there
#   2. call stage() to produce the directory mkdexe2 will package
#   3. invoke mkdexe to build the AppImage
#   4. move output to $OUT_DIR with metadata sidecars for the workflow
#
# Driven by games/build-game.sh (host entry point) which selects a recipe
# via GAME=<recipe-name> and runs it inside the linuxdeploy container.

set -eu

# --------------------------------------------------------------------------
# Required from recipe
# --------------------------------------------------------------------------
: "${GAME_NAME:?recipe must set GAME_NAME}"
: "${GAME_TAG:?recipe must set GAME_TAG}"
: "${GAME_DISPLAY:?recipe must set GAME_DISPLAY}"
: "${GAME_URL:?recipe must set GAME_URL}"
: "${GAME_ARCHIVE:?recipe must set GAME_ARCHIVE}"
: "${GAME_EXE:?recipe must set GAME_EXE}"
: "${GAME_LICENSE:?recipe must set GAME_LICENSE — recipes for non-redistributable games are not accepted}"
GAME_CATEGORY="${GAME_CATEGORY:-Game}"

declare -f stage >/dev/null || {
  echo "recipe must define a stage() function (archive_path, dest_dir)" >&2
  exit 1
}

# --------------------------------------------------------------------------
# Environment (set by docker-compose / workflow)
# --------------------------------------------------------------------------
: "${WORKSPACE:?WORKSPACE must be set (repo root, absolute path)}"
[[ "$WORKSPACE" = /* ]] || { echo "WORKSPACE must be absolute"; exit 1; }
test -d "$WORKSPACE"

OUT_DIR="${OUT_DIR:-$WORKSPACE/out}"
CACHE_DIR="${CACHE_DIR:-$WORKSPACE/.game-cache}"
mkdir -p "$OUT_DIR" "$CACHE_DIR"

# --------------------------------------------------------------------------
# 0. install the extraction tools recipes commonly need
# --------------------------------------------------------------------------
# linuxdeploy:v3-jammy doesn't ship these. Cheap to install per run
# (~3s); promote to the helper image if it becomes annoying.
need_install=()
command -v unzip >/dev/null || need_install+=(unzip)
command -v 7z    >/dev/null || need_install+=(p7zip-full)
if [ ${#need_install[@]} -gt 0 ]; then
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends "${need_install[@]}"
fi

# --------------------------------------------------------------------------
# 1. fetch
# --------------------------------------------------------------------------
ARCHIVE_PATH="$CACHE_DIR/$GAME_ARCHIVE"
if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "Fetching $GAME_URL -> $ARCHIVE_PATH"
  curl -fL --retry 3 -o "$ARCHIVE_PATH.tmp" "$GAME_URL"
  mv "$ARCHIVE_PATH.tmp" "$ARCHIVE_PATH"
fi

# --------------------------------------------------------------------------
# 2. stage (recipe-provided)
# --------------------------------------------------------------------------
STAGE_DIR=$(mktemp -d -t "${GAME_NAME}-stage.XXXXXX")
trap 'rm -rf "$STAGE_DIR"' EXIT
echo "Staging $GAME_DISPLAY into $STAGE_DIR"
stage "$ARCHIVE_PATH" "$STAGE_DIR"

# Sanity check: the entry .exe must exist in the staged dir.
if [ ! -r "$STAGE_DIR/$GAME_EXE" ]; then
  echo "stage() did not produce $GAME_EXE in $STAGE_DIR" >&2
  echo "Contents:" >&2
  ls -la "$STAGE_DIR" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# 3. wrap with mkdexe
# --------------------------------------------------------------------------
# Pull mkdexe2 upstream into a working dir; cd into it so its `find AppDir`
# resolves. Build output lands in cwd, then we move it to OUT_DIR.
MKD_DIR=$(mktemp -d -t mkdexe2-src.XXXXXX)
trap 'rm -rf "$STAGE_DIR" "$MKD_DIR"' EXIT
git clone --depth=1 https://github.com/dosemu2/mkdexe2.git "$MKD_DIR"

ARCH=$(uname -m)
APPIMAGE_NAME="org.dosemu2.${GAME_NAME}-${ARCH}.AppImage"

(
  cd "$MKD_DIR"
  # mkdexe upstream caches the appimagetool download under
  # $XDG_RUNTIME_DIR/mkdexe; that variable is empty on GitHub
  # runners, which resolves to "/mkdexe" — not writable as a
  # non-root user. Point it at a writable tmp dir.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d)}"
  # mkdexe downloads appimagetool (itself an AppImage) and invokes
  # it directly. Inside docker (CI) there's no /dev/fuse, so the
  # default FUSE-mount runtime fails. APPIMAGE_EXTRACT_AND_RUN tells
  # any AppImage to unpack into /tmp and exec from there instead.
  export APPIMAGE_EXTRACT_AND_RUN=1
  ./mkdexe -N "$GAME_NAME" -P "$STAGE_DIR" -E "$GAME_EXE" -C "$GAME_CATEGORY"
  mv "$APPIMAGE_NAME" "$OUT_DIR/"
)

# --------------------------------------------------------------------------
# 4. sidecars for the workflow
# --------------------------------------------------------------------------
(
  cd "$OUT_DIR"
  sha256sum "$APPIMAGE_NAME" > "$APPIMAGE_NAME.sha256sum"
)

printf '%s\n' "$GAME_NAME"     > "$OUT_DIR/GAME_NAME"
printf '%s\n' "$GAME_TAG"      > "$OUT_DIR/GAME_TAG"
printf '%s\n' "$GAME_DISPLAY"  > "$OUT_DIR/GAME_DISPLAY"
printf '%s\n' "$GAME_LICENSE"  > "$OUT_DIR/GAME_LICENSE"
printf '%s\n' "$APPIMAGE_NAME" > "$OUT_DIR/GAME_APPIMAGE"

echo "Built $OUT_DIR/$APPIMAGE_NAME"
