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
- `ScrollingCapture.swift` - instructions window, capture controls window
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
