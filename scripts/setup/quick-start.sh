#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"
command -v python3 >/dev/null || { echo "Python 3 is required." >&2; exit 1; }
read -r -p 'Dart app name [my_awesome_app]: ' APP_NAME
read -r -p 'Display name [My Awesome App]: ' APP_DISPLAY_NAME
read -r -p "Android package [com.example.${APP_NAME:-my_awesome_app}]: " PACKAGE_NAME
APP_NAME="${APP_NAME:-my_awesome_app}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-My Awesome App}"
PACKAGE_NAME="${PACKAGE_NAME:-com.example.$APP_NAME}"
printf 'App: %s\nDisplay: %s\nPackage: %s\n' "$APP_NAME" "$APP_DISPLAY_NAME" "$PACKAGE_NAME"
read -r -p 'Proceed? [Y/n]: ' CONFIRM
case "$CONFIRM" in ""|y|Y) ;; *) exit 0 ;; esac
python3 scripts/setup/rename-app.py "$APP_NAME" "$APP_DISPLAY_NAME" "$PACKAGE_NAME"
if command -v flutter >/dev/null; then
    dart format lib test
    flutter pub get
    flutter analyze
    flutter test
else
    echo 'Install Flutter 3.38.7 and run dart format lib test, flutter pub get, flutter analyze, and flutter test.'
fi
