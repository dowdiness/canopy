#!/bin/bash
export PATH="/home/antisatori/.moon/bin:/usr/bin:$PATH"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT/apps/ideal/web"
exec "$PROJECT_ROOT/apps/ideal/web/node_modules/.bin/vite"
