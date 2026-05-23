# Game AppImages

Pre-wrapped DOS games published as ready-to-run AppImages, built by
the `build-game.yml` workflow and uploaded to per-game GitHub release
tags (e.g. `game-wolf3d-shareware`).

Each game AppImage assumes the host has dosemu2 on PATH (commonly
the dosemu2 AppImage from this same repo, symlinked into
`~/.local/bin/dosemu`). dosemu2 itself is **not** bundled — see the
top-level README and `mkdexe2/AppRun` for why.

## What counts as redistributable

Recipes are only accepted for games that the copyright holder has
explicitly licensed for free redistribution. The bar is real: archive
availability isn't a license, "abandonware" isn't a legal status, and
GitHub honors DMCA takedowns mechanically.

Concretely, **OK**:

- Shareware episodes the publisher released under standard shareware
  terms (Apogee/3D Realms, id Software 1.x shareware)
- Games the original developer has explicitly released as freeware
  (e.g. Bluemoon's Skyroads, 1996 DX-Ball)

**Not OK**:

- Full retail games circulating on abandonware sites
- "Free download" pages that don't include a redistribution grant
- Anything where the rights holder is unknown or unreachable

The `GAME_LICENSE` field in each recipe must spell out the basis for
redistribution. It's reproduced in the release notes so end users can
see the provenance.

## Adding a new game

1. Create `games/recipes/<short-name>.sh` modeled on
   `games/recipes/wolf3d-shareware.sh`. Set `GAME_NAME`, `GAME_TAG`,
   `GAME_DISPLAY`, `GAME_URL`, `GAME_ARCHIVE`, `GAME_EXE`,
   `GAME_LICENSE`. Define a `stage()` function that extracts the
   download into the destination dir so the entry `.exe` is at
   `$dest/$GAME_EXE`.
2. Add the recipe's short name to the `matrix.game` list in
   `.github/workflows/build-game.yml`.
3. Test locally:
   ```
   GAME=<short-name> docker compose run --rm build-game
   ```
   The AppImage lands in `out/`. Launch with the dosemu2 AppImage
   symlinked into `~/.local/bin/dosemu`.
4. Push. The workflow builds an AppImage per `matrix.os` (amd64 +
   arm64) and publishes to the `GAME_TAG` release. The `Latest` badge
   stays on the dosemu2 release (see `appimage.yml`'s `makeLatest:
   true`).

## How a recipe is wired

`games/lib/build-game.sh` is the shared harness:

1. Fetches `$GAME_URL` into `$WORKSPACE/.game-cache/` (cached across
   re-runs).
2. Calls the recipe's `stage()` to populate a tmp dir with the DOS
   files mkdexe2 needs.
3. Clones `dosemu2/mkdexe2` and runs `./mkdexe -N $GAME_NAME -P
   $STAGE_DIR -E $GAME_EXE -C $GAME_CATEGORY` to produce
   `org.dosemu2.$GAME_NAME-$ARCH.AppImage`.
4. Moves the AppImage to `out/` and writes sidecar metadata files
   (`GAME_NAME`, `GAME_TAG`, `GAME_DISPLAY`, `GAME_LICENSE`,
   `GAME_APPIMAGE`) that the workflow reads to build the release.

If `mkdexe2` itself needs patching to ship a recipe (e.g. a new flag
upstream doesn't have), patch upstream first — this repo wraps
mkdexe2, it doesn't fork it.
