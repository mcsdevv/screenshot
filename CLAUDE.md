# Screenshot App - Project Instructions

## Project Overview

This is a macOS screenshot/screen capture application built with Swift and SwiftUI.

## Build & Verify

Always verify builds with:
```bash
xcodebuild -project ScreenCapture.xcodeproj -scheme ScreenCapture build
```

Or open in Xcode and build with Cmd+B.

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
