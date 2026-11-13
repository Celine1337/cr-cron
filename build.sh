#!/usr/bin/env bash
# Compile cr-cron with Crystal (release build, no debug info).
set -euo pipefail
cd "$(dirname "$0")"
export TC="$HOME/.local/toolchains"
export PATH="$TC/crystal/bin:$PATH"
command -v crystal >/dev/null 2>&1 || { echo "FATAL: crystal not found"; exit 1; }
mkdir -p bin
crystal build src/main.cr -o bin/cr-cron --release --no-debug
echo "built bin/cr-cron"