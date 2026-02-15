/**
 * Typed IPC wrappers for Tauri invoke() calls
 * Maps to Rust #[tauri::command] handlers in src-tauri/src/
 */
import { invoke } from "@tauri-apps/api/core";

// === Types ===

export interface CaptureItem {
  id: string;
  capture_type: "screenshot" | "recording" | "gif";
  filename: string;
  created_at: string;
  is_favorite: boolean;
}

export interface CaptureHistory {
  items: CaptureItem[];
}

export interface CaptureRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DisplayInfo {
  id: number;
  width: number;
  height: number;
  scale_factor: number;
  is_primary: boolean;
}

export interface WindowInfo {
  id: number;
  title: string;
  app_name: string;
  width: number;
  height: number;
}

export interface RecordingConfig {
  quality: "low" | "medium" | "high";
  fps: number;
  include_cursor: boolean;
  show_mouse_clicks: boolean;
  include_microphone: boolean;
  include_system_audio: boolean;
  exclude_app_audio: boolean;
}

export type RecordingTarget =
  | { type: "fullscreen"; display_id?: number }
  | { type: "area"; x: number; y: number; width: number; height: number; display_id: number }
  | { type: "window"; window_id: number };

export interface StorageInfo {
  location: "default" | "desktop" | { custom: { path: string } };
  path: string;
  total_items: number;
  total_size_bytes: number;
}

export interface TextBlock {
  text: string;
  confidence: number;
  bounding_box: { x: number; y: number; width: number; height: number };
}

export type PermissionStatus = "authorized" | "denied" | "restricted" | "notDetermined";

// === Screenshot Commands ===

export const captureFullscreen = (
  displayId?: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
) =>
  invoke<CaptureItem>("capture_fullscreen", {
    display_id: displayId,
    include_cursor: includeCursor,
    format: format === "jpeg" ? { jpeg: { quality: 0.9 } } : format,
  });

export const captureArea = (
  rect: CaptureRect,
  displayId: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
) =>
  invoke<CaptureItem>("capture_area", {
    rect,
    display_id: displayId,
    include_cursor: includeCursor,
    format: format === "jpeg" ? { jpeg: { quality: 0.9 } } : format,
  });

export const captureWindow = (
  windowId: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
) =>
  invoke<CaptureItem>("capture_window", {
    window_id: windowId,
    include_cursor: includeCursor,
    format: format === "jpeg" ? { jpeg: { quality: 0.9 } } : format,
  });

// === Recording Commands ===

export const startRecording = (target: RecordingTarget, config: RecordingConfig) =>
  invoke<void>("start_recording", { target, config });

export const stopRecording = () => invoke<CaptureItem>("stop_recording");

export const cancelRecording = () => invoke<void>("cancel_recording");

export const getRecordingState = () => invoke<string>("get_recording_state");

// === Content Discovery ===

export const listDisplays = () => invoke<DisplayInfo[]>("list_displays");

export const listWindows = () => invoke<WindowInfo[]>("list_windows");

// === OCR ===

export const recognizeText = (imagePath: string, languages?: string[]) =>
  invoke<TextBlock[]>("recognize_text", { image_path: imagePath, languages });

// === Storage ===

export const getHistory = () => invoke<CaptureHistory>("get_history");

export const deleteCapture = (id: string) => invoke<boolean>("delete_capture", { id });

export const toggleFavorite = (id: string) => invoke<void>("toggle_favorite", { id });

export const getStorageInfo = () => invoke<StorageInfo>("get_storage_info");

export const setStorageLocation = (location: "default" | "desktop" | { custom: { path: string } }) =>
  invoke<void>("set_storage_location", { location });

// === Permissions ===

export const checkScreenRecordingPermission = () =>
  invoke<PermissionStatus>("check_screen_recording_permission");

export const checkMicrophonePermission = () =>
  invoke<PermissionStatus>("check_microphone_permission");

// === Shortcuts ===

export const setShortcutMode = (mode: "safe" | "native") =>
  invoke<void>("set_shortcut_mode", { mode });
