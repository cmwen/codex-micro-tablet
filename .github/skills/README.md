# Agent Skills

This directory contains [Agent Skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) — specialized, reusable instructions that guide AI agents to perform specific tasks according to project best practices.

## Cross-Tool Compatibility

Skills are stored here (`.github/skills/`) as the canonical source and symlinked to `.opencode/skills/` for OpenCode CLI compatibility. Both tools read the same `SKILL.md` files.

| Tool | Discovery Path |
|------|---------------|
| **GitHub Copilot** (VS Code, CLI, Coding Agent) | `.github/skills/<name>/SKILL.md` |
| **OpenCode CLI** | `.opencode/skills/<name>/SKILL.md` (symlinks) |
| **Other agents** (Cursor, Codex, etc.) | Root `AGENTS.md` lists all skills |

### Adding a new skill

1. Create `.github/skills/your-skill-name/SKILL.md`
2. Add symlink: `cd .opencode/skills && ln -s ../../.github/skills/your-skill-name your-skill-name`

## What Are Agent Skills?

Agent Skills are folders containing structured instructions, workflows, and examples that Copilot agents can use to handle specialized tasks. Each skill has:

- **SKILL.md**: Main skill file with YAML frontmatter and detailed instructions
- **Frontmatter**: Metadata including name, description, and when to use the skill
- **Body**: Detailed workflows, commands, examples, and troubleshooting guidance

Skills are automatically discovered by Copilot in VS Code, GitHub CLI, and Copilot agents.

## Available Skills

### 🎨 icon-generation
**Path**: `.github/skills/icon-generation/`

Generate app icons (SVG/PNG) and launcher icons for Android Flutter apps.

**Use when**:
- Creating UI icons or launcher icons
- Setting up flutter_launcher_icons
- Generating platform-ready icon assets
- Creating consistent, accessible icons

**Key capabilities**:
- Provides sizing guidance for Android mipmap densities
- Includes prompt templates for AI image generation
- Documents flutter_launcher_icons setup
- Best practices for icon design

---

### 🐛 android-debug
**Path**: `.github/skills/android-debug/`

Debug Android Flutter apps including runtime errors, build issues, and performance problems.

**Use when**:
- App crashes or runtime errors on Android
- Device/emulator connection issues
- Performance problems (lag, memory, battery)
- Platform channel issues
- APK/App Bundle generation problems

**Key capabilities**:
- Complete debugging workflow from identification to resolution
- ADB commands and Flutter DevTools usage
- Platform-specific troubleshooting (Gradle, manifests, resources)
- Performance profiling guidance
- Quick troubleshooting checklist

---

### 🔧 ci-debug
**Path**: `.github/skills/ci-debug/`

Debug GitHub Actions workflow failures and CI-specific issues.

**Use when**:
- GitHub Actions workflows fail
- CI build errors that don't occur locally
- Test failures only in CI environment
- Artifact or secret issues
- Timeout or cache problems

**Key capabilities**:
- Workflow-specific debugging for build.yml, release.yml, pre-release.yml
- Common CI failure patterns and solutions
- Cache and artifact troubleshooting
- Read-only formatting verification
- Local CI simulation commands

---

### 🏗️ build-fix
**Path**: `.github/skills/build-fix/`

Diagnose and fix Flutter build failures including dependency conflicts and Gradle errors.

**Use when**:
- Flutter build fails (apk, appbundle)
- Gradle sync or build errors
- Dependency resolution failures
- Compilation errors (Dart or native)
- Version conflicts

**Key capabilities**:
- Systematic diagnostic workflow by build stage
- Common failure patterns with solutions
- Gradle, Java/JVM, R8/ProGuard issues
- Project-specific configuration guidance
- Performance optimization tips
- Troubleshooting checklist and quick reference

---

## How to Use Skills

### GitHub Copilot (VS Code / CLI)
Skills are automatically discovered from `.github/skills/`. Reference them in chat:
```
@workspace Use the android-debug skill to help me fix this crash
```

### OpenCode CLI
Skills are discovered from `.opencode/skills/` (symlinked to `.github/skills/`):
```
Use the build-fix skill to diagnose my Gradle error
```

## Skill Structure

Each skill follows this structure:

```
.github/skills/
└── skill-name/
    └── SKILL.md          # Main skill file
```

### SKILL.md Format

```markdown
---
name: skill-name
description: What the skill does and when to use it
---

# Skill Title

Detailed instructions, workflows, examples, and resources.
```

## Creating New Skills

To add a new skill:

1. **Create directory**: `.github/skills/your-skill-name/`
2. **Create SKILL.md** with:
   - YAML frontmatter (name, description)
   - Clear "When to Use" section
   - Structured workflow or instructions
   - Examples and code snippets
   - Troubleshooting guidance
   - Links to relevant resources

3. **Add OpenCode symlink**:
   ```bash
   cd .opencode/skills && ln -s ../../.github/skills/your-skill-name your-skill-name
   ```

4. **Follow best practices**:
   - Use lowercase-with-hyphens for skill names
   - Be specific about when to use the skill
   - Include practical examples
   - Add commands and code snippets
   - Provide troubleshooting steps
   - Keep instructions actionable

5. **Update this README**: Add your skill to the list above

## Skill Guidelines

**Good skills**:
- Focus on specific, repeatable tasks
- Include clear workflows and decision trees
- Provide concrete examples and commands
- Document edge cases and gotchas
- Reference project-specific configuration

**Avoid**:
- Vague or overly broad guidance
- Duplicating information available in docs
- Skills that are too similar to existing ones
- Complex dependencies between skills

## Related Resources

- **Custom Agents**: `.github/agents/` — Role-based agent personas (GitHub Copilot)
- **OpenCode Skills**: `.opencode/skills/` — Symlinks for OpenCode CLI compatibility
- **Documentation**: `docs/` — Project documentation
- **Workflows**: `.github/workflows/` — CI/CD automation

## Additional Information

### Skills vs Agents

- **Skills**: Task-specific, reusable workflows (this directory)
- **Agents**: Role-based personas with tools (`.github/agents/`)

### Official Documentation

- [GitHub Copilot Agent Skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- [OpenCode Skills](https://opencode.ai/docs/skills)
- [VS Code Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)

## Contributing

When contributing skills:

1. Test the skill with Copilot
2. Ensure it doesn't duplicate existing skills
3. Follow the structure and format
4. Update this README
5. Consider if it should be a skill vs documentation

For questions or suggestions, open an issue or PR.
