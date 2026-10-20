#!/usr/bin/env python3
"""Build and inspect a renamed starter in a disposable copy (requires Android SDK)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
flutter = os.environ.get("FLUTTER", "flutter")
dart = str(Path(shutil.which(flutter) or flutter).resolve().with_name("dart"))

def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True)

with tempfile.TemporaryDirectory(prefix="android-rename-") as temp:
    copy = Path(temp) / "app"
    shutil.copytree(root, copy, ignore=shutil.ignore_patterns(
        ".git", ".dart_tool", "build", "node_modules", ".gradle", ".kotlin",
        "key.properties", "*.jks", "*.keystore", "local.properties", "coverage"))
    title = """Sam's "App" & <Tools> / $value \\ $(touch rename-injection-marker) %s %d"""
    package = "com.example.renameprobe"
    # Exercise the actual interactive quick-start including hostile punctuation.
    subprocess.run(["bash", "scripts/setup/quick-start.sh"], cwd=copy,
                   input=f"rename_probe\n{title}\n{package}\ny\n", text=True, check=True)
    assert not (copy / "rename-injection-marker").exists()
    # A second rename verifies detection of current identity and escaped Dart titles.
    run("python3", "scripts/setup/rename-app.py", "renamed_again", title, package, cwd=copy)
    expected = json.dumps(title).replace("$", r"\$")
    (copy / "test/renamed_identity_test.dart").write_text("""
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renamed_again/main.dart';
void main() {
  testWidgets('Renamed app exposes its literal display name', (tester) async {
    await tester.pumpWidget(const MyApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, EXPECTED);
    expect(find.text(EXPECTED), findsOneWidget);
  });
}
""".replace("EXPECTED", expected))
    run(dart, "format", "lib", "test", cwd=copy)
    run(flutter, "pub", "get", cwd=copy)
    run(dart, "format", "--output=none", "--set-exit-if-changed", "lib", "test", cwd=copy)
    run(flutter, "analyze", "--no-pub", cwd=copy)
    run(flutter, "test", "--no-pub", cwd=copy)
    run(flutter, "build", "apk", "--debug", "--no-pub", cwd=copy)
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
    aapt = sorted((sdk / "build-tools").glob("*/aapt"))[-1]
    apk = copy / "build/app/outputs/flutter-apk/app-debug.apk"
    badging = subprocess.check_output([aapt, "dump", "badging", apk], text=True)
    assert f"package: name='{package}'" in badging, badging
    label = next(line for line in badging.splitlines() if line.startswith("application-label:"))
    # aapt escapes double quotes and backslashes when printing string values.
    label_value = re.sub(r'\\(["\\])', r'\1', label[len("application-label:'"):-1])
    assert label_value == title, label
    launch = re.search(r"launchable-activity: name='([^']+)'", badging)[1]
    assert launch == package + ".MainActivity", launch
    # Confirm the manifest launch target actually exists among the compiled classes.
    descriptor = ("L" + launch.replace(".", "/") + ";").encode()
    with zipfile.ZipFile(apk) as archive:
        assert any(descriptor in archive.read(name) for name in archive.namelist()
                   if re.fullmatch(r"classes\d*\.dex", name)), launch
    print("Rename regression passed: widget title, analyze/tests, APK identity and compiled launch activity.")
