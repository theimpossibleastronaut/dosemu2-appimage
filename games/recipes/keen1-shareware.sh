#!/bin/bash
# Commander Keen Episode 1: Marooned on Mars (Apogee, 1990).
# Apogee's standard shareware license: free to redistribute provided
# files are not modified and no fee is charged.

GAME_NAME=Keen1Shareware
GAME_TAG=game-keen1-shareware
GAME_DISPLAY="Commander Keen 1: Marooned on Mars (Shareware)"
GAME_URL='https://archive.org/download/keen1-sw/keen1.zip'
GAME_ARCHIVE=keen1.zip
GAME_EXE=KEEN1.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - free to redistribute provided files are unmodified and no fee is charged. Copyright (C) 1990 Apogee Software Productions / id Software.'

# Plain zip — no DEICE/ARJ wrapper to peel.
stage() {
  local archive="$1" dest="$2"
  unzip -q -o "$archive" -d "$dest"
}

source "$(dirname "$0")/../lib/build-game.sh"
