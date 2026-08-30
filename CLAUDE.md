# dosemu2-appimage — project notes

How this repo works, and the decisions behind it that are easy to undo by
accident.

An unofficial AnyLinux AppImage of dosemu2 (sharun + uruntime + DwarFS),
built from a hand-picked upstream commit.

## Build and test locally

```sh
docker run --rm -u 0 -v "$PWD":/workspace -w /workspace \
  -e DOSEMU2_REF=<sha> -e WORKSPACE=/workspace \
  dosemu2-appimage-build-env:<tag> sh -c './build-appimage.sh'
```

`out/` comes back root-owned; append
`; chown -R $(id -u):$(id -g) /workspace/out` inside the `sh -c`.
Smoke test with `./dosemu2-*.AppImage -td -ks -E "ver"`.

**`-dumb` is a `/usr/bin/dosemu` wrapper flag only** — `dosemu2.bin` parses
it as `-l umb` and dies. Use `-td -ks`; `-X` selects the X video plugin.

**Rebuild the build-env before trusting an A/B.** A stale image silently
disables plugins at configure time, so a missing error line proves nothing.
That invalidated one comparison already, and the wrong conclusion reached a
commit message.

To see what a DOS *game* renders without sitting at the keyboard, run
`Xvfb :99` inside the container, launch with `DISPLAY=:99`, drive it with
`xdotool windowfocus --sync` plus `keydown`/`keyup` (SDL ignores keys sent
to an unfocused window, and a tapped key can be missed), and capture with
`import -window`. Take 8–10 frames back to back and compare hashes: a
single screenshot cannot tell a correct frame from one phase of a flicker.

## Releases

Dispatch-only. Pushes build and smoke-test both arches and publish
nothing; Actions → Build dosemu2 AppImage → Run workflow publishes.

Each dispatch writes two releases: the rolling `latest` (one build's
assets, because AM's install script does `head -1` over the asset list)
and a per-commit archive tagged `2.0pre9-dev-g<sha>`.

**The archive tag carries no timestamp**, so rebuilding a commit replaces
that archive in place rather than adding a second release for the same
dosemu2 revision. That is intended: one archived build per commit.

`latest` is updated in place, so GitHub keeps showing its original
creation date. The build timestamp lives in the release *name*.

**AM's updater re-extracts neither the icon nor the `.desktop`** — only
the install script does, so those reach an existing AM user on reinstall.
The binary updates via `appimageupdatetool` zsync if present; without it
AM compares the asset *URL*, so an unchanged filename means no update.

## Design decisions worth keeping

**The bundled soundfont is a fallback, not an override.** PATH_MAPPING
targets `/usr/share/sounds/sf2/FluidR3_GM.sf2`, the **last** entry in
`mid_o_flus.c`'s search list, so a host with its own soundfont keeps it.
Mapping the first entry instead shadowed a reporter's `fluid-soundfont-gm`
(issue #9). For the same reason, do not ship `$_fluid_sfont`: config takes
priority over the whole search list.

**`--sysconfdir=/etc`** is passed at configure time. Autoconf would default
it to `/usr/etc` under `--prefix=/usr`, and dosemu2 would then look for its
global config somewhere no host has (issue #12). dosemu2 reads
`/etc/dosemu/dosemu.conf`, then `~/.dosemurc`; the AppImage ships neither.

**No `DEPLOY_OPENGL`.** Neither SDL plugin calls GL, and SDL3 opens it
lazily rather than as `DT_NEEDED`, so it falls back to software rendering.
Verified in a container with no GL libraries at all. Saves ~8 MB.

## Traps

- **PATH_MAPPING does not reach `dlopen()` of an absolute path.** It
  intercepts `open`/`access`/`stat` only. This is why libao is left out
  entirely — it dlopens `/usr/lib/ao/plugins-4/*` with no env override.
- **alsa-lib's module dir is compiled in and distro-specific**
  (`/usr/lib/alsa-lib` on Arch, `/usr/lib/<triplet>/alsa-lib` on Debian).
  The pulse/pipewire modules are bundled and `ALSA_PLUGIN_DIR` points at
  them, or a host routing through PulseAudio falls back to a busy hw
  device.
- **quick-sharun's path patcher corrupts `libdosemu2.so`.**
  `DOSEMUCMDS_DEFAULT` is a compile-time pointer into the middle of another
  string literal, so a length-preserving rewrite moves what it reads. The
  script disables the patcher and uses PATH_MAPPING instead.
- **fdpp picks its linker by name**, searching `['i686-linux-gnu-ld',
  'i386-elf-ld', 'x86_64-linux-gnu-ld', 'ld.bfd']`. The toolchain builds as
  `i686-unknown-linux-gnu`, which that list misses — harmless on x86_64
  where `ld.bfd` handles `elf_i386`, fatal on aarch64. A symlink fixes it.
- **The `lopsided/archlinux` digest copied from Dealer's Choice is an amd64
  manifest**, not a manifest list, so the arm64 leg built the wrong
  platform. arm64 is `sha256:63c8d3c5…`. DC still carries the bad pin.
- **The SDL plugin is the SDL3 one**, installed as `libplugin_sdl.so`;
  configure prints `sdl3 found, not enabling sdl2`. It needs `sdl3_ttf` and
  `fontconfig` at build time or it silently falls back to the bitmap font,
  and the SDL text mode looks its fonts up by fontconfig *family name* and
  refuses a substitute.
- **X needs two packages**, gated one after the other: `xorg-mkfontscale`,
  then `xorg-bdftopcf`.
- **The build-env image must be republished before a dispatch that depends
  on a Dockerfile change.** `appimage.yml` now builds the image in-job when
  the event's own diff touches the Dockerfile.
- **Toolchain pins are duplicated** between `docker/Dockerfile-appimage`
  and `dosemu2-container`'s `Dockerfile.02-binutils` / `.03-toolchain`.
  Nothing enforces the match.
- **OpenMT32 needs both files, and the sfz is the gate.** `$_omt_sfz_path`
  is what makes the fluidsynth plugin register as MT-32 capable
  (`mt32_scrub`); with only `$_fluid_sfont_mt32` set the soundfont loads
  and the log still says `MIDI: unsupported synth mode mt32`. Neither file
  is bundled — both come from the `stsp/openmt32_sf` release, which has no
  license file. Andy's copies are in `~/.dosemu/openmt32/`.
- **The MT-32 leaves MIDI channel 1 unassigned**, as the hardware does: the
  sfz's `mt32_init_system` maps parts to channels 2-10. A test that plays
  on channel 1 renders silence, and that is correct, not a bug.
- **munt is going away upstream.** stsp said so in discussion #2967 on
  2026-08-30: it is Fedora-only today and he intends to disable it there
  too, with OpenMT32 replacing it. When that lands, the libmt32emu build
  stage in `docker/Dockerfile-appimage` and the four munt references in
  the README (including the `$_munt_roms` section) all become dead.

## Reading dosemu2's source

Several `src/base/dev/vga/` files are **ISO-8859 encoded**, so plain `grep`
treats them as binary and prints nothing — always `grep -a` there. A silent
empty result once led to asserting a field was never assigned when it was
assigned in the obvious place.
