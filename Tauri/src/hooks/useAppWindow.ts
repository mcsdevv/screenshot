/**
 * Window management utilities for Tauri multi-window app
 */
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

interface WindowConfig {
  width?: number;
  height?: number;
  x?: number;
  y?: number;
  transparent?: boolean;
  decorations?: boolean;
  alwaysOnTop?: boolean;
  resizable?: boolean;
  fullscreen?: boolean;
  visible?: boolean;
}

export function useAppWindow() {
  const createWindow = async (
    label: string,
    url: string,
    config: WindowConfig = {}
  ) => {
    const existing = await WebviewWindow.getByLabel(label);
    if (existing) {
      await existing.setFocus();
      return existing;
    }

    const webview = new WebviewWindow(label, {
      url,
      title: label,
      width: config.width ?? 800,
      height: config.height ?? 600,
      x: config.x,
      y: config.y,
      transparent: config.transparent ?? false,
      decorations: config.decorations ?? true,
      alwaysOnTop: config.alwaysOnTop ?? false,
      resizable: config.resizable ?? true,
      fullscreen: config.fullscreen ?? false,
      visible: config.visible ?? true,
    });

    return webview;
  };

  const closeWindow = async (label: string) => {
    const win = await WebviewWindow.getByLabel(label);
    if (win) await win.close();
  };

  return { createWindow, closeWindow };
}
