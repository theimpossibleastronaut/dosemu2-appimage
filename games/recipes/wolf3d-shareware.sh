#!/bin/bash
# Wolfenstein 3-D shareware episode 1 (id Software / Apogee, 1992).
#
# Apogee's standard shareware license: free to redistribute provided
# files are not modified and no fee is charged.

GAME_NAME=Wolf3DShareware
GAME_TAG=game-wolf3d-shareware
GAME_DISPLAY="Wolfenstein 3-D (Shareware)"
GAME_URL='https://archive.org/download/1-wolf-14/%231WOLF14.ZIP'
GAME_ARCHIVE=1wolf14.zip
GAME_EXE=W3D-E1.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - free to redistribute provided files are unmodified and no fee is charged. Copyright (C) 1992 id Software, distributed by Apogee Software Productions.'

# The 1WOLF14.ZIP distribution is a thin wrapper: the actual game files
# live inside WOLF1.1, which is an ARJ self-extracting .EXE (despite the
# .1 extension). 7z handles ARJ.
stage() {
  local archive="$1" dest="$2"
  local work
  work=$(mktemp -d)
  unzip -q -o "$archive" -d "$work"
  ( cd "$work" && 7z x -y WOLF1.1 >/dev/null )
  install -m 0644 "$work"/*.WL1 "$dest/"
  install -m 0755 "$work/W3D-E1.EXE" "$dest/"
  rm -rf "$work"
}

source "$(dirname "$0")/../lib/build-game.sh"
