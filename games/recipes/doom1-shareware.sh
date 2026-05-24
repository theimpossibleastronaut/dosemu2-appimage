#!/bin/bash
# DOOM (id Software, 1993) - shareware episode 1 ("Knee-Deep in the
# Dead"). Distributed under id's standard shareware terms: the
# shareware episode is freely mirrorable provided files are not
# modified (README.TXT identifies the program as an ASP member;
# HELPME.TXT lists id Software's own ftp distribution mirrors).

GAME_NAME=Doom1Shareware
GAME_TAG=game-doom1-shareware
GAME_DISPLAY="DOOM (Shareware)"
GAME_URL='https://archive.org/download/DoomsharewareEpisode/DoomV1.9sw1995idSoftwareInc.action.zip'
GAME_ARCHIVE=doom1-sw-1.9.zip
GAME_EXE=DOOM.EXE
GAME_CATEGORY=Game
GAME_LICENSE='Shareware - id Software shareware episode 1, freely distributable in unmodified form (per id Software shareware distribution policy and the program''s ASP membership; bundled README.TXT and HELPME.TXT list id Software''s own ftp mirrors). Copyright (C) 1993-1995 id Software, Inc.'

# Zip extracts straight to the destination root.
stage() {
  local archive="$1" dest="$2"
  unzip -q -o "$archive" -d "$dest"
}

source "$(dirname "$0")/../lib/build-game.sh"
