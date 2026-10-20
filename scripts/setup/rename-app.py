#!/usr/bin/env python3
"""Rename the starter using literal input; no shell or replacement-string evaluation."""
import argparse
import json
from pathlib import Path
import re
from xml.sax.saxutils import escape

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app_name")
parser.add_argument("display_name")
parser.add_argument("package_name")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
# Reject language keywords as identifiers as well as malformed names.
keywords = set("abstract as assert async await break case catch class const continue default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield package fun object val when typealias typeof public private protected internal".split())
if not re.fullmatch(r"[a-z][a-z0-9_]*", args.app_name) or args.app_name in keywords:
    parser.error("app_name must be a non-keyword lowercase Dart identifier")
parts = args.package_name.split(".")
if len(parts) < 2 or any(not re.fullmatch(r"[a-z][a-z0-9_]*", p) or p in keywords for p in parts):
    parser.error("package_name must contain non-keyword lowercase package segments")
if not args.display_name or any(ord(c) < 32 for c in args.display_name):
    parser.error("display_name must be nonempty and contain no control characters")

pubspec = root / "pubspec.yaml"
old_name = re.search(r"^name:\s*(\w+)", pubspec.read_text(), re.M)[1]
gradle = root / "android/app/build.gradle.kts"
old_package = re.search(r'namespace = "([^"]+)"', gradle.read_text())[1]
activity = root / "android/app/src/main/kotlin" / Path(*old_package.split(".")) / "MainActivity.kt"
if not activity.is_file():
    parser.error(f"expected starter activity missing: {activity}")
# Prepare edits before writing anything.
updates = {}
updates[pubspec] = re.sub(r"^name:.*$", f"name: {args.app_name}", pubspec.read_text(), flags=re.M)
updates[pubspec] = re.sub(r"^description:.*$", lambda _: "description: " + json.dumps(args.display_name + " - Built with min-android-app-template", ensure_ascii=False), updates[pubspec], flags=re.M)
for folder in ("lib", "test", "integration_test"):
    for path in (root / folder).rglob("*.dart"):
        updates[path] = path.read_text().replace(f"package:{old_name}/", f"package:{args.app_name}/")
main = root / "lib/main.dart"
# JSON strings are valid Dart strings after escaping interpolation.
dart_title = json.dumps(args.display_name, ensure_ascii=False).replace("$", r"\$")
title_pattern = r"""title:\s*(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")"""
updates[main], count = re.subn(title_pattern, lambda _: "title: " + dart_title, updates[main])
if count < 2:
    parser.error("expected MaterialApp and home screen titles in starter main.dart")
updates[gradle] = re.sub(r'(namespace|applicationId) = "[^"]+"', lambda m: f'{m[1]} = "{args.package_name}"', gradle.read_text())
manifest = root / "android/app/src/main/AndroidManifest.xml"
updates[manifest] = re.sub(r'android:label="[^"]*"', 'android:label="@string/app_name"', manifest.read_text())
# Quoted Android string values preserve whitespace and protect @, ?, apostrophes.
android_title = args.display_name.replace("\\", "\\\\").replace('"', r'\"').replace("'", r"\'")
strings = root / "android/app/src/main/res/values/app_name.xml"
updates[strings] = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name" formatted="false">"' + escape(android_title) + '"</string>\n</resources>\n'
new_activity = root / "android/app/src/main/kotlin" / Path(*parts) / "MainActivity.kt"
updates[new_activity] = re.sub(r"^package\s+[^\s;]+;?", "package " + args.package_name, activity.read_text(), flags=re.M)
for path, content in updates.items():
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
if new_activity != activity:
    activity.unlink()
    parent = activity.parent
    kotlin = root / "android/app/src/main/kotlin"
    while parent != kotlin and not any(parent.iterdir()):
        parent.rmdir()
        parent = parent.parent
print(f"Renamed to {args.app_name} ({args.package_name}).")
