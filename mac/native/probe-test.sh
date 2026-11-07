#!/bin/bash
# MPFever macOS probes: starts the Mac build of Transport Fever 3 with a probe module of ours inserted, and writes
# ~/Desktop/mpfever-<probe>-result.txt. Nothing in the game's folder is changed.
#
#   bash probe-test.sh probe  [game folder]    step 1: is the module loaded?
#   bash probe-test.sh probe2 [game folder]    step 2: patch the Lua seed, hook the command function (load a savegame when asked)
#
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-probe}"
G="${2:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
DYL="$HERE/$NAME.dylib"
OUT="$HOME/Desktop/mpfever-$NAME-result.txt"
if [ "$NAME" = probe ]; then LOGF="$HOME/mpfever-probe.log"; else LOGF="$HOME/mpfever-$NAME.log"; fi
[ -x "$G/TransportFever3" ] || { echo "TransportFever3 not found in: $G"; exit 1; }
[ -f "$DYL" ] || { echo "$NAME.dylib is not next to this script"; exit 1; }
rm -f "$LOGF"
# what came from the internet is blocked by macOS until the mark is removed; Apple Silicon wants code signed (ad hoc is enough)
xattr -c "$DYL" 2>/dev/null
codesign --force --sign - "$DYL" 2>&1 | tail -1
pkill -x TransportFever3 2>/dev/null
pgrep -x steam_osx >/dev/null 2>&1 || { echo "Starting Steam..."; open -g -a Steam; sleep 15; }
echo "Starting the game with the module..."
( cd "$G" && DYLD_INSERT_LIBRARIES="$DYL" ./TransportFever3 > "$HOME/mpfever-$NAME-game.txt" 2>&1 ) &
for i in $(seq 1 40); do [ -s "$LOGF" ] && break; sleep 1; done
if [ "$NAME" != probe ]; then
    echo
    echo "The game is starting. When its main menu is there: load any savegame (or start a new game), let it run about 10 seconds,"
    echo "then come back to this window and press Enter."
    read -r _
else
    sleep 3
fi
ALIVE=no; pgrep -x TransportFever3 >/dev/null 2>&1 && ALIVE=yes
{
    echo "== macOS"; sw_vers; uname -m
    echo "== module log"; cat "$LOGF" 2>&1
    echo "== game process still running: $ALIVE"
    echo "== game output (first 40 lines)"; head -40 "$HOME/mpfever-$NAME-game.txt" 2>&1
    echo "== crash reports of the last 15 minutes"; find "$HOME/Library/Logs/DiagnosticReports" -name 'TransportFever3*' -mmin -15 2>/dev/null
} > "$OUT" 2>&1
pkill -x TransportFever3 2>/dev/null
echo "Done. Result: $OUT"
[ -s "$LOGF" ] && echo "The module WAS loaded by the game." || echo "The module was NOT loaded: see the result file."
