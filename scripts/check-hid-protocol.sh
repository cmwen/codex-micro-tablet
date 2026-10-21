#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
javac -d "$build_dir" android/app/src/main/java/com/cmwen/codex_micro_tablet/MicroWire.java android/app/src/test/java/com/cmwen/codex_micro_tablet/MicroWireCheck.java
java -cp "$build_dir" com.cmwen.codex_micro_tablet.MicroWireCheck
