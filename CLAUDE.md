# Screenshot App - Project Instructions

## Project Overview

This is a macOS screenshot/screen capture application built with Swift and SwiftUI.

## Conductor Commands

Configuration is in `conductor.json`. Available commands:

| Command | Script | Description |
|---------|--------|-------------|
| Setup | `./scripts/setup.sh` | Verify environment is ready |
| Run | `./scripts/build-and-test.sh --run` | Build and launch app |
| Build | `./scripts/build-and-test.sh` | Build only |
| Test | `./scripts/build-and-test.sh --verbose` | Build with full output |

## Setup

Run once to verify the environment:
```bash
./scripts/setup.sh
```

## Build & Verify

**Always run the build script after making changes:**
```bash
./scripts/build-and-test.sh
```

Options:
- `--run` - Build and launch the app to test changes
- `--clean` - Clean build first
- `--open-xcode` - Open project in Xcode
- `--verbose` - Show full build output
- `--release` - Build release configuration

Example workflow after code changes:
```bash
./scripts/build-and-test.sh --run   # Build and launch to verify
```

Or use the raw xcodebuild command:
```bash
xcodebuild -project ScreenCapture.xcodeproj -scheme ScreenCapture build
```

## Skills to Use

- **UI changes**: Always use `frontend-design` skill for any UI modifications
- **Debugging**: Use `systematic-debugging` for any crashes or unexpected behavior
- **New features**: Use `brainstorming` before implementing new annotation tools or UI elements

## Swift/SwiftUI Guidelines

- Use `@State`, `@Binding`, and `@ObservableObject` appropriately
- Prefer `guard` statements over force unwrapping
- Use `async/await` for asynchronous operations
- Keep views small and composable
- Use `PreviewProvider` for all views to enable SwiftUI previews

## Code Style

- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Use meaningful variable names
- Add documentation comments for public APIs
- Keep functions focused and single-purpose

## Documentation Updates

The documentation site is in `docs/` using Fumadocs (Next.js). When modifying features:

1. Update the relevant MDX file in `docs/content/docs/`
2. If adding a new feature, create a new MDX file
3. Update `meta.json` navigation if needed
4. Run `cd docs && pnpm build` to verify
5. Commit both code and docs changes together

### Documentation Structure

```
docs/content/docs/
├── index.mdx              # Getting Started
├── capture/               # Screenshot capture modes
├── recording/             # Video and GIF recording
├── annotation/            # Annotation tools
├── features/              # Additional features
├── shortcuts/             # Keyboard shortcuts
├── settings/              # App settings
├── storage/               # File management
└── system/                # System integration
```

### Keeping FEATURES.md in Sync

When updating documentation, also update `FEATURES.md` in the root to keep it as the source of truth for feature specifications.

## Mandatory Documentation Checklist

**CRITICAL: Every PR that adds/modifies user-facing features MUST include documentation updates.**

Before marking work complete:
- [ ] Update relevant MDX file in `docs/content/docs/`
- [ ] Update `FEATURES.md` if feature spec changed
- [ ] Run `cd docs && pnpm build` to verify
- [ ] Commit docs with code changes

If you skip this, you MUST create a follow-up task for documentation.
