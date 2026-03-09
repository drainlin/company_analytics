#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${1:-.}"

ANDROID_MANIFEST="$APP_ROOT/android/app/src/main/AndroidManifest.xml"
ANDROID_STRINGS="$APP_ROOT/android/app/src/main/res/values/strings.xml"
ANDROID_FB_CONFIG="$APP_ROOT/android/app/src/main/res/values/facebook_config.xml"
IOS_PLIST="$APP_ROOT/ios/Runner/Info.plist"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILURES=0
WARNINGS=0

ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  FAILURES=$((FAILURES + 1))
}

check_file() {
  local file="$1"
  local label="$2"
  if [[ -f "$file" ]]; then
    ok "$label exists: $file"
  else
    fail "$label missing: $file"
  fi
}

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -q "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label (pattern not found: $pattern)"
  fi
}

echo "Checking Facebook App Events native setup under: $APP_ROOT"

check_file "$ANDROID_MANIFEST" "AndroidManifest.xml"
check_file "$IOS_PLIST" "Info.plist"

echo
ANDROID_VALUES_FILE=""
if [[ -f "$ANDROID_FB_CONFIG" ]]; then
  ANDROID_VALUES_FILE="$ANDROID_FB_CONFIG"
  ok "Android values file exists: $ANDROID_FB_CONFIG"
elif [[ -f "$ANDROID_STRINGS" ]]; then
  ANDROID_VALUES_FILE="$ANDROID_STRINGS"
  ok "Android values file exists: $ANDROID_STRINGS"
else
  fail "Android values file missing: expected one of $ANDROID_FB_CONFIG or $ANDROID_STRINGS"
fi

if [[ -n "$ANDROID_VALUES_FILE" ]]; then
  check_contains "$ANDROID_VALUES_FILE" 'name="facebook_app_id"' 'Android strings: facebook_app_id'
  check_contains "$ANDROID_VALUES_FILE" 'name="facebook_client_token"' 'Android strings: facebook_client_token'
  if grep -q 'name="fb_login_protocol_scheme"' "$ANDROID_VALUES_FILE"; then
    ok 'Android strings: fb_login_protocol_scheme'
  else
    warn 'Android strings: fb_login_protocol_scheme missing (required for login/deep link scenarios)'
  fi
fi

echo
if [[ -f "$ANDROID_MANIFEST" ]]; then
  check_contains "$ANDROID_MANIFEST" 'com.facebook.sdk.ApplicationId' 'Android manifest meta-data: com.facebook.sdk.ApplicationId'
  check_contains "$ANDROID_MANIFEST" 'com.facebook.sdk.ClientToken' 'Android manifest meta-data: com.facebook.sdk.ClientToken'
fi

echo
if [[ -f "$IOS_PLIST" ]]; then
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    if /usr/libexec/PlistBuddy -c "Print :FacebookAppID" "$IOS_PLIST" >/dev/null 2>&1; then
      ok 'iOS plist: FacebookAppID'
    else
      fail 'iOS plist: FacebookAppID missing'
    fi

    if /usr/libexec/PlistBuddy -c "Print :FacebookClientToken" "$IOS_PLIST" >/dev/null 2>&1; then
      ok 'iOS plist: FacebookClientToken'
    else
      fail 'iOS plist: FacebookClientToken missing'
    fi

    if /usr/libexec/PlistBuddy -c "Print :FacebookDisplayName" "$IOS_PLIST" >/dev/null 2>&1; then
      ok 'iOS plist: FacebookDisplayName'
    else
      warn 'iOS plist: FacebookDisplayName missing'
    fi

    if grep -q 'fb[0-9]' "$IOS_PLIST" || grep -q 'fb\$(FACEBOOK_APP_ID)' "$IOS_PLIST"; then
      ok 'iOS plist: fb<APP_ID> URL scheme looks configured'
    else
      fail 'iOS plist: fb<APP_ID> URL scheme missing (CFBundleURLTypes)'
    fi
  else
    warn 'PlistBuddy not found, fallback to text grep only.'
    check_contains "$IOS_PLIST" '<key>FacebookAppID</key>' 'iOS plist: FacebookAppID key'
    check_contains "$IOS_PLIST" '<key>FacebookClientToken</key>' 'iOS plist: FacebookClientToken key'
    if grep -q 'fb[0-9]' "$IOS_PLIST" || grep -q 'fb\$(FACEBOOK_APP_ID)' "$IOS_PLIST"; then
      ok 'iOS plist: fb<APP_ID> URL scheme'
    else
      fail 'iOS plist: fb<APP_ID> URL scheme'
    fi
  fi
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo -e "${RED}Result: FAILED${NC} ($FAILURES failures, $WARNINGS warnings)"
  exit 1
fi

echo -e "${GREEN}Result: PASSED${NC} (0 failures, $WARNINGS warnings)"
