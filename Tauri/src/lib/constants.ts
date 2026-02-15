/**
 * Shared constants for the ScreenCapture Tauri app
 */

// Color presets (matching Swift annotationColorPresets)
export const COLOR_PRESETS = [
  "#FF3B30",
  "#FF9500",
  "#FFCC00",
  "#34C759",
  "#007AFF",
  "#AF52DE",
  "#FF2D55",
  "#FFFFFF",
  "#000000",
  "#8E8E93",
] as const;

// Font options (matching Swift FontOption)
export const FONT_OPTIONS = [
  { name: "system-ui", displayName: "System" },
  { name: "Helvetica Neue", displayName: "Helvetica" },
  { name: "Arial", displayName: "Arial" },
  { name: "Georgia", displayName: "Georgia" },
  { name: "Courier New", displayName: "Courier" },
  { name: "Menlo", displayName: "Menlo" },
  { name: "Monaco", displayName: "Monaco" },
] as const;

// Toast types (matching Swift ToastType)
export const TOAST_TYPES = {
  copy: { icon: "doc.on.clipboard", message: "Copied to clipboard", color: "var(--ds-accent)" },
  save: { icon: "checkmark.circle", message: "Saved", color: "var(--ds-success)" },
  pin: { icon: "pin", message: "Pinned", color: "var(--ds-warm-accent)" },
  ocr: { icon: "text.viewfinder", message: "Text copied", color: "var(--ds-accent)" },
  open: { icon: "folder", message: "Opened in Finder", color: "var(--ds-text-secondary)" },
  delete: { icon: "trash", message: "Deleted", color: "var(--ds-danger)" },
  shortcutStandardEnabled: { icon: "keyboard", message: "Standard shortcuts enabled", color: "var(--ds-accent)" },
  shortcutSafeEnabled: { icon: "keyboard", message: "Safe shortcuts enabled", color: "var(--ds-success)" },
  shortcutModeUpdateFailed: { icon: "exclamationmark.triangle", message: "Shortcut mode update failed", color: "var(--ds-danger)" },
} as const;

// Screen corners
export type ScreenCorner = "topLeft" | "topRight" | "bottomLeft" | "bottomRight";

// After-capture actions
export type AfterCaptureAction = "quickAccess" | "clipboard" | "save" | "editor";

// Auto-cleanup days options
export const CLEANUP_DAY_OPTIONS = [7, 14, 30, 90] as const;
