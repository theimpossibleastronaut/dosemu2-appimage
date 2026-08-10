#!/bin/sh

# Build a truly-portable AppImage of dosemu2 using sharun + uruntime + DwarFS
# (pkgforge-dev's AnyLinux method). It bundles the libc and dynamic linker, so
# the result runs on any Linux distro (musl, very old glibc, ...).
#
# Meant to run inside docker/Dockerfile-appimage's build-env image (Arch base
# + dosemu2's toolchain -- binutils, thunk_gen, fdpp, smallerc, djstub,
# dj64dev, comcom64, libsearpc -- all prebuilt to /usr, see appimage.yml).
# This script clones dosemu2 itself, builds it from source, installs it into
# the system /usr, then bundles the installed binary with quick-sharun.

set -eux

ARCH="$(uname -m)"

# DOSEMU2_REF pins the dosemu2 commit this build is made from. It changes
# only when deliberately passed a new one, never on an upstream push.
DOSEMU2_REF="${DOSEMU2_REF:?DOSEMU2_REF must be set (a dosemu2 commit, branch, or tag)}"

SHARUN="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh"
DEBLOAT_PKGS="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/get-debloated-pkgs.sh"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE="${WORKSPACE:-$SCRIPT_DIR}"
APPDIR="${APPDIR:-/tmp/dosemu2-AppDir}"
OUTPATH="$WORKSPACE/out"

rm -rf "$APPDIR"
mkdir -p "$APPDIR" "$OUTPATH"

# --- clone + build dosemu2, install into the system /usr -------------------
# Full clone, not shallow: getversion needs history for `git describe`,
# or the version falls back to the bare VERSION file. --prefix=/usr is
# what quick-sharun expects to bundle an installed app from.
git clone https://github.com/dosemu2/dosemu2.git /tmp/dosemu2-src
cd /tmp/dosemu2-src
git checkout "$DOSEMU2_REF"
DOSEMU2_COMMIT=$(git rev-parse HEAD)

./autogen.sh
./configure --prefix=/usr
make -j"$(nproc)"
make install

# VERSION is dosemu2's own getversion string, not a release tag -- the
# release always stays tagged "latest" (see UPINFO below).
VERSION=$(./getversion)

# Shortened for the filename: at full length GitHub's release page
# truncates the asset name before the arch, the one part a person picking
# a download needs. The arch goes ahead of the version for the same
# reason. The full VERSION still labels the release itself.
VERSION_SHORT=$(printf '%s\n' "$VERSION" | sed -E 's/-[0-9]{8}-[0-9]+-g/-g/')

# --- bundle with sharun and pack the AppImage ------------------------------
cd "$WORKSPACE"

# The SDL3 plugin renders through OpenGL, so mesa has to be bundled;
# --add-common (implies --add-mesa) supplies pkgforge-dev's nano mesa/LLVM
# and icu stub instead of the stock ones, keeping every gallium driver plus
# the softpipe fallback for hosts with no GPU. pacman -Syu first because
# get-debloated-pkgs resolves its own `pacman -U` deps against the image's
# baked-in DB, and a stale one 404s against already-pruned mirrors.
pacman -Syu --noconfirm
wget --retry-connrefused --tries=30 "$DEBLOAT_PKGS" -O ./get-debloated-pkgs
chmod +x ./get-debloated-pkgs
./get-debloated-pkgs --add-common --prefer-nano

wget --retry-connrefused --tries=30 "$SHARUN" -O ./quick-sharun
chmod +x ./quick-sharun

# Disable quick-sharun's hardcoded-path binary patcher
# (_check_hardcoded_lib_dirs / _check_hardcoded_data_dirs). Its
# length-preserving byte rewrite corrupts libdosemu2.so: DOSEMUCMDS_DEFAULT
# is a compile-time pointer into the middle of another "/usr/share/..."
# literal, so rewriting that literal moves what the pointer reads (observed
# as ".../JRd_j/dosemu/dosemu2-cmds-0.3"). PATH_MAPPING below covers the
# same paths.
sed -i '/^_check_hardcoded_lib_dirs$/d; /^_check_hardcoded_data_dirs$/d' ./quick-sharun
# Same for the later bin-only patch loop: no-op its two _patch_away_*
# calls, leaving the unrelated bun/pyinstaller branch alone.
sed -i \
  -e "s/_patch_away_usr_share_dir \"\$bin\" || :/:/" \
  -e "s/_patch_away_usr_lib_dir \"\$bin\" || :/:/" \
  ./quick-sharun

export APPDIR
export ICON="$WORKSPACE/dosemu.png"
export DESKTOP="$WORKSPACE/dosemu2.desktop"
export OUTPATH
export OUTNAME="dosemu2-$ARCH-$VERSION_SHORT.AppImage"
# dosemu2's SDL3 plugin renders accelerated by default; keep OpenGL in
# the bundle (same reasoning as Dealer's Choice's AnyLinux build).
export DEPLOY_OPENGL=1

# gh-releases-zsync "latest" resolves against whatever GitHub marks as the
# Latest Release, not a fixed tag, and an AppImage bakes this string in for
# good. This repo publishes one rolling release, so "latest" always means
# the current pinned build. The glob needs *$ARCH*: the arch sits in the
# middle of the filename, not at the end.
export UPINFO="gh-releases-zsync|theimpossibleastronaut|dosemu2-appimage|latest|*$ARCH*.AppImage.zsync"

# Data dosemu2 opens by compiled-in /usr/... path at runtime: dj64's
# crt0.elf sysroot, comcom64, fdpp's kernel, and dosemu2's own
# keymaps/codepages/commands. None of it is an ELF, so quick-sharun's
# dependency walk never finds it, and some paths are assembled at runtime
# from DATADIR-style pieces the string patcher cannot match. PATH_MAPPING
# (pkgforge-dev's pathmap, an LD_PRELOAD interceptor) redirects at lookup
# time instead -- but only lookups, so every directory it names still has
# to be copied in by hand below. It does not reach dlopen() of an absolute
# path, which is why libao is left out of the build-env entirely.
DJ64_SYSROOT=/usr/i386-pc-dj64
export PATH_MAPPING="
  $DJ64_SYSROOT:\${SHARUN_DIR}/i386-pc-dj64
  /usr/share/dosemu:\${SHARUN_DIR}/share/dosemu
  /usr/share/comcom64:\${SHARUN_DIR}/share/comcom64
  /usr/share/fdpp:\${SHARUN_DIR}/share/fdpp
  /usr/share/soundfonts:\${SHARUN_DIR}/share/soundfonts
"
mkdir -p "$APPDIR/i386-pc-dj64/lib" "$APPDIR/share/fonts"
cp -v "$DJ64_SYSROOT/lib/crt0.elf" "$APPDIR/i386-pc-dj64/lib/crt0.elf"
cp -av /usr/share/dosemu /usr/share/comcom64 /usr/share/fdpp "$APPDIR/share/"

# SDL text mode looks its two "oldschool" TTF fonts up by fontconfig
# *family name*, not by path, and rejects a substitute -- so an unbundled
# font is a hard failure of the SDL plugin, not a downgrade (see
# sdl_load_font() in src/plugin/sdl3/sdl.c). FONTCONFIG_FILE below points
# at a self-contained config listing only these.
cp -av /usr/share/fonts/oldschool "$APPDIR/share/fonts/oldschool"

# The soundfont the Dockerfile fetches, mapped above so fluidsynth's own
# default path finds it. COPYRIGHT.txt has to travel with it.
if [ -d /usr/share/soundfonts ]; then
  cp -av /usr/share/soundfonts "$APPDIR/share/soundfonts"
fi

# ladspa's filter.so is dlopen()'d through the LADSPA SDK's own loader,
# which searches $LADSPA_PATH (set below). It needs only libc/libm, both
# already loaded by then, so it skips sharun's lib deployment.
cp -av /usr/lib/ladspa "$APPDIR/share/ladspa"

# alsa-lib dlopens its backends from a compiled-in module dir, which is
# Arch's /usr/lib/alsa-lib and exists nowhere else, so on any other host a
# config routed through PulseAudio finds nothing and falls back to a hw
# device the sound server already owns. Bundle the pulse/pipewire modules
# (quick-sharun deploys the rest of the dir alongside them) and point
# ALSA_PLUGIN_DIR at them, set in .env below. Guarded like libao above.
ALSA_MODULES=
for m in conf_pulse pcm_pulse ctl_pulse pcm_pipewire; do
  if [ -e "/usr/lib/alsa-lib/libasound_module_$m.so" ]; then
    ALSA_MODULES="$ALSA_MODULES /usr/lib/alsa-lib/libasound_module_$m.so"
  fi
done

# Deploy dosemu2.bin directly (not the /usr/bin/dosemu shell launcher --
# it only adds convenience flag translation, dosemu2.bin works standalone)
# plus every plugin .so. The plugins are dlopen()'d, not DT_NEEDED, so
# quick-sharun's normal dependency-closure walk wouldn't otherwise find
# them; passing them explicitly is more deterministic in CI than relying
# on quick-sharun's strace-based dlopen discovery (which needs ptrace).
./quick-sharun /usr/libexec/dosemu2/dosemu2.bin /usr/lib/dosemu/libplugin_*.so $ALSA_MODULES

# After the deploy pass, not before: quick-sharun's libfontconfig hook
# drops the build container's fonts.conf here, pointing at the host's
# /usr/share/fonts. prefix="relative" resolves against this file's own
# directory, so it survives being mounted at an unpredictable path.
mkdir -p "$APPDIR/etc/fonts"
cat > "$APPDIR/etc/fonts/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir prefix="relative">../../share/fonts</dir>
  <cachedir prefix="xdg">fontconfig</cachedir>
</fontconfig>
EOF

# sharun expands ${SHARUN_DIR} in .env at launch; it must stay unexpanded
# here (single quotes), same rule as PATH_MAPPING above.
{
  echo 'FONTCONFIG_FILE=${SHARUN_DIR}/etc/fonts/fonts.conf'
  echo 'LADSPA_PATH=${SHARUN_DIR}/share/ladspa'
  echo 'ALSA_PLUGIN_DIR=${SHARUN_DIR}/lib/alsa-lib'
} >> "$APPDIR/.env"

./quick-sharun --make-appimage

ls -lh "$OUTPATH"
echo "Built from dosemu2 commit: $DOSEMU2_COMMIT"
printf '%s\n' "$DOSEMU2_COMMIT" > "$OUTPATH/DOSEMU2_COMMIT"
printf '%s\n' "$VERSION" > "$OUTPATH/DOSEMU2_VERSION"
