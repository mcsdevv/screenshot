import { create } from "zustand";
import type { AfterCaptureAction, ScreenCorner } from "@/lib/constants";

interface SettingsState {
  // General
  launchAtLogin: boolean;
  showMenuBarIcon: boolean;
  playSound: boolean;
  showQuickAccess: boolean;
  quickAccessDuration: number;
  popupCorner: ScreenCorner;
  afterCaptureAction: AfterCaptureAction;

  // Shortcuts
  shortcutMode: "safe" | "native";

  // Capture
  showCursor: boolean;
  captureFormat: "png" | "jpeg" | "tiff";
  jpegQuality: number;

  // Recording
  recordingQuality: "low" | "medium" | "high";
  recordingFPS: 30 | 60;
  recordShowCursor: boolean;
  recordMicrophone: boolean;
  recordSystemAudio: boolean;
  showMouseClicks: boolean;

  // Storage
  storageLocation: "default" | "desktop" | "custom";
  autoCleanup: boolean;
  cleanupDays: number;

  // Actions
  setSetting: <K extends keyof SettingsState>(key: K, value: SettingsState[K]) => void;
}

export const useSettingsStore = create<SettingsState>((set) => ({
  launchAtLogin: false,
  showMenuBarIcon: true,
  playSound: true,
  showQuickAccess: true,
  quickAccessDuration: 0,
  popupCorner: "bottomLeft",
  afterCaptureAction: "quickAccess",
  shortcutMode: "safe",
  showCursor: false,
  captureFormat: "png",
  jpegQuality: 0.9,
  recordingQuality: "high",
  recordingFPS: 60,
  recordShowCursor: true,
  recordMicrophone: false,
  recordSystemAudio: true,
  showMouseClicks: true,
  storageLocation: "default",
  autoCleanup: true,
  cleanupDays: 30,

  setSetting: (key, value) => set({ [key]: value } as Partial<SettingsState>),
}));
