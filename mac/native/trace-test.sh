#!/bin/bash
# MPFever macOS, step 4: which functions of the game does one action call? Installs the tracing module (probe 4) in place of the game's
# audio library, guides you through three marks (nothing / one road piece), collects the log, and puts the game back as it was.
#
#   bash trace-test.sh [game folder]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${1:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
LOGF="$HOME/mpfever-probe4.log"
MARK="$HOME/mpf-mark"
OUTDIR="$HERE"
[ -f "$HERE/libalut.0.probe4.dylib" ] || { echo "libalut.0.probe4.dylib is not next to this script"; exit 1; }
pgrep -x TransportFever3 >/dev/null 2>&1 && { echo "Close Transport Fever 3 first."; exit 1; }
rm -f "$LOGF" "$MARK"
MPF_PROXY=libalut.0.probe4.dylib bash "$HERE/proxy-install.sh" install "$G" || exit 1
echo
echo "1. Start Transport Fever 3 from STEAM now (the Play button)."
echo "2. Load a savegame and wait until you see the map with things moving. Do not pause."
echo "Then come back here and press Enter."
read -r _ < /dev/tty
if [ ! -s "$LOGF" ]; then echo "The module did not start (no log). Putting the game back."; bash "$HERE/proxy-install.sh" uninstall "$G"; exit 1; fi
touch "$MARK"; sleep 1
echo "Mark 1 set. Now do NOTHING for 12 seconds (just look at the map)..."
sleep 12
touch "$MARK"; sleep 1
echo
echo "Mark 2 set. Now build exactly ONE short piece of road (one click, a few metres), wait 3 seconds,"
echo "then press Enter here."
read -r _ < /dev/tty
touch "$MARK"; sleep 2
echo
echo "Mark 3 set. Now quit the game (menu > Quit) and press Enter here."
read -r _ < /dev/tty
pkill -x TransportFever3 2>/dev/null; sleep 2
cp "$LOGF" "$OUTDIR/mpfever-probe4-result.txt" 2>/dev/null
bash "$HERE/proxy-install.sh" uninstall "$G"
echo
echo "Done. Send me the file: $OUTDIR/mpfever-probe4-result.txt"
open -R "$OUTDIR/mpfever-probe4-result.txt" 2>/dev/null
