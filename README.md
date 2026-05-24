# dosemu2 AppImage

A single-file [AppImage](https://appimage.org/) of
[dosemu2](https://github.com/dosemu2/dosemu2) — a virtual machine that
runs DOS programs under Linux. Download one file, `chmod +x`, run; no
installation, no PPA, no distro dependencies.

Upstream project: <https://github.com/dosemu2/dosemu2>

## Download

Each release on this repo is tagged with the upstream dosemu2 version
it wraps (e.g. `2.0pre9`). Grab the latest from the
[releases page](../../releases/latest):

```sh
# x86_64 host — substitute the latest version
VERSION=2.0pre9
wget https://github.com/theimpossibleastronaut/dosemu-appimage/releases/download/$VERSION/dosemu2-$VERSION-x86_64.AppImage
chmod +x dosemu2-$VERSION-x86_64.AppImage
./dosemu2-$VERSION-x86_64.AppImage
```

An `aarch64.AppImage` is built next to it for arm64 hosts.

If [appimageupdatetool](https://github.com/AppImageCommunity/AppImageUpdate)
is installed, the AppImage embeds zsync update info and can update
itself in place when a newer release is published:

```sh
appimageupdatetool dosemu2-*.AppImage
```

If your distro doesn't package it, [AM](https://github.com/ivan-hc/AM)
can install it (`am -i appimageupdatetool`).

## Build locally

The same builds the GitHub Actions workflows run can be reproduced on
any host with Docker:

```sh
docker compose run --rm build
```

The finished `.AppImage` lands in `out/`, labelled with whatever
dosemu2 version the PPA currently ships (e.g.
`dosemu2-2.0pre9-x86_64.AppImage`). The build runs inside
`andy5995/linuxdeploy:v3-jammy` and auto-detects host UID/GID from
the bind-mounted workspace owner, so the resulting files are owned by
you. To override the version label or UID/GID, export `VERSION=...`,
`HOSTUID=$(id -u)`, or `HOSTGID=$(id -g)` before running compose.

## How it works

`build-appimage.sh` runs inside the linuxdeploy container and:

1. Adds the upstream [dosemu2 PPA](https://launchpad.net/~dosemu2/+archive/ubuntu/ppa)
   and `apt-get install`s `dosemu2` + `comcom32`.
2. Enumerates every file shipped by the dosemu2 / fdpp / comcom32 /
   comcom64 / dj64 / libdosemu2 debs (via `dpkg -L`) and stages them
   under an `AppDir`.
3. Patches the rpath of `dosemu2.bin` and the bundled plugin `.so`
   files (`$ORIGIN/..`) so dlopens succeed at AppImage-run time without
   needing `LD_LIBRARY_PATH` — exporting that env var would leak the
   AppDir's older libreadline into child shells that dosemu2 spawns.
4. Converts the bundled XPM icon to PNG (appimagetool requires PNG).
5. Runs `linuxdeploy` + `appimagetool` with a custom `AppRun`.

`AppRun` bypasses the PPA's `/usr/bin/dosemu` shell launcher (whose
hardcoded `/usr/...` paths don't survive the AppImage mount) and execs
`dosemu2.bin` directly. It passes `--Flibdir` / `--Fplugindir` pointing
at the mounted AppDir, sets `FDPP_KERNEL_DIR` and `DOSEMU2_COMCOM_DIR`
to redirect the binary's other absolute-path lookups, and translates
launcher-style flags (`-dumb`, `-quiet`, `-home`) to their
`dosemu2.bin` equivalents.

## Limitations

- **Ships comcom32, not comcom64.** comcom64 needs the dj64 runtime,
  whose `libdjstub64.so` hardcodes `/usr/i386-pc-dj64/lib/crt0.elf`
  with no env-var override — that path is unreachable from inside the
  AppImage mount. comcom32 uses plain DPMI and works. The user-visible
  difference is small (both implement `command.com`), but DJGPP-
  compiled DOS programs that depend on the dj64 runtime won't work
  inside this AppImage.
- **Landlock sandbox is disabled at runtime.** The PPA's dosemu2
  (currently 2.0pre9) was built against an older landlock header. On
  kernels exposing landlock ABI 8 the binary logs
  `landlock_init() failed` at startup and continues without the
  sandbox. Functionally fine, just noisier.

## License

MIT — see [LICENSE](LICENSE). Compatible with dosemu2's GPL-2.0-only:
this repo only contains build glue, not dosemu2 source.

The AppImage payload is dosemu2 itself, licensed under GPL-2.0-only,
plus its bundled runtime libraries under their respective licenses
(LGPL, MIT, etc.). The AppImage's `usr/share/doc/` directory carries
linuxdeploy-collected copyright files for each shared library.
