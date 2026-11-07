#!/usr/bin/env sh
# Builds dist/nimbe.hshader from the repository.
set -eu
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/nimbe.hshader
zip -qrX dist/nimbe.hshader horizon-shaders.toml ./*.wgsl post textures README.md LICENSE
echo "dist/nimbe.hshader"
