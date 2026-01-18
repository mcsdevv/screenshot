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
