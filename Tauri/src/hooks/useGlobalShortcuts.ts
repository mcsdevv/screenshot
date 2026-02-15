/**
 * Bridge to Tauri global shortcut events
 * Listens for shortcut events from Rust and dispatches UI actions
 */
import { useEffect } from "react";
import { onShortcutTriggered } from "@/lib/events";
import * as ipc from "@/lib/ipc";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

export function useGlobalShortcuts() {
  useEffect(() => {
    let unlisten: (() => void) | undefined;

    onShortcutTriggered(async (action) => {
      switch (action) {
        case "capture_fullscreen":
          try { await ipc.captureFullscreen(); } catch { /* noop */ }
          break;
        case "capture_area":
          new WebviewWindow("selection", {
            url: "/selection",
            fullscreen: true,
            decorations: false,
            alwaysOnTop: true,
          });
          break;
        case "capture_window":
          new WebviewWindow("window-picker", {
            url: "/selection?mode=window",
            fullscreen: true,
            decorations: false,
            alwaysOnTop: true,
          });
          break;
        case "record_area":
          new WebviewWindow("recording-selection", {
            url: "/recording-selection?mode=area",
            fullscreen: true,
            decorations: false,
            alwaysOnTop: true,
          });
          break;
        case "record_fullscreen":
          new WebviewWindow("recording-selection", {
            url: "/recording-selection",
            fullscreen: true,
            decorations: false,
            alwaysOnTop: true,
          });
          break;
      }
    }).then((fn) => {
      unlisten = fn;
    });

    return () => unlisten?.();
  }, []);
}
