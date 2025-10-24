#!/bin/sh

zig build --release=safe -Dtarget=x86_64-linux-gnu
mkdir -p dist/linux
cp zig-out/bin/shffl dist/linux/shffl

pushd web
pnpm install
rm -r dist
pnpm run build
popd
