#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${1:-8765}"

echo "Serving analytics remote config from: $PACKAGE_ROOT/config"
echo "iOS simulator / desktop URL: http://127.0.0.1:$PORT/analytics.remote.dev.json"
echo "Android emulator URL:        http://10.0.2.2:$PORT/analytics.remote.dev.json"

python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$PACKAGE_ROOT/config"
