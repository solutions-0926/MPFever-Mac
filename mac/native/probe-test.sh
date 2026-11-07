#!/bin/bash
# MPFever macOS, step 1: does Transport Fever 3 (the Mac build) load a module of ours?
# Starts the game's TransportFever3 file with probe.dylib inserted, waits for the module's log, closes the game, and writes
# ~/Desktop/mpfever-probe-result.txt. It changes nothing in the game's folder. Close Transport Fever 3 first; Steam can be open.
#
#   bash probe-test.sh [folder of the game]
#
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${1:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
DYL="$HERE/probe.dylib"
OUT="$HOME/Desktop/mpfever-probe-result.txt"
LOGF="$HOME/mpfever-probe.log"
[ -x "$G/TransportFever3" ] || { echo "TransportFever3 not found in: $G"; exit 1; }
[ -f "$DYL" ] || { echo "probe.dylib is not next to this script"; exit 1; }
rm -f "$LOGF"
# what came from the internet is blocked by macOS until the mark is removed; Apple Silicon wants code signed (ad hoc is enough)
xattr -c "$DYL" 2>/dev/null
codesign --force --sign - "$DYL" 2>&1 | tail -1
pkill -x TransportFever3 2>/dev/null
# Steam is needed by the game: start it when it is not running
pgrep -x steam_osx >/dev/null 2>&1 || { echo "Starting Steam..."; open -g -a Steam; sleep 15; }
echo "Starting the game with the module (a game window may open; it is closed by this script)..."
( cd "$G" && DYLD_INSERT_LIBRARIES="$DYL" ./TransportFever3 > "$HOME/mpfever-probe-game.txt" 2>&1 ) &
for i in $(seq 1 40); do [ -s "$LOGF" ] && break; sleep 1; done
sleep 3
ALIVE=no; pgrep -x TransportFever3 >/dev/null 2>&1 && ALIVE=yes
{
    echo "== macOS"; sw_vers; uname -m
    echo "== module log"; cat "$LOGF" 2>&1
    echo "== game process still running after the wait: $ALIVE"
    echo "== game output (first 40 lines)"; head -40 "$HOME/mpfever-probe-game.txt" 2>&1
    echo "== codesign of the module"; codesign -dvv "$DYL" 2>&1 | head -8
} > "$OUT" 2>&1
pkill -x TransportFever3 2>/dev/null
echo "Done. Result: $OUT"
[ -s "$LOGF" ] && echo "The module WAS loaded by the game." || echo "The module was NOT loaded: see the result file."
