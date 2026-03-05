#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${1:-}"
if [[ -z "$APP_ROOT" ]]; then
  echo "Usage: bash tool/apply_native_templates.sh <flutter_app_root>" >&2
  exit 2
fi

ANDROID_MANIFEST="$APP_ROOT/android/app/src/main/AndroidManifest.xml"
IOS_PLIST="$APP_ROOT/ios/Runner/Info.plist"

if [[ ! -f "$ANDROID_MANIFEST" ]]; then
  echo "Android manifest not found: $ANDROID_MANIFEST" >&2
  exit 1
fi

if [[ ! -f "$IOS_PLIST" ]]; then
  echo "iOS Info.plist not found: $IOS_PLIST" >&2
  exit 1
fi

ensure_android_manifest() {
  local manifest="$1"
  local tmp
  tmp="$(mktemp)"

  # Clean existing Facebook meta-data entries, then inject canonical template entries.
  awk '
    BEGIN { inserted = 0 }
    {
      if ($0 ~ /com\.facebook\.sdk\.ApplicationId/ ||
          $0 ~ /com\.facebook\.sdk\.ClientToken/) {
        next
      }

      print $0

      if (inserted == 0 && $0 ~ /<application[[:space:]>]/) {
        print "        <meta-data android:name=\"com.facebook.sdk.ApplicationId\" android:value=\"@string/facebook_app_id\"/>"
        print "        <meta-data android:name=\"com.facebook.sdk.ClientToken\" android:value=\"@string/facebook_client_token\"/>"
        inserted = 1
      }
    }
  ' "$manifest" > "$tmp"

  mv "$tmp" "$manifest"
  echo "Patched Android manifest (clean + overwrite Facebook meta-data)."
}

plist_set_or_add_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}

cleanup_ios_facebook_url_types() {
  local plist="$1"

  if ! /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$plist" >/dev/null 2>&1; then
    return
  fi

  local count
  count=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$plist" | grep -E '^    Dict \{' | wc -l | tr -d ' ')

  local i
  for ((i = count - 1; i >= 0; i--)); do
    local schemes
    schemes=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$i:CFBundleURLSchemes" "$plist" 2>/dev/null || true)

    # Remove any existing Facebook style URL scheme entries to avoid duplicates / stale IDs.
    if echo "$schemes" | grep -Eq 'fb[0-9]+' || echo "$schemes" | grep -Fq 'fb$(FACEBOOK_APP_ID)'; then
      /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes:$i" "$plist"
    fi
  done
}

ensure_ios_plist() {
  local plist="$1"

  if ! command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    echo "PlistBuddy not found. Cannot auto-template Info.plist." >&2
    exit 1
  fi

  # Always overwrite keys with variable-based template.
  plist_set_or_add_string "$plist" "FacebookAppID" '$(FACEBOOK_APP_ID)'
  plist_set_or_add_string "$plist" "FacebookClientToken" '$(FACEBOOK_CLIENT_TOKEN)'
  plist_set_or_add_string "$plist" "FacebookDisplayName" '$(FACEBOOK_DISPLAY_NAME)'

  cleanup_ios_facebook_url_types "$plist"

  if ! /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$plist"
  fi

  local count
  count=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$plist" | grep -E '^    Dict \{' | wc -l | tr -d ' ')
  local idx="$count"

  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleURLSchemes array" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleURLSchemes:0 string fb\$(FACEBOOK_APP_ID)" "$plist"

  echo "Patched iOS Info.plist (clean + overwrite Facebook keys and URL scheme template)."
}

ensure_android_manifest "$ANDROID_MANIFEST"
ensure_ios_plist "$IOS_PLIST"

echo "Native template apply finished."
