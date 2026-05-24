#!/bin/bash
# AM's Mini Golf 3D (Andrew McNab / A.L. McNab, 1996) — shareware
# 3D mini-golf. The bundled LICENSE.TXT grants free redistribution
# of the unmodified shareware version.

GAME_NAME=MiniGolf3D
GAME_TAG=game-mgolf3d
GAME_DISPLAY="AM's Mini Golf 3D (Shareware)"
GAME_URL='https://archive.org/download/msdos_AMs_Mini_Golf_3D_1996/AMs_Mini_Golf_3D_1996.zip'
GAME_ARCHIVE=AMs_Mini_Golf_3D_1996.zip
GAME_EXE=MG3D.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - "You may freely distribute this shareware version of the game as long it stays in it''s origional, complete and unmodified form." (bundled LICENSE.TXT). Copyright (C) 1996 Andrew McNab.'

# Plain zip, files under AMsMiniG/. Flatten so MG3D.EXE sits at the root.
stage() {
  local archive="$1" dest="$2"
  local work
  work=$(mktemp -d)
  unzip -q -o "$archive" -d "$work"
  cp -a "$work/AMsMiniG"/. "$dest/"
  rm -rf "$work"
}

source "$(dirname "$0")/../lib/build-game.sh"
