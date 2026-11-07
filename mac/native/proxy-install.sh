#!/bin/bash
# MPFever macOS: puts the module in as a stand-in for the game's audio library (libalut.0.dylib) so that the game loads it by itself,
# however it is started (from Steam too). The game's own library stays next to it as libalut.0.real.dylib and everything is passed
# on to it; a pristine copy of the original is kept as libalut.0.dylib.mpfever-orig. Steam's "Verify integrity of game files"
# puts the game back as it was.
#
#   bash proxy-install.sh install   [game folder]
#   bash proxy-install.sh uninstall [game folder]
#   bash proxy-install.sh status    [game folder]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-status}"
G="${2:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
PROXY="$HERE/${MPF_PROXY:-libalut.0.proxy.dylib}"
die() { echo "proxy-install: $*" >&2; exit 1; }
[ -x "$G/TransportFever3" ] || die "TransportFever3 not found in: $G"
ORIG="$G/libalut.0.dylib"; REAL="$G/libalut.0.real.dylib"; KEEP="$G/libalut.0.dylib.mpfever-orig"

is_proxy() { grep -aq "MPFever probe" "$1" 2>/dev/null; }

case "$CMD" in
  install)
    [ -f "$PROXY" ] || die "libalut.0.proxy.dylib is not next to this script"
    pgrep -x TransportFever3 >/dev/null 2>&1 && die "close Transport Fever 3 first"
    [ -f "$ORIG" ] || die "the game's libalut.0.dylib is missing: verify the game's files in Steam"
    if is_proxy "$ORIG"; then
        [ -f "$KEEP" ] || die "the module is already in, but the original copy is missing: verify the game's files in Steam, then install again"
        echo "The module is already in; updating it."
    else
        cp "$ORIG" "$KEEP" || die "cannot copy the original"
    fi
    # the real library, under its new name (its own name inside is changed too, so the game does not mix it up with the stand-in)
    cp "$KEEP" "$REAL" || die "cannot write $REAL"
    install_name_tool -id "@loader_path/libalut.0.real.dylib" "$REAL" || die "install_name_tool failed (install the Command Line Tools: xcode-select --install)"
    codesign --force --sign - "$REAL" 2>&1 | tail -1
    cp "$PROXY" "$ORIG" || die "cannot write $ORIG"
    chmod 755 "$ORIG" "$REAL"
    xattr -c "$ORIG" 2>/dev/null
    codesign --force --sign - "$ORIG" 2>&1 | tail -1
    echo "Installed. Start Transport Fever 3 from Steam as usual; the module's log is ~/mpfever-probe3.log."
    ;;
  uninstall)
    [ -f "$KEEP" ] || die "no original copy found ($KEEP): use Steam's 'Verify integrity of game files'"
    cp "$KEEP" "$ORIG" && rm -f "$REAL" "$KEEP" && echo "The game's own libalut.0.dylib is back."
    ;;
  status)
    if is_proxy "$ORIG"; then echo "installed (the module stands in for libalut.0.dylib)"; else echo "not installed"; fi
    ls -la "$G"/libalut.0* 2>&1
    ;;
  *) die "install, uninstall or status" ;;
esac
