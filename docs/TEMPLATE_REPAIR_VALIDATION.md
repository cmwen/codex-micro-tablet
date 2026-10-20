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
| Website `npm ci` / `ASTRO_TELEMETRY_DISABLED=1 npm run build` | Passed on Node 24.12.0 / npm 11.6.2 with Astro 7.4.1; exactly four static pages |
| Website `npm audit --json` | Passed; zero advisories across all severities, including development and optional dependencies |
| Generated website content inspection | Passed; all 92 page-source text fragments, page links, titles, and shared navigation retained |
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

The website dependency follow-up on 20 October 2026 upgraded Astro from 6.1.9
(to which the old manifest allowed updates via `^6.1.9`) to 7.4.1 (`^7.4.1`) and
refreshed `astro/package-lock.json` through npm's supported dependency resolution.
Key locked dependencies are Vite 8.3.4, Rolldown 1.2.14,
`@astrojs/compiler-rs` 0.5.2, `@astrojs/markdown-satteri` 0.4.4, devalue 6.0.3,
and cookie 2.0.1. No overrides, forced audit fixes, or advisory exclusions were
used. After a clean `npm ci`, `npm audit --json` exited successfully with an empty
`vulnerabilities` object and zero low, moderate, high, or critical advisories,
resolving the previously reported 14 advisories. This reflects npm's advisory
database at validation time.

The static build passed with telemetry disabled. Inspection of the actual output
confirmed exactly `index.html`, `about/index.html`, `install/index.html`, and
`releases/index.html`, with all page-source text and page links retained. Astro 7
requires Node >=22.22.0; the site's existing stricter Node >=24.0.0 engine remains
valid, and CI still selects Node 24. The README and Astro documentation now
reflect this requirement. Site source, GitHub Pages configuration, and release
workflows were unchanged. Generated tracked `.astro` files were restored and
untracked generated type declarations removed from the review diff.

The website's existing project-base links and stylesheet source path were also
repaired in a follow-up Run. All four generated pages now link under
`/min-android-app-template/`; each internal page link resolves to a generated file.
The layout imports its CSS through Astro, and the bundled stylesheet references
resolve to generated assets. These checks passed against the built HTML; no browser
visual check or live Pages deployment was performed.

The devcontainer configuration and setup script were checked statically; a container
was not recreated. GitHub release publication and Pages deployment were not executed;
workflow validation and resolver tests do not prove a live deployment. App Bundle
builds were not run locally. Integration tests are not installed in this starter.
No tablet installation or on-device launch was performed. Nothing was pushed or
published.
