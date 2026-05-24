#!/bin/bash
# Floatris (DATA WAVE / Loyd L. Towe, 1993) — Tetris-style falling-
# (or rather, rising-) blocks game. Bundled LEGAL.DOC grants free
# non-commercial redistribution.

GAME_NAME=Floatris
GAME_TAG=game-floatris
GAME_DISPLAY="Floatris"
GAME_URL='https://archive.org/download/msdos_Floatris_1993/Floatris_1993.zip'
GAME_ARCHIVE=Floatris_1993.zip
GAME_EXE=FLOATRIS.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - "You may distribute this program by giving it to friends, placing it on electronic bulletin board systems, etc., so long as it is not for profit." (bundled LEGAL.DOC). Copyright (C) 1993 DATA WAVE / Loyd L. Towe.'

# Plain zip, files under floatris/. Flatten.
stage() {
  local archive="$1" dest="$2"
  local work
  work=$(mktemp -d)
  unzip -q -o "$archive" -d "$work"
  cp -a "$work/floatris"/. "$dest/"
  rm -rf "$work"
}

source "$(dirname "$0")/../lib/build-game.sh"
