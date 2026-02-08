# Development Notes

## Critical: NSWindow Memory Management Under ARC

### The Problem

When creating `NSWindow` programmatically on macOS, there's a critical memory management issue that causes **EXC_BAD_ACCESS crashes in `objc_release`**.

By default, `NSWindow.isReleasedWhenClosed` is set to `true`. This means:
1. When `window.close()` is called, AppKit automatically releases the window
2. But ARC (Automatic Reference Counting) also releases the window when your reference goes out of scope
3. **Result: Double-release → EXC_BAD_ACCESS crash**

This is especially common in menu bar/agent apps that create windows programmatically without using `NSWindowController`.

### The Solution

**Always set `isReleasedWhenClosed = false` on programmatically created windows:**

```swift
let window = NSWindow(
    contentRect: frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)

// CRITICAL: Prevent double-release crash under ARC
window.isReleasedWhenClosed = false

window.contentView = hostingView
// ... other configuration
```

### Why This Works

- Setting `isReleasedWhenClosed = false` tells AppKit NOT to release the window when closed
- ARC handles the memory management as expected
- No double-release, no crash

### References

- [Apple Documentation: isReleasedWhenClosed](https://developer.apple.com/documentation/appkit/nswindow/1419062-releasedwhenclosed)
- [Working Without a Nib: NSWindow Memory Management](https://lapcatsoftware.com/articles/working-without-a-nib-part-12.html)
- [How to avoid crash when closing NSWindow for agent macOS app](https://github.com/onmyway133/blog/issues/312)

### Files That Create Windows

All of these files create windows and MUST set `isReleasedWhenClosed = false`:

- `AppDelegate.swift` - QuickAccessOverlay window, AllInOneMenu window
- `ScreenRecordingManager.swift` - selection window, control window
- `PinnedScreenshotWindow.swift` - pinned screenshot window
- `BackgroundTool.swift` - background tool window

### Checklist for New Windows

When creating any new `NSWindow` or subclass:

- [ ] Set `window.isReleasedWhenClosed = false` immediately after creation
- [ ] Use `orderOut(nil)` before `close()` if hiding first
- [ ] Clear `contentView` before closing if using `NSHostingView`
- [ ] Nil out your window reference after closing

### Alternative Approach

If you can't modify window creation, override `close()` in a custom window subclass:

```swift
class SafeWindow: NSWindow {
    override func close() {
        self.orderOut(nil)
        // Don't call super.close() to avoid the release
    }
}
```

However, setting `isReleasedWhenClosed = false` is the preferred approach.

## Known Benign ScreenCaptureKit Stop Logs (macOS 15+)

When stopping area recordings on macOS 15+, Console/Xcode can show framework-level teardown noise such as:

- `_SCStream_RemoteAudioQueueOperationHandlerWithError:1492 streamOutput NOT found. Dropping frame`
- `_SCStream_RemoteVideoQueueOperationHandlerWithError:1459 stream output NOT found. Dropping frame`
- `No scene exists for identity: com.apple.controlcenter:...-NSStatusItemView`
- `Unhandled disconnected auxiliary scene <NSHostedViewScene: ...>`

These messages can appear even when recording output is valid and playable. They are emitted by system components (`ScreenCaptureKit` / Control Center scene lifecycle), not by app-level logging.

### When to Treat as Non-Blocking

The log spam above is considered non-blocking when all are true:

- The recording file exists and is non-empty
- The recording is playable
- The video track is present and decodes
- No app crash or recording-session failure state is triggered

### When to Treat as a Real Bug

Investigate as a failure if any of the following occur:

- Missing output file
- Zero-byte output
- Unplayable asset / decode failure
- Session transitions to failed or app crashes

### Debugging Guidance

- Do not rely on these framework log lines alone for pass/fail decisions.
- Use app-level output validation (`validateVideoOutputFile`) and session state as source of truth.
- For cleaner local debugging, filter these signatures in Console/Xcode log output.

## Important Milestone: Keyboard Shortcuts Working (2026-01-08)

Successfully fixed keyboard shortcuts and button responsiveness:

### Key Changes:
1. **Changed shortcut modifiers from ⌘⇧ to ⌃⇧** - The original shortcuts conflicted with macOS built-in screenshot shortcuts. Using Control+Shift avoids this conflict.

2. **Registered missing pinScreenshot shortcut** - Was defined in KeyboardShortcuts.swift but never registered in AppDelegate.

3. **Replaced SwiftUI Button with onTapGesture** - More reliable click handling, especially in floating windows.

4. **Added KeyboardShortcutHandler** - NSViewRepresentable that handles keyboard events in the QuickAccessOverlay window.

### Working Shortcuts:
- Global: ⌃⇧3/4/5/6/7/8/O/P and ⌃⇧⌥A
- Overlay: ⌘C/S/E/P/T/O and ⌘⌫, Esc

### Carbon HIToolbox Notes:
- Uses RegisterEventHotKey for global shortcuts
- Signature: "SCAP" (0x53434150)
- Event handler installed via InstallEventHandler
- Shortcuts work even when app is not focused
