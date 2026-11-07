#!/bin/bash
# cross-builds probe.dylib and probe2.dylib for Apple Silicon on a Linux machine with clang and lld (no macOS SDK needed)
set -eu
cd "$(dirname "$0")"
for p in probe probe2; do
    clang --target=arm64-apple-macos13 -O2 -fno-stack-protector -ffreestanding -fno-builtin -nostdlib -c $p.c -o $p.o
    ld.lld -flavor darwin -arch arm64 -platform_version macos 13.0 13.0 -dylib -install_name @rpath/$p.dylib \
        -undefined dynamic_lookup -o $p.dylib $p.o
    file $p.dylib 2>/dev/null || true
done
