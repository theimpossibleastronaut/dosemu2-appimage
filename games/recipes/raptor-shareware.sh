#!/bin/bash
# Raptor: Call of the Shadows (Cygnus Studios / Apogee, 1994) — vertical
# scrolling space shoot-em-up. Shareware episode under Apogee's standard
# distribution terms (see bundled VENDOR.DOC).

GAME_NAME=Raptor
GAME_TAG=game-raptor-shareware
GAME_DISPLAY="Raptor: Call of the Shadows (Shareware)"
GAME_URL='https://archive.org/download/Raptor-sw1/raptor.zip'
GAME_ARCHIVE=raptor.zip
GAME_EXE=RAP.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - "Everyone can -- and is encouraged! -- to copy, upload and generally pass around this Program without charging for it." (bundled VENDOR.DOC). Copyright (C) 1994 Cygnus Studios, exclusively distributed by Apogee Software.'

# Flatten the raptor/ subdir.
stage() {
  local archive="$1" dest="$2"
  local work
  work=$(mktemp -d)
  unzip -q -o "$archive" -d "$work"
  cp -a "$work/raptor"/. "$dest/"
  rm -rf "$work"
}

source "$(dirname "$0")/../lib/build-game.sh"
