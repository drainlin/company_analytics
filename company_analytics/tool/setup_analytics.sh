#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_ROOT=""
CONFIG_PATH=""

usage() {
  cat <<USAGE
Usage:
  bash tool/setup_analytics.sh --app-root <flutter_app_root> [--config <yaml_path>]

Default config path:
  <app-root>/config/company_analytics.yaml

Example:
  bash tool/setup_analytics.sh --app-root .
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      APP_ROOT="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$APP_ROOT" ]]; then
  echo "--app-root is required." >&2
  usage
  exit 2
fi

if [[ -z "$CONFIG_PATH" ]]; then
  CONFIG_PATH="$APP_ROOT/config/company_analytics.yaml"
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cp "$PACKAGE_ROOT/config/analytics.sample.yaml" "$CONFIG_PATH"
  echo "Created config template: $CONFIG_PATH"
  echo "Please fill real keys in that file, then re-run the same command."
  exit 2
fi

if rg -n "YOUR_|123456789012345" "$CONFIG_PATH" >/dev/null 2>&1; then
  echo "Config file still contains placeholder values: $CONFIG_PATH" >&2
  echo "Please fill real keys, then re-run." >&2
  exit 2
fi

echo "[1/3] Applying native template..."
bash "$PACKAGE_ROOT/tool/apply_native_templates.sh" "$APP_ROOT"

echo "[2/3] Syncing analytics config..."
bash "$PACKAGE_ROOT/tool/sync_analytics_config.sh" --app-root "$APP_ROOT" --config "$CONFIG_PATH"

echo "[3/3] Verifying native setup..."
bash "$PACKAGE_ROOT/tool/check_facebook_setup.sh" "$APP_ROOT"

echo "All done. Native template + analytics config sync + verification passed."
