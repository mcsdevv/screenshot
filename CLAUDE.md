# Screenshot App - Project Instructions

macOS screenshot/screen capture app. Swift + SwiftUI + ScreenCaptureKit.

## Native-Only Rule (CRITICAL)

Only native Apple frameworks/APIs are permitted for implementation and runtime behavior unless explicitly requested otherwise.
Do not introduce or rely on shelling out to external binaries, private system utilities, or third-party tooling when a native API path exists.

## Build Commands

```bash
./scripts/build-and-test.sh          # Build only
./scripts/build-and-test.sh --run    # Build and launch
./scripts/build-and-test.sh --clean  # Clean build
```

## Skill Overrides (stricter than global)

- **Any UI change**: MUST use `frontend-design` skill. This app has a design system (`DesignSystem.swift`)—never use raw SwiftUI styling.
- **Any crash/unexpected behavior**: MUST use `systematic-debugging`. This app has complex window lifecycle issues.

## Project-Specific Anti-Patterns (CRITICAL)

These are battle scars from this codebase. Violating them causes real crashes.

### NSWindow Double-Release (EXC_BAD_ACCESS)

**Problem:** Programmatic NSWindows crash on close due to ARC + AppKit double-release.

**Rule:** ALWAYS set `isReleasedWhenClosed = false` immediately after creating any NSWindow.

```swift
// CORRECT
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false  // CRITICAL - prevents crash

// WRONG - will crash when window closes
let window = NSWindow(...)
// missing isReleasedWhenClosed = false
```

**Files that create windows (check all when adding new windows):**
- `AppDelegate.swift` - QuickAccessOverlay, AllInOneMenu
- `ScreenRecordingManager.swift` - selection window, control window
- `PinnedScreenshotWindow.swift` - pinned screenshot window

### Design System Consistency

**Problem:** New UI uses raw SwiftUI (`.accentColor`, `.bordered`) instead of design system.

**Rule:** Always use `DS*` components and colors:
- Colors: `.dsAccent`, `.dsTextPrimary`, `.dsTextSecondary`
- Buttons: `DSPrimaryButton`, `DSSecondaryButton`, `DSIconButton`
- Spacing: `DSSpacing.*`, `DSRadius.*`
- Typography: `DSTypography.*`

```swift
// CORRECT
Text("Title").font(DSTypography.title).foregroundColor(.dsTextPrimary)
DSPrimaryButton("Save") { save() }

// WRONG - breaks visual consistency
Text("Title").font(.title).foregroundColor(.primary)
Button("Save") { save() }.buttonStyle(.borderedProminent)
```

### Keyboard Shortcut Conflicts

**Problem:** `Cmd+Shift+3/4/5` conflicts with macOS Screenshot.app.

**Rule:** Use `Ctrl+Shift` prefix in Safe Mode (default). See `KeyboardShortcuts.swift` for the pattern.

## Documentation Sync

Docs site: `docs/` (Fumadocs/Next.js). FEATURES.md is source of truth.

**Every user-facing change requires:**
1. Update MDX in `docs/content/docs/`
2. Update `FEATURES.md`
3. Run `cd docs && pnpm build`
4. Commit code + docs together

**If you skip docs:** Create explicit follow-up todo. Don't leave it implicit.
