#!/bin/bash
export PATH="/home/antisatori/.moon/bin:/usr/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT/deps/rabbita/examples/SSR"
exec "$PROJECT_ROOT/deps/rabbita/examples/SSR/node_modules/.bin/vite"
