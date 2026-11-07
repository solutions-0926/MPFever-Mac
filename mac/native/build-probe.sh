#!/bin/bash
# cross-builds probe.dylib for Apple Silicon on a Linux machine with clang and lld (no macOS SDK needed)
set -eu
cd "$(dirname "$0")"
clang --target=arm64-apple-macos13 -O2 -fno-stack-protector -ffreestanding -fno-builtin -nostdlib -c probe.c -o probe.o
ld.lld -flavor darwin -arch arm64 -platform_version macos 13.0 13.0 -dylib -install_name @rpath/probe.dylib \
    -undefined dynamic_lookup -o probe.dylib probe.o
file probe.dylib 2>/dev/null || true
