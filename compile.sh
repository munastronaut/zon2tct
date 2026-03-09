#!/bin/bash
set -e

TARGETS=("x86_64-linux" "aarch64-linux" "x86_64-windows" "aarch64-windows" "x86_64-macos" "aarch64-macos")

rm -rf zig-out dist
mkdir -p dist

for TARGET in "${TARGETS[@]}"; do
    zig build -Dtarget="$TARGET" -Doptimize=ReleaseFast

    BIN="zon2tct"
    if [[ "$TARGET" == *"windows"* ]]; then
        BIN="zon2tct.exe"
    fi

    if [[ "$TARGET" == *"windows"* ]]; then
        WIN_OUT="dist/zon2tct-$TARGET.zip"
        (cd zig-out/bin && zip "../../$WIN_OUT" "$BIN")
    fi

    OUT="dist/zon2tct-$TARGET.tar.gz"
    tar -cvzf "$OUT" -C zig-out/bin "$BIN"

    rm -rf zig-out/bin
done
