#!/bin/bash
# Host entry point invoked inside the linuxdeploy container by the
# docker-compose `build-game` service or the build-game.yml workflow.
#
# Usage:
#   GAME=wolf3d-shareware ./games/build-game.sh
#
# Selects the matching recipe at games/recipes/$GAME.sh and runs it.
# The recipe sources games/lib/build-game.sh which handles fetch,
# stage, mkdexe wrap, and writing sidecar metadata to $OUT_DIR.

set -eu

[ -n "${DOCKER_BUILD:-}" ] || {
  echo "This script is only meant to run inside the linuxdeploy build container." >&2
  exit 1
}
: "${GAME:?GAME=<recipe> required (see games/recipes/)}"
: "${WORKSPACE:?WORKSPACE must be set}"

RECIPE="$WORKSPACE/games/recipes/$GAME.sh"
[ -f "$RECIPE" ] || {
  echo "No such recipe: $RECIPE" >&2
  echo "Available:" >&2
  ls "$WORKSPACE/games/recipes/" >&2
  exit 1
}

exec bash "$RECIPE"
