# Build configuration

Use Flutter **3.38.7** / Dart **3.10.7**, Java **17**, and the checked-in Gradle wrapper and Android plugin versions. Avoid updating Android build components independently without testing their compatibility.

## Local and CI settings

`android/gradle.properties` is for local development. It enables the Gradle daemon, parallel execution, the build cache, up to four workers, and a 4 GB heap with 1 GB metaspace. Reusing the daemon and caches helps repeated builds.

`android/gradle-ci.properties` bounds CI resource usage: two workers, a 3 GB heap with 768 MB metaspace, and no persistent daemon. Both configurations disable configuration caching because compatibility with Flutter and Android plugins is not assumed. Configuration on demand is a separate feature and is not enabled.

Workflows copy the CI properties into place for their disposable checkout. Formatting verification is read-only and no workflow commits that configuration change to a branch. Avoid copying CI properties over your local configuration unless you intend to restore it afterward.

## Build workflows

`build.yml` verifies formatting, analyzes Dart code, runs the tests and builds debug artifacts. It caches Gradle dependencies, the Flutter SDK and pub packages, and cancels redundant builds for the same branch.

`release.yml` builds on version tags; `pre-release.yml` supports manual beta/alpha builds. Both require all signing credentials and produce signed APK and App Bundle artifacts. See [SIGNING.md](SIGNING.md). Developer debug builds use the standard Android debug key.

```bash
flutter pub get
flutter build apk --debug
# After configuring private release credentials:
flutter build apk --release
```

Release builds enable R8 code and resource shrinking. The Android app configuration controls Java 17 compilation and uses Flutter's SDK defaults for compile/target/minimum Android versions. Keep custom ProGuard rules only when your app or plugins require them.

Build time and APK size depend on hardware, dependency downloads, cache state and application content. Measure your app instead of relying on fixed speed or size estimates. Use `flutter clean` to investigate stale build artifacts, rather than as part of every normal build.

The optional `astro/` site uses Node 24 LTS and has a separate website deployment workflow.
