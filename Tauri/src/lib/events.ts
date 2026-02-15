/**
 * Typed Tauri event listeners for backend -> frontend communication
 */
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

// Event payload types
export interface RecordingStatePayload {
  state: string;
  elapsed_seconds?: number;
}

export interface CaptureCompletedPayload {
  id: string;
  capture_type: "screenshot" | "recording" | "gif";
  filename: string;
  path: string;
}

export interface ShortcutPayload {
  action: string;
}

// Event listeners
export const onRecordingStateChanged = (handler: (payload: RecordingStatePayload) => void): Promise<UnlistenFn> =>
  listen<RecordingStatePayload>("recording:state-changed", (e) => handler(e.payload));

export const onRecordingDuration = (handler: (seconds: number) => void): Promise<UnlistenFn> =>
  listen<{ elapsed_seconds: number }>("recording:duration", (e) => handler(e.payload.elapsed_seconds));

export const onCaptureCompleted = (handler: (payload: CaptureCompletedPayload) => void): Promise<UnlistenFn> =>
  listen<CaptureCompletedPayload>("capture:completed", (e) => handler(e.payload));

export const onRecordingCompleted = (handler: (payload: CaptureCompletedPayload) => void): Promise<UnlistenFn> =>
  listen<CaptureCompletedPayload>("recording:completed", (e) => handler(e.payload));

export const onRecordingFailed = (handler: (message: string) => void): Promise<UnlistenFn> =>
  listen<{ message: string }>("recording:failed", (e) => handler(e.payload.message));

export const onShortcutTriggered = (handler: (action: string) => void): Promise<UnlistenFn> =>
  listen<ShortcutPayload>("shortcut:triggered", (e) => handler(e.payload.action));

export const onTrayAction = (handler: (action: string) => void): Promise<UnlistenFn> =>
  listen<{ action: string }>("tray:action", (e) => handler(e.payload.action));
