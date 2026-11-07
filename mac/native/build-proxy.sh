#!/bin/bash
# Builds libalut.0.proxy.dylib: probe3's code as a stand-in for the game's libalut.0.dylib (the audio library the game loads at
# start). It re-exports everything of the real library, which proxy-install.sh keeps next to it as libalut.0.real.dylib.
# Needs the game's own libalut.0.dylib (only to read its symbol list; it is not copied into the result).
#
#   bash build-proxy.sh <path to the game's libalut.0.dylib>
set -eu
cd "$(dirname "$0")"
ORIG="${1:?give the path of the libalut.0.dylib of the game}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
python3 -I - "$ORIG" "$T/libalut.0.real.dylib" <<'PY'
import sys, lief
fat = lief.MachO.parse(sys.argv[1]); b = fat.at(0)
for c in b.commands:
    if c.command.name == "ID_DYLIB":
        c.name = "@loader_path/libalut.0.real.dylib"
fat.write(sys.argv[2])
PY
clang --target=arm64-apple-macos13 -O2 -fno-stack-protector -ffreestanding -fno-builtin -nostdlib -c probe3.c -o "$T/probe3.o"
ld.lld -flavor darwin -arch arm64 -platform_version macos 13.0 13.0 -dylib -install_name @rpath/libalut.0.dylib \
    -undefined dynamic_lookup -reexport_library "$T/libalut.0.real.dylib" -o libalut.0.proxy.dylib "$T/probe3.o"
file libalut.0.proxy.dylib
