#!/usr/bin/env bash

set -euo pipefail

moon update
cd event-graph-walker && moon update
cd ../loom/loom && moon update
cd ../../svg-dsl && moon update
cd ../graphviz && moon update
