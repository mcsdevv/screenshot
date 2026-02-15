/**
 * Bridge to Tauri global shortcut events
 * Listens for shortcut events from Rust and dispatches UI actions
 */
import { useEffect } from "react";
import { onShortcutTriggered } from "@/lib/events";

export function useGlobalShortcuts() {
  useEffect(() => {
    let unlisten: (() => void) | undefined;

    onShortcutTriggered((action) => {
      // TODO: Dispatch UI actions based on shortcut
      console.log("Shortcut triggered:", action);
    }).then((fn) => {
      unlisten = fn;
    });

    return () => unlisten?.();
  }, []);
}
