#!/bin/sh
set -e

# Install MoonBit CLI
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version --all

# Install MoonBit package dependencies for each module
cd ..
git submodule update --init --recursive
moon update
cd graphviz && moon update && cd ..

cd web

# Build with Vite
npx vite build
