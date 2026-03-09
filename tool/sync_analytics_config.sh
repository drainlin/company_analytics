#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_ROOT=""
CONFIG_PATH=""
INIT_TEMPLATE="false"

usage() {
  cat <<USAGE
Usage:
  bash tool/sync_analytics_config.sh --app-root <flutter_app_root> [--config <yaml_path>] [--init-template]

Example:
  bash tool/sync_analytics_config.sh \
    --app-root /path/to/your_flutter_app \
    --config /path/to/your_flutter_app/config/company_analytics.yaml

Init template only:
  bash tool/sync_analytics_config.sh --app-root /path/to/your_flutter_app --init-template
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
    --init-template)
      INIT_TEMPLATE="true"
      shift
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

if [[ "$INIT_TEMPLATE" == "true" ]]; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  if [[ -f "$CONFIG_PATH" ]]; then
    echo "Template already exists: $CONFIG_PATH"
  else
    cp "$PACKAGE_ROOT/config/analytics.sample.yaml" "$CONFIG_PATH"
    echo "Created template: $CONFIG_PATH"
  fi
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH" >&2
  echo "Run with --init-template first, then fill keys." >&2
  exit 2
fi

cd "$PACKAGE_ROOT"
dart run tool/sync_analytics_config.dart --app-root "$APP_ROOT" --config "$CONFIG_PATH"
