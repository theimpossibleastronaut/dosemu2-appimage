#!/bin/bash
# Epic Pinball (Epic MegaGames, 1993) — shareware version, showcases
# the "Android" pinball table. Standard Epic MegaGames shareware
# redistribution terms (bundled LICENSE.DOC: "Epic MegaGames allows
# and encourages all bulletin board systems and online services to
# distribute this game by modem as long as no files are altered or
# removed").

GAME_NAME=EpicPinballAndroid
GAME_TAG=game-epic-pinball-android
GAME_DISPLAY="Epic Pinball - Android (Shareware)"
GAME_URL='https://archive.org/download/epic_pinball_11/epic_pinball.zip'
GAME_ARCHIVE=epic_pinball.zip
GAME_EXE=PINBALL.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - "Epic MegaGames allows and encourages all bulletin board systems and online services to distribute this game by modem as long as no files are altered or removed." (bundled LICENSE.DOC). Copyright (C) 1993 Epic MegaGames / James Schmalz.'

# Zip extracts straight to the destination root.
stage() {
  local archive="$1" dest="$2"
  unzip -q -o "$archive" -d "$dest"
}

source "$(dirname "$0")/../lib/build-game.sh"
