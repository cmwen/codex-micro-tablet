# Template repair validation

Validated on 20 October 2026 in the isolated Run worktree. The Flutter counter
starter, storage service, and optional Astro website remain. The optional
language-model toolkit, its tests, documentation, skills, and exclusive HTTP
dependencies were removed.

## Environment

- Flutter 3.38.7 / Dart 3.10.7, pinned in `.flutter-version` and CI/devcontainer.
- Java 17 and the Linux Android SDK, using the workspace's `android-env.sh`.
- Node 24.12.0 for the optional Astro site.

## Results

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed; removed three unused locked HTTP dependencies without upgrading retained packages |
| `dart format --output=none --set-exit-if-changed .` | Passed; four Dart files, no changes |
| `flutter analyze --no-pub` | Passed; no issues |
| `flutter test --no-pub` | Passed; starter widget smoke test |
| `flutter build apk --debug --no-pub` | Passed |
| Release APK without signing configuration | Failed as intended with an explicit list of missing signing properties |
| `flutter build apk --release --no-pub` with disposable signing configuration | Passed; APK signature verified with Android `apksigner` |
| `python3 scripts/checks/rename-regression.py` | Passed; disposable copy, interactive setup, repeated rename, analysis, tests, formatting, debug APK identity and launch activity |
| Website `npm ci` / `npm run build` on Node 24 | Passed; final content rebuild also passed with telemetry disabled |
| `actionlint` | Passed for all workflows |
| Bash syntax and Python compilation checks | Passed |
| Agent skill structure/symlink verifier | Passed; four remaining skills |
| Website release resolver | Seven mocked event/release cases passed |
| `git diff --check` and final diff review | Passed; generated website changes removed and starter/storage files unchanged |

The rename regression checks the literal Flutter title and Android APK label with
quotes, backslashes, XML punctuation, dollar signs, shell substitution syntax, and
multiple percent placeholders. It resolves the APK's application ID and launch
activity using Android build tools and checks that the launch class exists in the
compiled DEX files. This catches a renamed app whose manifest points at a missing
activity, rather than merely checking source substitutions.

Signing checks also exercised each missing composite-action secret, private file
permissions, Java properties escaping (including non-ASCII passwords), and rejection
of malformed or shell-like version inputs. The release APK used a short-lived test
key, not a production signing identity. The private test key and local signing
properties were deleted after verification. No signing credentials were added to
source or logs.

## Limits and follow-up

The existing website dependency tree reported 14 npm audit advisories: one low,
one moderate, eleven high, and one critical. No dependency upgrade or `npm audit fix`
was included in this repair; the optional site needs a separate dependency audit.

The devcontainer configuration and setup script were checked statically; a container
was not recreated. GitHub release publication and Pages deployment were not executed;
workflow validation and resolver tests do not prove a live deployment. App Bundle
builds were not run locally. Integration tests are not installed in this starter.
No tablet installation or on-device launch was performed. Nothing was pushed or
published.
