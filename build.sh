#!/bin/bash
# Builds the menu bar binary into build/ (install-root.sh copies it from there).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p build
xcrun swiftc -O -framework Cocoa menubar/main.swift -o build/hostblock-menubar
echo "built build/hostblock-menubar"
