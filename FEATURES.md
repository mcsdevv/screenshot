# Features

A comprehensive macOS screenshot and screen recording application with annotation tools, capture history, and system-level integration.

**Platform:** macOS 14.0+
**Architecture:** SwiftUI + AppKit with ScreenCaptureKit

---

## Screenshot Capture

### Capture Area
Interactive region selection for precise screenshots.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+4` |
| Shortcut (Native Mode) | `Cmd+Shift+4` |
| Format | PNG |
| Cancel | `Esc` (immediate) |

### Capture Window
Capture a specific window with optional shadow.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+5` |
| Shortcut (Native Mode) | `Cmd+Shift+5` |
| Format | PNG |
| Cancel | `Esc` (immediate) |
| Options | Include/exclude window shadow |

### Capture Fullscreen
Capture the entire primary display instantly.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+3` |
| Shortcut (Native Mode) | `Cmd+Shift+3` |
| Format | PNG |

### Scrolling Capture
Multi-frame capture with automatic image stitching for long content.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+6` |
| Shortcut (Native Mode) | `Cmd+Shift+6` |
| Format | PNG (stitched) |
| Resolution | 2x (Retina) |
| Overlap Detection | 10% |

---

## Screen Recording

### Video Recording
Record screen activity as MP4 video.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+7` |
| Shortcut (Native Mode) | `Cmd+Shift+7` |
| Format | MP4 |
| Video Codec | H.264 (High Profile) |
| Video Bitrate | 10 Mbps |
| Frame Rate | 30 or 60 FPS (configurable) |
| Audio Codec | AAC |
| Audio Bitrate | 128 kbps |
| Audio Sample Rate | 48 kHz stereo |

**Recording Controls:**
- Stop button with duration timer
- Optional cursor display
- Optional microphone/system audio

### GIF Recording
Record screen as animated GIF.

| Setting | Value |
|---------|-------|
| Shortcut (Safe Mode) | `Ctrl+Shift+8` |
| Shortcut (Native Mode) | `Cmd+Shift+8` |
| Format | Animated GIF |
| Frame Rate | 10, 15, or 20 FPS |
| Loop | Infinite |

**Quality Presets:**
| Preset | Max Dimension | Frame Skip |
|--------|---------------|------------|
| Low | 640px | 3 |
| Medium | 960px | 2 |
| High | 1280px | 1 |

**GIF Export Pipeline:** ScreenCapture records a temporary MP4, then exports the final GIF via `ffmpeg` palette generation/encoding for better quality and reliability.

---

## Annotation Editor

### Tools
| Tool | Description |
|------|-------------|
| Select | Select and move annotations |
| Crop | Crop image to selection |
| Rectangle (Outline) | Draw unfilled rectangle |
| Rectangle (Solid) | Draw filled rectangle |
| Circle | Draw unfilled circle |
| Line | Draw straight line |
| Arrow | Draw directional arrow |
| Text | Add text labels (7 fonts, 4-100pt, frosted glass styling) |
| Blur | Blur sensitive areas (radius: 10) |
| Pencil | Freehand drawing |
| Highlighter | Semi-transparent highlighting |
| Numbered Step | Sequential numbered markers |

### Text Tool Features
- **Styling:** Frosted glass background with native macOS appearance
- **Selection:** Dashed border when selected, 8 resize handles (corners + edges)
- **Persistence:** Size preserved after deselection, auto-saves on tool switch

### Features
- **Color Picker:** 10 presets (Red, Orange, Yellow, Green, Blue, Purple, Pink, White, Black, Gray) + custom HSB
- **Stroke Width:** Configurable (default 3pt)
- **Undo/Redo:** 50-item stack limit
- **Non-destructive:** Annotations stored in `.screencapture-annotations` sidecar files
- **Hash Verification:** SHA256 links annotations to source image

---

## Quick Access Overlay

Appears after capture with action buttons. Auto-dismisses based on preferences.

### Actions
| Action | Shortcut | Description |
|--------|----------|-------------|
| Copy | `Cmd+C` | Copy to clipboard |
| Save | `Cmd+S` | Reveal in Finder |
| Edit | `Cmd+E` | Open annotation editor |
| Pin | `Cmd+P` | Create floating window |
| OCR | `Cmd+T` | Extract text |
| Reveal | `Cmd+O` | Open in Finder |
| Delete | `Cmd+Delete` | Permanently delete |
| Close | `Esc` | Dismiss overlay |

**Auto-dismiss options:** 3s, 5s, 10s, or Never

### Toast Notifications
Actions display confirmation toasts (e.g., "Copied to clipboard", "Pinned screenshot").

### Position Configuration
Overlay position configurable: Near Capture (default), Top Left, Top Right, Bottom Left, Bottom Right.

---

## Text Extraction (OCR)

Vision framework-based text recognition.

| Shortcut (Safe Mode) | `Ctrl+Shift+O` |
|----------------------|----------------|
| Shortcut (Native Mode) | `Cmd+Shift+O` |

### Supported Languages
- English (US, GB)
- German
- French
- Spanish
- Italian
- Portuguese (Brazil)
- Simplified Chinese
- Traditional Chinese
- Japanese
- Korean

**Features:**
- Accurate recognition level
- Language correction enabled
- Bounding box detection
- Barcode detection
- Results copied to clipboard

---

## Pinned Screenshots

Floating always-on-top windows for reference screenshots.

### Toolbar (hover-activated)
Compact single-row toolbar with tooltips and keyboard shortcuts:

| Control | Shortcut | Description |
|---------|----------|-------------|
| Zoom In | `Cmd++` | Increase scale (up to 3.0x) |
| Zoom Out | `Cmd+-` | Decrease scale (down to 0.5x) |
| Lock/Unlock | `Cmd+L` | Toggle interaction lock |
| Opacity | - | Cycle: 100%, 80%, 60%, 40%, 20% |
| Copy | `Cmd+C` | Copy to clipboard |
| Close | `Cmd+W` | Dismiss window |

### Features
- Pinch-to-zoom gesture
- Draggable positioning
- Works across all Spaces
- Works with fullscreen apps
- Unlimited simultaneous windows

---

## Webcam Overlay

Floating camera feed during captures.

| Setting | Value |
|---------|-------|
| Position | Top-right corner |
| Size | 200x200px |
| Camera | Front-facing (wide-angle) |
| Mirroring | Enabled |
| Corner Radius | 32pt |

---

## Capture History

### Views
- **Grid:** 2-column adaptive layout (220-280px cards)
- **List:** Compact rows with thumbnails

### Filtering
- By type: All, Screenshot, Scrolling, Recording, GIF
- Search by filename
- Real-time filtering

### Sorting
- Date (newest/oldest first)
- Name (A-Z/Z-A)

### Per-Capture Actions
- Open
- Open in Editor
- Copy to Clipboard
- Save As...
- Show in Finder
- Toggle Favorite
- Delete

### Auto-cleanup
Removes non-favorite captures after retention period (default: 30 days).

**Retention options:** 7, 14, 30, or 90 days

---

## Storage & File Management

### Save Locations
| Location | Path |
|----------|------|
| Default | `~/Library/Application Support/ScreenCapture/Screenshots` |
| Desktop | `~/Desktop` |
| Custom | User-selected folder |

### File Formats
| Type | Format |
|------|--------|
| Screenshots | PNG |
| Recordings | MP4 (H.264/AAC) |
| GIFs | Animated GIF |
| Scrolling Captures | PNG (stitched) |

### Features
- Security-scoped bookmarks for custom folders
- Bookmark staleness detection
- Storage usage tracking
- Auto-save every 30 seconds

---

## Keyboard Shortcuts

### Capture Shortcuts

| Action | Safe Mode | Native Mode |
|--------|-----------|-------------|
| Capture Fullscreen | `Ctrl+Shift+3` | `Cmd+Shift+3` |
| Capture Area | `Ctrl+Shift+4` | `Cmd+Shift+4` |
| Capture Window | `Ctrl+Shift+5` | `Cmd+Shift+5` |
| Scrolling Capture | `Ctrl+Shift+6` | `Cmd+Shift+6` |
| Record Screen | `Ctrl+Shift+7` | `Cmd+Shift+7` |
| Record GIF | `Ctrl+Shift+8` | `Cmd+Shift+8` |
| Capture Text (OCR) | `Ctrl+Shift+O` | `Cmd+Shift+O` |
| Pin Screenshot | `Ctrl+Shift+P` | `Cmd+Shift+P` |
| All-in-One Menu | `Ctrl+Shift+Option+A` | `Cmd+Shift+Option+A` |

### Application Shortcuts

| Action | Shortcut |
|--------|----------|
| Show Capture History | `Cmd+Shift+H` |
| Open Preferences | `Cmd+,` |

**Shortcut Modes:**
- **Safe Mode (default):** Uses `Ctrl+Shift` to avoid conflicts with macOS Screenshot.app
- **Native Mode:** Uses `Cmd+Shift` with option to remap system shortcuts

---

## Settings

### General
- Launch at login
- Show menu bar icon
- Play sound after capture
- Show Quick Access overlay
- Quick Access auto-dismiss timing
- Default action after capture

### Shortcuts
- Native vs Safe mode toggle
- Current shortcut display
- System shortcut integration status

### Capture
- Hide desktop icons during capture
- Include cursor in screenshots
- Show selection dimensions
- Show magnifier during selection
- Image format (PNG, JPEG, TIFF)
- JPEG quality (10-100%)
- Window shadow capture
- Rounded corners capture

### Recording
- Video quality (Low, Medium, High)
- Frame rate (30/60 FPS)
- Microphone recording
- System audio recording
- Mouse click highlighting
- Keystroke display
- GIF frame rate (10, 15, 20)
- GIF quality preset

### Storage
- Save location
- Storage usage display
- Auto-cleanup toggle
- Cleanup retention period
- Clear all captures
- Open folder button

### Advanced
- Hardware acceleration
- Reduce motion effects
- Debug mode
- Reset preferences
- Version information

---

## System Integration

### Menu Bar
- Camera viewfinder icon
- Recording state indicator (red circle when active)
- Full menu with all capture modes and tools

### URL Scheme
```
screencapture://history    # Opens Capture History window
```

### Permissions
| Permission | Usage |
|------------|-------|
| Screen Recording | ScreenCaptureKit capture |
| Camera | Webcam overlay |
| Microphone | Audio recording (optional) |
| Files & Folders | Custom save locations |

### App Configuration
- Menu bar only (LSUIElement)
- Works across all Spaces
- ServiceManagement for login item

---

## Changelog

When adding or modifying features, document changes here:

| Date | Version | Change | Files Modified |
|------|---------|--------|----------------|
| 2025-01-19 | 1.0.0 | Initial feature documentation | FEATURES.md |
| 2026-01-21 | 1.1.0 | Added Quick Access toast notifications and position config | FEATURES.md, quick-access.mdx |
| 2026-01-21 | 1.1.0 | Added Text tool styling (frosted glass, resize handles, persistence) | FEATURES.md, tools.mdx |
| 2026-01-21 | 1.1.0 | Added Pinned Screenshots toolbar details and shortcuts | FEATURES.md, pinned.mdx |

### Guidelines for Updating

1. Add new features to the appropriate section above
2. Add a changelog entry with date and affected files
3. Update keyboard shortcut table if shortcuts change
4. Update settings section if preferences change
5. Run `./scripts/build-and-test.sh` to verify build after changes
