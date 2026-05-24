#!/bin/bash
# Blockage (Ben Hanke, 2003) — tiny 4 KB Breakout/Arkanoid-style game
# for DOS. Released by the author as freeware; see
# https://www.dosgamesarchive.com/download/blockage/

GAME_NAME=Blockage
GAME_TAG=game-blockage
GAME_DISPLAY="Blockage"
GAME_URL='https://archive.org/download/msdos_Blockage_2003/Blockage_2003.zip'
GAME_ARCHIVE=Blockage_2003.zip
GAME_EXE=blockage.com
GAME_CATEGORY=Game
GAME_LICENSE='Freeware - released by the author for free redistribution. Copyright (C) 2003 Ben Hanke.'

# Plain zip; the only DOS files we need are inside Blockage/.
# Flatten so $GAME_EXE sits at the root of $dest.
stage() {
  local archive="$1" dest="$2"
  local work
  work=$(mktemp -d)
  unzip -q -o "$archive" -d "$work"
  install -m 0755 "$work/Blockage"/blockage.com "$dest/blockage.com"
  install -m 0755 "$work/Blockage"/MRESET.COM   "$dest/MRESET.COM"
  rm -rf "$work"
}

source "$(dirname "$0")/../lib/build-game.sh"
