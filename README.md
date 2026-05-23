# dosemu2 AppImage

Two AppImages, both produced from this repo:

1. **`dosemu2-<version>-<arch>.AppImage`** —
   [dosemu2](https://github.com/dosemu2/dosemu2) itself, the DOS
   virtual machine. Download, `chmod +x`, run. No PPA, no distro
   deps. Tagged by the upstream version it wraps (e.g. `2.0pre9`).
2. **`mkdexe2-<sha>-<arch>.AppImage`** —
   [mkdexe2](https://github.com/dosemu2/mkdexe2), a tool that wraps
   a DOS program directory into its own runnable AppImage. The
   wrapped game AppImages launch under whatever dosemu2 you have on
   your host (e.g. #1 above symlinked into `~/.local/bin/dosemu`).

Upstream projects:
- dosemu2: <https://github.com/dosemu2/dosemu2>
- mkdexe2: <https://github.com/dosemu2/mkdexe2>

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

## Build locally

The same builds the GitHub Actions workflows run can be reproduced on
any host with Docker:

```sh
docker compose run --rm build           # produces dosemu2-*.AppImage
docker compose run --rm build-mkdexe2   # produces mkdexe2-*.AppImage
```

Finished `.AppImage` files land in `out/`. The dosemu2 build is
labelled with whatever version the PPA currently ships (e.g.
`dosemu2-2.0pre9-x86_64.AppImage`); the mkdexe2 build is labelled
with upstream's git short SHA (e.g. `mkdexe2-git-abcd123-x86_64.AppImage`).
Both run inside `andy5995/linuxdeploy:v3-jammy` and auto-detect host
UID/GID from the bind-mounted workspace owner. Override with
`VERSION=...`, `HOSTUID=$(id -u)`, or `HOSTGID=$(id -g)` before
running compose.

## Using mkdexe2

```sh
# Download the tool AppImage
wget https://github.com/theimpossibleastronaut/dosemu2-appimage/releases/download/mkdexe2-latest/mkdexe2-git-<sha>-x86_64.AppImage
chmod +x mkdexe2-*.AppImage

# Wrap a DOS game directory into its own AppImage
./mkdexe2-*.AppImage -N Wolf3d \
                     -P ~/dos/games/wolf \
                     -E wolf3d.exe
# → org.dosemu2.Wolf3d-x86_64.AppImage in cwd
```

The generated game AppImage assumes dosemu2 is available on `PATH`
(`dosemu` invokable). If you don't have a system dosemu2, the easiest
path is to symlink the dosemu2 AppImage from this same repo:

```sh
ln -sf ~/Downloads/dosemu2-2.0pre9-x86_64.AppImage ~/.local/bin/dosemu
```

mkdexe2 deliberately does not bundle dosemu2 inside game AppImages —
license-wise mixing dosemu2 (GPL-2.0) with arbitrary game payloads is
a redistribution risk, and dosemu2 is meant to live once on a host
and be shared.

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
