# Agent Configuration and Instructions

This document provides guidance for AI agents and automated tools working with this Android Flutter template repository.

> **Multi-tool support**: This repo is configured for both **GitHub Copilot** (`.github/agents/`, `.github/skills/`) and **OpenCode CLI** (`.opencode/agents/` for opencode-compatible agents, `.opencode/skills/` symlinked to `.github/skills/`). The root `AGENTS.md` is read by all major coding agents.
>
> **Note on agent formats**: GitHub Copilot agents (`.github/agents/*.agent.md`) and OpenCode agents (`.opencode/agents/*.md`) use different frontmatter schemas and cannot be symlinked. The `.opencode/agents/` files are native opencode format with `mode: subagent`, `tools: {write, edit, bash, webfetch}`, and `permission` blocks. Skills remain as symlinks since both tools share the same `SKILL.md` format.

## 🎯 Quick Reference for AI Agents

**First-Time Users**: Direct them to [GETTING_STARTED.md](GETTING_STARTED.md) for complete setup guide.

**Customization**: Use [APP_CUSTOMIZATION.md](APP_CUSTOMIZATION.md) for comprehensive customization checklist with AI prompts.

**Important Files to Update When Renaming App**:
- `pubspec.yaml` (name, description)
- `lib/main.dart` (imports, title)
- `test/widget_test.dart` (imports)
- `android/app/build.gradle.kts` (namespace, applicationId)
- `android/app/src/main/kotlin/.../MainActivity.kt` (package declaration and directory)
- `android/app/src/main/AndroidManifest.xml` (label)

## Repository Overview

This is a production-ready Android Flutter template with AI-powered development workflow, optimized build system (Java 17, parallel builds, caching), and comprehensive CI/CD. All agents have access to VS Code tools including terminal, debugger, test runner, and codebase explorer.

## AI Agents Overview

This template includes 7 specialized agents (defined in `.github/agents/`):

| Agent | Purpose |
|-------|---------|
| **@orchestrator** | Coordinate multi-agent workflows; delegates to subagents by task type |
| **@product-owner** | Define features, requirements, user stories |
| **@experience-designer** | Design UX, user flows, wireframes |
| **@architect** | Plan architecture, technical decisions |
| **@researcher** | Research packages, best practices |
| **@flutter-developer** | Implement features, write tests, debug |
| **@doc-writer** | Create documentation, guides |

**Use `@orchestrator` for complex, multi-step requests** — it decomposes the work, delegates each part to the right specialist, and synthesizes the results. For simple single-domain tasks, invoke the specialist directly.

**All agents have terminal access** - They can run Flutter commands, tests, builds, and formatting.

## Agent Skills

This project includes **Agent Skills** — specialized, reusable workflows for specific tasks.

### Available Skills

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| **icon-generation** | Generate app icons and launcher assets | Creating UI or launcher icons, setting up flutter_launcher_icons |
| **android-debug** | Debug Android app issues | App crashes, device issues, performance problems |
| **ci-debug** | Fix GitHub Actions failures | Workflow failures, CI-specific build errors |
| **build-fix** | Diagnose build failures | Gradle errors, dependency conflicts, compilation issues |

### Skill Locations

Skills are stored in `.github/skills/` and symlinked to `.opencode/skills/` for cross-tool compatibility:

- **GitHub Copilot**: Reads from `.github/skills/<name>/SKILL.md`
- **OpenCode CLI**: Reads from `.opencode/skills/<name>/SKILL.md` (symlinks)
- **Other agents**: Read this `AGENTS.md` for skill descriptions

## Key Technologies

- **Framework**: Flutter 3.38.7
- **Language**: Dart 3.10.7
- **Build System**: Java 17, Gradle 8.0+ with parallel builds and caching
- **Platform**: Android
- **Package Manager**: pub (pubspec.yaml)
- **Testing**: flutter_test unit and widget tests; integration tests are not installed
- **Linting**: flutter_lints 6.0.0
- **CI/CD**: GitHub Actions with caching and concurrency control

## Project Structure

```
├── lib/                    # Dart source code
│   └── main.dart           # App entry point
├── test/                   # Unit and widget tests
├── android/                # Android platform files
├── docs/                   # AI prompting guides
├── scripts/                # Automation scripts
│   ├── signing/            # Signing-related scripts
│   ├── setup/              # Setup scripts
│   └── release/            # Release scripts
├── .github/                # CI/CD workflows and agents
│   ├── workflows/          # GitHub Actions
│   ├── actions/            # Custom composite actions
│   ├── agents/             # Copilot Chat agents (.agent.md)
│   └── skills/             # Agent skills (SKILL.md)
├── .opencode/              # OpenCode CLI compatibility
│   ├── agents/             # OpenCode-compatible agents (mode: subagent, opencode format)
│   └── skills/             # Symlinks → .github/skills/
└── pubspec.yaml            # Dependencies and project config
```

## AI Customization Points

When using this template, AI agents should focus on these key customization areas:

### 1. App Identity (pubspec.yaml)
```yaml
name: your_app_name           # Change app name
description: "Your app description"
version: 1.0.0+1              # Update version
```

### 2. App Entry Point (lib/main.dart)
- Change `title` in MaterialApp
- Modify `colorScheme` seedColor for theming
- Replace `MyHomePage` with your own screens

### 3. Android Configuration
- `android/app/build.gradle.kts`: Change `applicationId`
- `android/app/build.gradle.kts`: Configure signing (see release workflow)

## Flutter Commands

### Basic Commands
```bash
# Get dependencies
flutter pub get

# Run app
flutter run

# Build debug (no private signing credentials needed)
flutter build apk --debug

# Build release after configuring private signing (see SIGNING.md)
flutter build apk           # Android APK
flutter build appbundle     # Android App Bundle

# Run tests
flutter test

# Analyze code
flutter analyze
```

## CI/CD Workflows

### build.yml
- Runs on push to main/develop and PRs
- Verifies formatting with `dart format --output=none --set-exit-if-changed .`
- Builds a debug APK
- Runs tests with parallel execution
- Uploads coverage to Codecov
- Uses CI-optimized Gradle properties
- Implements caching for Gradle, Flutter, and pub packages
- Concurrency control to cancel duplicate runs
- Timeout: 30 minutes

### release.yml
- Triggered by version tags (v*)
- Builds signed release artifacts
- Creates GitHub Release with auto-generated notes
- Uses CI-optimized Gradle properties
- Artifact retention: 90 days
- Timeout: 45 minutes

**Required Secrets for Signed Releases:**
- `ANDROID_KEYSTORE_BASE64`: Base64-encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password

### pre-release.yml
- Manual workflow dispatch for beta/alpha releases
- Customizable version naming
- Creates pre-release on GitHub
- Supports alpha, beta, and pre-release types
- Artifacts named with version and release type

## Build configuration

Local `android/gradle.properties` enables the daemon and build cache, up to four workers, and a 4 GB heap. CI uses `android/gradle-ci.properties` with two workers, a 3 GB heap, and no daemon. Both disable configuration caching for compatibility. Keep Java 17 and the checked-in Gradle/plugin versions aligned with the tested Flutter SDK.

Release builds enable code and resource shrinking and require configured private signing credentials. Debug builds use the Android debug key. See [BUILD_OPTIMIZATION.md](BUILD_OPTIMIZATION.md) and [SIGNING.md](SIGNING.md).

## Documentation Resources

- `docs/AI_BEGINNER_GUIDE.md` - For complete beginners
- `docs/AI_INTERMEDIATE_GUIDE.md` - For developers new to Flutter
- `docs/AI_ADVANCED_GUIDE.md` - For experienced developers
- `docs/AI_PROMPT_TEMPLATES.md` - Ready-to-use prompts
- `AI_PROMPTING_GUIDE.md` - Overview of all guides

## Common Tasks and Agent Workflows

### Task: Rename the App

**Agent**: @flutter-developer

**Prompt**:
```
Please rename this Flutter app from "min_flutter_template" to "my_awesome_app" 
and update the package from "com.cmwen.min_flutter_template" to "com.mycompany.my_awesome_app".

Update all files including:
- pubspec.yaml (name, description)
- lib/main.dart (imports, title)
- test/widget_test.dart (imports)
- android/app/build.gradle.kts (namespace, applicationId)
- android/app/src/main/kotlin/.../MainActivity.kt (package declaration and directory)
- android/app/src/main/AndroidManifest.xml (label)

After updates, run flutter pub get and verify compilation.
```

### Task: Generate App Icon

**Agent**: Use icon-generation.prompt.md

**Prompt**:
```
@icon-generation.prompt.md

Create an app launcher icon for my [TYPE OF APP] app.

Requirements:
- App concept: [DESCRIBE]
- Style: [minimal/flat/gradient]
- Primary color: #[HEX]
- Symbol: [DESCRIBE ICON CONCEPT]

Provide 1024×1024 PNG and setup instructions for flutter_launcher_icons package.
```

### Task: Implement New Feature

**Multi-Agent Workflow**:

1. **Define Requirements** (@product-owner):
```
@product-owner Create user stories and acceptance criteria for [FEATURE NAME].
Include MVP scope and success metrics. Save to docs/REQUIREMENTS_[FEATURE].md
```

2. **Design UX** (@experience-designer):
```
@experience-designer Based on docs/REQUIREMENTS_[FEATURE].md, design the user flow 
and wireframes. Consider Material Design 3 patterns. Save to docs/UX_DESIGN_[FEATURE].md
```

3. **Research Dependencies** (@researcher):
```
@researcher What packages do I need for [FEATURE REQUIREMENTS]? 
Compare options and recommend best choice. Save to docs/DEPENDENCIES_[FEATURE].md
```

4. **Plan Architecture** (@architect):
```
@architect Design the architecture for [FEATURE] including data models, 
repositories, state management, and folder structure. Follow project conventions.
Save to docs/ARCHITECTURE_[FEATURE].md
```

5. **Implement** (@flutter-developer):
```
@flutter-developer Implement [FEATURE] following docs/ARCHITECTURE_[FEATURE].md.
- Create models in lib/models/
- Implement services in lib/services/
- Create UI in lib/screens/[feature]/
- Add state management with [chosen solution]
- Write unit and widget tests
- Run flutter test and dart format
```

6. **Document** (@doc-writer):
```
@doc-writer Document [FEATURE] including:
- API documentation
- Usage examples
- User guide (if needed)
Save to docs/FEATURE_[NAME]_GUIDE.md
```

### Task: Debug Build Issue

**Agent**: @flutter-developer

**Workflow**:
```
@flutter-developer I'm getting this build error:
[PASTE ERROR]

Please:
1. Use #tool:problems to see all compilation errors
2. Use #tool:codebase to find related code
3. Use #tool:terminal to run flutter clean and flutter pub get
4. Fix the issues
5. Verify with flutter analyze and flutter test
```

### Task: Optimize Performance

**Multi-Agent Workflow**:

1. **Analyze** (@flutter-developer):
```
@flutter-developer Use #tool:terminal to run:
- flutter build apk --analyze-size
- flutter run --profile
Identify performance bottlenecks and large dependencies.
```

2. **Research** (@researcher):
```
@researcher Research Flutter performance optimization techniques for [SPECIFIC ISSUE].
Find packages or patterns to improve [scroll performance/load time/etc].
```

3. **Architect** (@architect):
```
@architect Design performance optimization strategy for [ISSUE].
Consider caching, lazy loading, code splitting, etc.
```

4. **Implement** (@flutter-developer):
```
@flutter-developer Implement performance optimizations:
- Add const constructors
- Implement lazy loading
- Use RepaintBoundary where needed
- Profile before/after with DevTools
```

### Task: Set Up CI/CD

**Agent**: @doc-writer + terminal

**Prompt**:
```
@doc-writer Guide me through setting up GitHub repository and CI/CD:

1. Create GitHub repository
2. Update git remote to new repo URL
3. Generate Android keystore for signed releases
4. Add GitHub Secrets:
   - ANDROID_KEYSTORE_BASE64
   - ANDROID_KEYSTORE_PASSWORD
   - ANDROID_KEY_ALIAS
   - ANDROID_KEY_PASSWORD
5. Test workflows by pushing a commit
6. Create first release with git tag v1.0.0

Provide step-by-step commands using #tool:terminal.
```

### Task: Add New Dependency

**Multi-Agent Workflow**:

1. **Research** (@researcher):
```
@researcher Find the best Flutter package for [FUNCTIONALITY].
Compare latest versions, maintenance, popularity, and alternatives.
```

2. **Architect** (@architect):
```
@architect How should I integrate [PACKAGE] into the project?
What architecture patterns should I follow? Any gotchas?
```

3. **Implement** (@flutter-developer):
```
@flutter-developer Add [PACKAGE] to pubspec.yaml and implement basic usage:
1. Add dependency
2. Run flutter pub get
3. Create example usage in lib/services/
4. Write tests
5. Update documentation
```

## VS Code Tool Usage Guidelines

### When to Use Each Tool

**#tool:terminal**:
- Running Flutter commands (run, build, test, analyze)
- Installing dependencies (flutter pub get)
- Formatting code (dart format)
- Running scripts
- Checking git status
- Building for Android

**#tool:runTests**:
- Executing specific test files
- Running test suites
- Quick test feedback
- Integration with VS Code test explorer

**#tool:debugger**:
- Setting breakpoints in code
- Inspecting variables and state
- Stepping through code execution
- Debugging complex logic
- Widget tree inspection

**#tool:problems**:
- Viewing compiler errors
- Checking linter warnings
- Finding syntax errors
- Identifying deprecation warnings

**#tool:changes**:
- Reviewing uncommitted changes
- Checking git diff
- Verifying edits before commit
- Understanding modified files

**#tool:codebase**:
- Understanding project structure
- Finding existing implementations
- Discovering patterns
- Navigating large codebases

**#tool:search**:
- Finding specific code patterns
- Locating class/method definitions
- Searching across files
- Finding usage examples

## Best Practices for AI Agents

1. **Always use terminal to verify changes** - Run tests and analyzer after implementation
2. **Save documentation to docs/** - Future agents can reference prior decisions
3. **Use descriptive file names** - Prefix with REQUIREMENTS_, UX_DESIGN_, ARCHITECTURE_, etc.
4. **Check problems before finishing** - Use #tool:problems to catch errors early
5. **Review changes with #tool:changes** - Ensure no unintended modifications
6. **Run tests with #tool:runTests or #tool:terminal** - Verify functionality
7. **Format locally** - Run `dart format .`; CI verifies formatting without changing or committing files
8. **Use codebase to understand context** - Don't guess patterns, search for them
9. **Handoff between agents** - Use handoff features for multi-stage tasks
10. **Reference documentation files** - Link to docs/ files for context

## Troubleshooting Guide for Agents

### Build Fails

```bash
# Use #tool:terminal to run:
flutter clean
flutter pub get
flutter pub upgrade --major-versions  # if needed
flutter analyze
```

### Import Errors After Rename

```bash
# Use #tool:terminal:
flutter clean
flutter pub get
dart fix --apply
```

### Test Failures

```bash
# Use #tool:runTests or #tool:terminal:
flutter test --verbose
# Check #tool:testFailure for context
# Use #tool:debugger to set breakpoints
```

### Performance Issues

```bash
# Use #tool:terminal:
flutter run --profile
flutter build apk --analyze-size
# Use Flutter DevTools for profiling
```
