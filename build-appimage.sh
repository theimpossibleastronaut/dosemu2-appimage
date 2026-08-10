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

# DOSEMU2_REF pins the exact dosemu2 commit/branch/tag this build is made
# from -- set it explicitly (appimage.yml takes it as a workflow_dispatch
# input) for a reproducible build; it only changes when you deliberately
# pass a new one, not automatically on every dosemu2 upstream push.
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
# Full (non-shallow) clone: getversion needs git history reachable so
# `git describe` can produce the rich "2.0pre9-dev-DATE-N-gSHA" version
# string; a shallow clone of just DOSEMU2_REF would make it fall back to
# the bare VERSION file instead. --prefix=/usr (not the autotools default
# /usr/local) matches every AUR PKGBUILD this toolchain is built from and
# is what quick-sharun expects to bundle an installed app from.
git clone https://github.com/dosemu2/dosemu2.git /tmp/dosemu2-src
cd /tmp/dosemu2-src
git checkout "$DOSEMU2_REF"
DOSEMU2_COMMIT=$(git rev-parse HEAD)

./autogen.sh
./configure --prefix=/usr
make -j"$(nproc)"
make install

# VERSION comes from dosemu2's own getversion (the same rich string
# dosemu2-container embeds), not from a release tag -- the GitHub release
# always stays tagged "latest" (see UPINFO below).
VERSION=$(./getversion)

# The filename uses a shortened form: getversion produces
# "2.0pre9-dev-20260806-4883-g604ce0cdd", and at that length GitHub's
# release page truncates the asset name before the arch, which is the
# one part a person picking a download actually needs. Cutting the date
# and commit-count leaves "2.0pre9-dev-g604ce0cdd", and the arch goes
# ahead of it rather than last, so it survives any future growth. The
# full VERSION still labels the release itself.
VERSION_SHORT=$(printf '%s\n' "$VERSION" | sed -E 's/-[0-9]{8}-[0-9]+-g/-g/')

# --- bundle with sharun and pack the AppImage ------------------------------
cd "$WORKSPACE"

# The SDL3 plugin renders through OpenGL, so mesa has to be bundled -- but
# stock Arch mesa brings a 164 MiB libLLVM, a 52 MiB libgallium and a 32 MiB
# libicudata with it. --add-common (which implies --add-mesa) installs
# pkgforge-dev's nano mesa/LLVM and the icu stub over the stock packages,
# and quick-sharun then bundles those instead. mesa-nano keeps every
# hardware gallium driver plus the softpipe software fallback, so a host
# with no GPU still renders.
#
# pacman -Syu first: the build-env image bakes in a package DB, Arch is
# rolling, and get-debloated-pkgs resolves its own `pacman -U` dependencies
# against that DB -- a stale one points at versions the mirrors have already
# pruned, which 404s.
pacman -Syu --noconfirm
wget --retry-connrefused --tries=30 "$DEBLOAT_PKGS" -O ./get-debloated-pkgs
chmod +x ./get-debloated-pkgs
./get-debloated-pkgs --add-common --prefer-nano

wget --retry-connrefused --tries=30 "$SHARUN" -O ./quick-sharun
chmod +x ./quick-sharun

# Disable quick-sharun's automatic hardcoded-/usr/share-or-/usr/lib-path
# binary patcher (_check_hardcoded_lib_dirs / _check_hardcoded_data_dirs).
# It does a length-preserving `sed` substitution directly on compiled
# binaries' raw bytes wherever it detects a literal "/usr/share/..." or
# "/usr/lib/..." match. dosemu2's DOSEMUCMDS_DEFAULT (libdosemu2.so) is
# not its own string -- it's computed at compile time as a POINTER
# `sizeof(PREFIXDIR)` bytes into the *same* underlying "/usr/share/..."
# literal libdosemu2.so also uses verbatim elsewhere (for comcom64's
# default path), so the patcher's in-place byte rewrite of that shared
# literal corrupts what the precomputed offset reads back (observed:
# dosemu2 looking for ".../JRd_j/dosemu/dosemu2-cmds-0.3" instead of
# ".../share/dosemu/dosemu2-cmds-0.3"). PATH_MAPPING above already
# covers every /usr/share path dosemu2 needs redirected, so the
# automatic patcher is both redundant and actively harmful here.
sed -i '/^_check_hardcoded_lib_dirs$/d; /^_check_hardcoded_data_dirs$/d' ./quick-sharun
# Same reasoning for the later bin-only patch loop (it would scan
# dosemu2.bin itself for the same class of match); no-op its two
# _patch_away_* calls but leave the unrelated bun/pyinstaller
# interpreter-patch branch in that same loop alone.
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

# gh-releases-zsync "latest" resolves against whatever GitHub currently
# marks as the Latest Release, regardless of its actual tag name -- not
# a fixed tag. An AppImage bakes this string in at build time and can
# never change it on a copy a user already has. This repo publishes a
# single rolling "latest" release (no separate snapshot/prerelease
# stream), updated only when DOSEMU2_REF is deliberately bumped, so
# "latest" here always means the current pinned build.
# The glob has to be *$ARCH*, not *$ARCH: the arch sits in the middle of
# the filename now, not at the end.
export UPINFO="gh-releases-zsync|theimpossibleastronaut|dosemu2-appimage|latest|*$ARCH*.AppImage.zsync"

# dj64dev's runtime sysroot is where dosemu2's dj64 plugin looks for
# crt0.elf at *every* dj64 program launch (stub.c: open(CRT0, ...), CRT0
# a path baked in at dj64dev's build time -- see docker/Dockerfile-appimage).
# comcom64.exe/command.com (/usr/share/comcom64), fdpp's kernel
# (/usr/share/fdpp), and dosemu2's own keymaps/codepages/command
# utilities (/usr/share/dosemu, including the dosemu2-cmds-* dir
# make install creates) are all real data dosemu2 looks up by compiled-in
# /usr/share/... paths at runtime -- none of it is a library or ELF
# executable, so quick-sharun's normal dependency-closure walk never
# finds it to bundle automatically, and quick-sharun's binary-string
# patcher only catches paths that appear as one complete literal in a
# binary (some of these are assembled at runtime from separate
# DATADIR-style pieces, so they never appear as a single matchable
# string). PATH_MAPPING (an LD_PRELOAD path interceptor from
# pkgforge-dev's pathmap) redirects the actual resolved path at runtime
# regardless of how it was built, which is why it's used here instead of
# relying on the automatic patcher; PATH_MAPPING only redirects lookups
# though, so every directory it covers still has to be bundled by hand.
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

# dosemu2's SDL/SDL3 text mode wants the two "oldschool" TTF fonts it
# installs to $datadir/fonts/oldschool, and looks them up by fontconfig
# *family name* ($_SDL_fonts, default "Flexi IBM VGA False, Flexi IBM VGA
# True") rather than by path -- and it rejects a substitute font, so an
# unbundled font is a hard failure of the SDL text plugin, not a downgrade
# (see sdl_load_font() in src/plugin/sdl3/sdl.c). Bundle the fonts and
# point fontconfig at them with a self-contained config; FONTCONFIG_FILE
# is set below in the AppDir's .env.
cp -av /usr/share/fonts/oldschool "$APPDIR/share/fonts/oldschool"

# The soundfont the Dockerfile fetches, mapped above so fluidsynth's own
# default path finds it. COPYRIGHT.txt has to travel with it.
if [ -d /usr/share/soundfonts ]; then
  cp -av /usr/share/soundfonts "$APPDIR/share/soundfonts"
fi

# ladspa's filter.so is dlopen()'d by dosemu2's sound-effects plugin
# through the LADSPA SDK's own loader, which searches $LADSPA_PATH (set
# below). It needs only libc/libm, both already loaded from sharun's
# bundle by the time anything dlopen()s it, so it doesn't have to go
# through sharun's own lib deployment.
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

# Written after the deploy pass, not before: quick-sharun's own
# libfontconfig post-deploy hook copies the build container's
# /etc/fonts/fonts.conf here, and that one points at the *host's*
# /usr/share/fonts. Replace it with a self-contained config -- prefix=
# "relative" resolves against the directory holding this file, so it
# survives the AppImage being mounted at an unpredictable path. Only the
# bundled fonts are visible to dosemu2 as a result, which is what makes
# the font lookup behave the same on every host.
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
