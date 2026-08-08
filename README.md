# dosemu2 AppImage

A single-file [AppImage](https://appimage.org/) of
[dosemu2](https://github.com/dosemu2/dosemu2), a virtual machine that
runs DOS programs under Linux. Download one file, `chmod +x`, run.

The AppImage carries its own C library and dynamic loader, so it runs on
any Linux distribution: glibc or musl, new or old. This is the
[AnyLinux](https://github.com/pkgforge-dev/Anylinux-AppImages) method
(sharun + uruntime + DwarFS).

Upstream project: <https://github.com/dosemu2/dosemu2>

## Download

Builds are published to a single rolling
[`latest` release](../../releases/latest). The file name carries the
dosemu2 version it was built from.

```sh
chmod +x dosemu2-*.AppImage
./dosemu2-*.AppImage
```

An `aarch64` build sits next to it for arm64 hosts.

If [appimageupdatetool](https://github.com/AppImageCommunity/AppImageUpdate)
is installed, the AppImage can update itself in place:

```sh
appimageupdatetool dosemu2-*.AppImage
```

If your distro does not package it, [AM](https://github.com/ivan-hc/AM)
can install it (`am -i appimageupdatetool`).

## Build locally

You need Docker. First build the build environment, which is Arch plus
dosemu2's toolchain (binutils, thunk_gen, fdpp, smallerc, djstub,
dj64dev, comcom64, libsearpc) compiled from pinned commits:

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

## How it works

`build-appimage.sh` runs inside the build environment and:

1. Clones dosemu2 at `DOSEMU2_REF` and builds it with `--prefix=/usr`,
   installing into the container's own `/usr`.
2. Copies the data dosemu2 looks up by absolute path at runtime into the
   AppDir: fdpp's kernel, comcom64's `command.com`, dj64's `crt0.elf`,
   dosemu2's keymaps and command utilities, the oldschool TTF fonts, and
   the LADSPA plugins.
3. Runs `quick-sharun` over `dosemu2.bin` and every plugin `.so`, which
   collects the full library closure including libc and the loader, then
   packs the result as a DwarFS AppImage.

Two runtime path problems are worth knowing about, because they explain
the odd-looking parts of the script.

dosemu2 and its toolchain bake absolute `/usr/...` paths into their
binaries at compile time, and some of those paths are read on every
launch (dj64's `crt0.elf`) or assembled at runtime from pieces that
never appear as one matchable string. quick-sharun's automatic path
patcher rewrites such strings in place, and on `libdosemu2.so` that
corrupts them: `DOSEMUCMDS_DEFAULT` is a compile-time pointer *into* the
middle of another string literal, so rewriting the literal moves what
the pointer reads. The script therefore disables the automatic patcher
and uses `PATH_MAPPING` instead, an `LD_PRELOAD` interceptor that
redirects the resolved path at runtime.

The SDL text plugin asks fontconfig for the fonts by family name and
refuses a substitute, so the AppImage ships its own fontconfig
configuration pointing at the two bundled fonts.

## Limitations

- **No soundfont.** fluidsynth reports `soundfonts not found` unless one
  is installed on the host. A General MIDI soundfont is over 100 MB,
  which is more than the rest of the AppImage put together.
- **No X11-native video plugin.** dosemu2's `X` plugin needs `mkfontdir`
  at build time. The SDL and Xkmaps plugins cover the same ground.
- **Landlock.** On kernels older than the headers dosemu2 was built
  against, startup logs `landlock_init() failed` and continues without
  the sandbox.

## License

MIT, see [LICENSE](LICENSE). Compatible with dosemu2's GPL-2.0-only:
this repo contains build glue, not dosemu2 source.

The AppImage payload is dosemu2 itself under GPL-2.0-only, plus its
bundled runtime libraries under their own licenses.
