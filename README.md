# dosemu2 in Docker

Run [dosemu2](https://github.com/dosemu2/dosemu2) — a virtual machine
that runs DOS programs under Linux — inside a container, without
installing it on your host. When you start the container, dosemu2 boots
and drops you into a DOS shell right in your terminal.

Upstream project: <https://github.com/dosemu2/dosemu2>

Two image variants are provided:

| File | What it does | Build time |
| --- | --- | --- |
| `Dockerfile` | Ubuntu 24.04 + the official [dosemu2 PPA](https://code.launchpad.net/~dosemu2/+archive/ubuntu/ppa). Installs the latest released dosemu2 binary. | Fast |
| `Dockerfile.git` | Arch Linux. Clones dosemu2 from GitHub and builds it from source against SDL3. Pick any branch, tag, or commit. Build helpers that aren't in the official Arch repos (`libsearpc`, `fdpp`, `dj64-git`, `comcom64-git` and their transitive AUR deps) are resolved and built by [`paru`](https://aur.archlinux.org/packages/paru) in a builder stage. Two-stage build keeps the runtime image lean — make-only deps (DJGPP toolchain etc.) stay behind in the builder layer. | Slow (compiles dosemu2 *and* the full AUR dep graph) |

Both produce a runnable `dosemu2` image with the same interface.

## What you need

* Docker Engine (the `docker` command). On Linux: `sudo apt install docker.io`
  or follow the [official install guide](https://docs.docker.com/engine/install/).
  On macOS / Windows: install Docker Desktop.
* Optional: the `docker compose` plugin (bundled with Docker Desktop, available
  as `docker-compose-plugin` on Debian/Ubuntu).

Verify Docker works before continuing:

```sh
docker run --rm hello-world
```

If that prints "Hello from Docker!" you're good.

## Quick start (compose)

From this `docker/` folder:

```sh
cp .env.example .env        # optional — only if you want to change defaults
docker compose build
docker compose run --rm dosemu2
```

`run --rm` (not `up`) is what you want — it attaches your terminal so you can
actually type into DOS, and removes the container when you exit. Type `exitemu`
inside DOS (or press `Ctrl-Alt-PgDn`) to quit.

To build from upstream git instead of the PPA, edit `.env`:

```ini
DOSEMU_VARIANT=git
DOSEMU2_REF=devel
```

…then `docker compose build` again. The image is tagged `dosemu2:git`
(vs. `dosemu2:ppa` for the default), so the two variants don't overwrite
each other. See [Configuration via `.env`](#configuration-via-env) below
for the full list of variables.

## Quick start (plain `docker`)

If you'd rather not use compose, build and run the image directly.

PPA build:

```sh
docker build -t dosemu2 .
```

Git build (pass a ref to pin a branch / tag / commit):

```sh
docker build -f Dockerfile.git -t dosemu2:git --build-arg DOSEMU2_REF=devel .
```

Run it:

```sh
docker run --rm -it dosemu2
```

What the flags mean:

* `--rm` — delete the container when you exit (the image stays).
* `-it` — interactive + TTY. dosemu2 is a terminal program, so both are
  required; without them you'll see no prompt.

Anything after the image name is passed straight to `dosemu`, e.g.:

```sh
docker run --rm -it dosemu2 -E dir
docker run --rm -it dosemu2 -dumb -E "echo hello"
```

See `man dosemu` (or `dosemu --help` inside the container) for the full
option list.

### Keep your DOS files between runs

Without a volume, anything you do in DOS vanishes when the container exits.
Mount a host directory onto `/home/dosuser/.dosemu` to persist the C: drive,
config and logs:

```sh
mkdir -p ~/dosemu-home
docker run --rm -it -v ~/dosemu-home:/home/dosuser/.dosemu dosemu2
```

The files dosemu2 normally puts in `~/.dosemu` on a host install (including
`drive_c/`) will now live in `~/dosemu-home` on your machine. Drop DOS
programs into `~/dosemu-home/drive_c/` and they'll show up on `C:` inside DOS.

With compose this is controlled by the `DOSEMU_HOME` variable in `.env`.

## Configuration via `.env`

`docker compose` automatically reads a file called `.env` in the same folder
as `docker-compose.yml`. Copy `.env.example` to `.env` to get started:

```sh
cp .env.example .env
```

Every variable has a default, so the file is optional. The available knobs:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DOSEMU_VARIANT` | _(empty)_ | Empty = `Dockerfile` (Ubuntu PPA, image `dosemu2:ppa`). Set to `git` for `Dockerfile.git` (Arch + upstream git, image `dosemu2:git`). One variable selects both the Dockerfile and the image tag. |
| `DOSEMU2_REF` | `devel` | Git branch / tag / commit to build (only used when `DOSEMU_VARIANT=git`). |
| `DOSEMU2_REPO` | `https://github.com/dosemu2/dosemu2.git` | Repo to clone — point at a fork to build your own changes. |
| `DOSEMU_IMAGE` | _(derived from `DOSEMU_VARIANT`)_ | Set this to override the full image name, e.g. `myregistry.example.com/dosemu2:latest` for pushing to a registry. |
| `DOSEMU_CONTAINER` | `dosemu2` | Container name. |
| `DOSEMU_HOME` | `dosemu-home` | Source of the volume mounted at `/home/dosuser/.dosemu`. Leave as the default for a docker-managed named volume, or set to a host path like `./dosemu-home` to use a bind mount instead. |

After changing build-time variables (`DOSEMU_VARIANT`, `DOSEMU2_REF`,
`DOSEMU2_REPO`, `DOSEMU_IMAGE`) run `docker compose build` again. Runtime
variables (`DOSEMU_HOME`, `DOSEMU_CONTAINER`) take effect on the next
`docker compose run`.

### Passing extra dosemu options through compose

`docker compose run` forwards trailing arguments to the image's entrypoint,
so the same args you'd pass to `dosemu` work here too:

```sh
docker compose run --rm dosemu2 -E dir
docker compose run --rm dosemu2 -dumb -E "echo hello"
```

## Common issues

* **"the input device is not a TTY"** — you forgot `-it` on `docker run`,
  or you used `docker compose up` instead of `docker compose run`.
* **Garbled characters / wrong colors** — your host terminal needs to
  support 256 colors. Try a different terminal emulator, or pass
  `-e TERM=xterm` to `docker run`.
* **No sound, no graphics** — these images run dosemu2 in terminal video
  mode only. SDL/X11 graphics and audio would need extra host wiring
  (X socket forwarding, PulseAudio, `/dev/snd`) and aren't set up here.
* **Permission errors on a bind-mounted host folder** — the container
  user has UID 1000. If your host user has a different UID, either
  `chown -R 1000:1000 ~/dosemu-home` or rebuild the image after editing
  the `useradd` line in the Dockerfile to match your UID.
* **`Dockerfile.git` build fails on `make`** — check that `DOSEMU2_REF`
  points at a buildable commit. The `devel` branch occasionally breaks;
  pinning to a release tag (e.g. `DOSEMU2_REF=2.0pre10`) is a safer
  bet for reproducible builds.
* **`Dockerfile.git` build fails inside the `paru -S` step** — AUR
  packages are user-maintained and can break independently of dosemu2.
  Check the failing package's page on
  [aur.archlinux.org](https://aur.archlinux.org/) for recent comments.
  To pin to a working snapshot of a specific helper, replace `paru -S`
  with a `git clone https://aur.archlinux.org/<pkg>.git#commit=<sha>`
  + manual `makepkg` for that package, then let `paru` handle the rest.

## Cleaning up

```sh
docker rmi dosemu2                     # remove the image
docker compose down -v                 # stop + remove compose volumes
```
