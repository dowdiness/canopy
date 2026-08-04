#!/bin/bash
export PATH="/home/antisatori/.moon/bin:/usr/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT/examples/demo-react"
exec "$PROJECT_ROOT/examples/demo-react/node_modules/.bin/vite"
