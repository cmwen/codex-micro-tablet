# Minimal Android App Template

A Flutter Android starter with a Material 3 counter app, shared-preference storage service, a widget smoke test, and GitHub Actions build and release workflows. Optional agent configurations and an Astro documentation website are included. App architecture, navigation, authentication, and integration tests are choices to add for your app.

## Quick start

Use **Flutter 3.38.7**, which includes **Dart 3.10.7**, and **Java 17**. The SDK version is pinned in `.flutter-version` and aligned with CI and the devcontainer. Python 3 is required for the setup and rename regression scripts. Install Android SDK Platform 36 and accept the SDK licenses. See [PREREQUISITES.md](PREREQUISITES.md) for setup details.

```bash
git clone https://github.com/cmwen/min-android-app-template.git my-app
cd my-app
flutter --version
flutter doctor -v
./scripts/setup/quick-start.sh
```

The interactive setup renames the Dart package, app title, Android application ID and namespace, and Kotlin activity declaration and directory. It then runs dependency resolution, analysis, and tests. Review the changes before starting your own app. You can also follow [PACKAGE_RENAME_GUIDE.md](PACKAGE_RENAME_GUIDE.md) manually. The template runs under its default identity; choose a unique identity before distributing an app or installing it alongside another app derived from this template.

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
# Run on your chosen emulator or device when ready:
flutter run
```

For a cloud setup, create a repository from this template and open it in GitHub Codespaces. The devcontainer installs the same pinned Flutter version.

## Builds and signing

Developer debug builds use the Android debug key. Local release builds require a private signing key and complete `android/key.properties`. CI releases require all four repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. Real releases fail if any credential is absent. See [SIGNING.md](SIGNING.md) for private key generation, local signing, and GitHub secret configuration. Keep keys and passwords out of source, logs, and build artifacts.

```bash
# After configuring private release signing:
flutter build apk --release
flutter build appbundle --release
```

CI checks formatting without editing or committing source files, runs analysis and tests, and builds debug artifacts. Tag-triggered `release.yml` and manually triggered `pre-release.yml` build signed artifacts with configured GitHub secrets. See [BUILD_OPTIMIZATION.md](BUILD_OPTIMIZATION.md) for the local and CI Gradle settings.

## Optional website

`astro/` contains an optional GitHub Pages documentation website. It is independent of the Android app and can be retained, customized, or removed. Use **Node 24 LTS** (Astro 7 requires at least 22.22.0; this site requires Node >=24.0.0):

```bash
cd astro
npm ci
npm run build
```

`deploy-website.yml` handles website deployment, including successful completion of release workflows. Enable GitHub Pages with GitHub Actions as the source before using it.

## Development resources

The repository includes seven optional agent roles: orchestrator, product owner, experience designer, architect, researcher, Flutter developer, and documentation writer. Their configurations live in `.github/agents/` and `.opencode/agents/`; shared task skills live in `.github/skills/`.

- [GETTING_STARTED.md](GETTING_STARTED.md): detailed setup
- [APP_CUSTOMIZATION.md](APP_CUSTOMIZATION.md): customization checklist
- [AGENTS.md](AGENTS.md): agent conventions
- [AI_PROMPTING_GUIDE.md](AI_PROMPTING_GUIDE.md): agent prompts
- [TESTING.md](TESTING.md): unit and widget tests, plus instructions for adding integration tests
- [CONTRIBUTING.md](CONTRIBUTING.md): contributions
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): common issues

```text
lib/           Flutter starter and storage service
test/          Widget smoke test
android/       Android configuration
astro/         Optional documentation website
docs/          Development guides
scripts/       Setup, validation, and signing helpers
```

MIT License. See [LICENSE](LICENSE).
