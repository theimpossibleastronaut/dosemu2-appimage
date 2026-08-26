# dosemu2 AppImage

An unofficial [AppImage](https://appimage.org/) of
[dosemu2](https://github.com/dosemu2/dosemu2), built from the official
sources. dosemu2 is a virtual machine that runs DOS programs under Linux.
Download one file, `chmod +x`, run.

The AppImage carries its own C library and dynamic loader, so it runs on
any Linux distribution: glibc or musl, new or old. This is the
[AnyLinux](https://github.com/pkgforge-dev/Anylinux-AppImages) method
(sharun + uruntime + DwarFS).

Upstream project: <https://github.com/dosemu2/dosemu2>

## Download

Builds are published to a rolling
[`latest` release](../../releases/latest), which carries one build at a
time, and to a per-commit release that keeps earlier builds reachable.
The file name carries the dosemu2 version it was built from.

```sh
chmod +x dosemu2-*.AppImage
./dosemu2-*.AppImage
```

There is an `aarch64` build for arm64 hosts.

If [appimageupdatetool](https://github.com/AppImageCommunity/AppImageUpdate)
is installed, the AppImage can update itself in place:

```sh
appimageupdatetool dosemu2-*.AppImage
```

If your distribution does not package it, [AM](https://github.com/ivan-hc/AM)
can install it (`am -i appimageupdatetool`).

## Configuration

dosemu2 reads `/etc/dosemu/dosemu.conf` first, then `~/.dosemurc`. The
AppImage ships neither, so it uses whatever is on the host and your
settings survive an update.

## Build locally

You need Docker. First build the build environment — Arch, the bundled
soundfont, and these, each compiled from a pinned commit:

- binutils
- thunk_gen
- fdpp
- smallerc
- djstub
- dj64dev
- comcom64
- libsearpc
- libmt32emu

```sh
docker build -f docker/Dockerfile-appimage -t dosemu2-appimage-build-env .
```

Then build the AppImage. `DOSEMU2_REF` is required and can be any
dosemu2 commit, tag or branch:

```sh
docker run --rm -u 0 -v "$PWD":/workspace -w /workspace \
  -e DOSEMU2_REF=devel -e WORKSPACE=/workspace \
  dosemu2-appimage-build-env sh -c './build-appimage.sh'
```

The finished `.AppImage` lands in `out/`, owned by root because the
build runs as root inside the container. `out/DOSEMU2_COMMIT` records
the exact commit it came from.

## Proposing a newer dosemu2

The `DOSEMU2_REF` file in the repository root holds the dosemu2 commit
the AppImage is built from. To propose a newer one, edit that file and
open a pull request. CI then builds and smoke-tests both architectures
against the commit you put there, and publishes nothing.

Releases stay manual. A maintainer runs the workflow from the Actions
tab with the commit to publish.

## How it works

`build-appimage.sh` runs inside the build environment and:

1. Clones dosemu2 at `DOSEMU2_REF` and builds it with `--prefix=/usr
   --sysconfdir=/etc`, installing into the container's own `/usr`. The
   sysconfdir is what makes it read `/etc/dosemu/dosemu.conf`; autoconf
   would otherwise default it to `/usr/etc`, which exists on no host.
2. Copies the data dosemu2 looks up by absolute path at runtime into the
   AppDir: fdpp's kernel, comcom64's `command.com`, dj64's `crt0.elf`,
   dosemu2's keymaps and command utilities, the oldschool TTF fonts, the
   LADSPA plugins, and the soundfont.
3. Runs `quick-sharun` over `dosemu2.bin`, every plugin `.so`, and
   alsa-lib's PulseAudio and PipeWire modules, which collects the full
   library closure including libc and the loader, then packs the result
   as a DwarFS AppImage.

dosemu2 and its toolchain bake absolute `/usr/...` paths into their
binaries at compile time. quick-sharun rewrites such paths in place, and
on `libdosemu2.so` that corrupts them: `DOSEMUCMDS_DEFAULT` is a
compile-time pointer into the middle of another string literal, so
rewriting the literal moves what the pointer reads. The script disables
that patcher and uses `PATH_MAPPING`, an `LD_PRELOAD` interceptor that
redirects the path at runtime instead.

The SDL text plugin asks fontconfig for the fonts by family name and
refuses a substitute, so the AppImage ships its own fontconfig
configuration pointing at the two bundled fonts.

## What is included

dosemu2 is built with every optional plugin its dependencies allow. That
is the part people find hard to do by hand:

- **DOS:** fdpp, comcom64, dj64
- **Video:** SDL3 with TrueType text, X11, terminal, console
- **Sound:** ALSA with the PulseAudio and PipeWire backends, FluidSynth
  with a bundled soundfont, munt for MT-32, LADSPA
- **Other:** slirp networking, keyboard maps, parallel port

MIDI plays through [GeneralUser
GS](https://github.com/mrbumpy409/GeneralUser-GS), which the AppImage
carries. If your system already has a soundfont, dosemu2 uses that one
instead.

Two things are left out:

- **libao output.** It loads its backends from a fixed path in `/usr`
  that an AppImage cannot supply, so the plugin could only ever report
  `unable to open output device`. ALSA and SDL cover sound output.
- **MT-32 ROMs.** munt is built in, but the ROM files are proprietary.
  dosemu2 looks for them in `~/.munt_roms`; set `$_munt_roms` to use
  another directory.

How much Landlock sandboxing you get depends on the kernel. Below ABI 8,
startup logs `Warning: your kernel is too old, using minimal Landlock
protection` and runs with a reduced sandbox. Below ABI 2, or with no
Landlock at all, it logs `landlock_init() failed` and runs without one.

## License

MIT, see [LICENSE](LICENSE). Compatible with dosemu2's GPL-2.0-only:
this repo contains build glue, not dosemu2 source.

The AppImage payload is dosemu2 itself under GPL-2.0-only, plus its
bundled runtime libraries under their own licenses.
