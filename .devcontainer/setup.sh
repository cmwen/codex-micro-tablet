#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_version=$(cat .flutter-version)
flutter_dir=/home/vscode/flutter
if [[ ! -d "$flutter_dir/.git" ]]; then
  git clone https://github.com/flutter/flutter.git --branch "$flutter_version" --depth 1 "$flutter_dir"
fi
export PATH="$flutter_dir/bin:$PATH"
if [[ "$(git -C "$flutter_dir" describe --tags --exact-match HEAD)" != "$flutter_version" ]]; then
  echo "Flutter checkout must match .flutter-version ($flutter_version). Rebuild the container." >&2
  exit 1
fi
flutter doctor
flutter pub get
