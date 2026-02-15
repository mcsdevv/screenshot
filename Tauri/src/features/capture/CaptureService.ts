/**
 * CaptureService — typed wrapper around all capture-related Tauri IPC calls.
 *
 * Re-exports from @/lib/ipc with additional convenience methods and
 * a unified error handling pattern. Consumers should import from here
 * rather than calling invoke() directly.
 */
import {
  captureFullscreen as ipcCaptureFullscreen,
  captureArea as ipcCaptureArea,
  captureWindow as ipcCaptureWindow,
  startRecording as ipcStartRecording,
  stopRecording as ipcStopRecording,
  cancelRecording as ipcCancelRecording,
  getRecordingState as ipcGetRecordingState,
  recognizeText as ipcRecognizeText,
  checkScreenRecordingPermission,
  checkMicrophonePermission,
  type CaptureItem,
  type CaptureRect,
  type RecordingConfig,
  type RecordingTarget,
  type TextBlock,
  type PermissionStatus,
} from "@/lib/ipc";

// Re-export types for consumers
export type { CaptureItem, CaptureRect, RecordingConfig, RecordingTarget, TextBlock, PermissionStatus };

// ─── Screenshot ─────────────────────────────────────────

export async function captureFullscreen(
  displayId?: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
): Promise<CaptureItem> {
  return ipcCaptureFullscreen(displayId, includeCursor, format);
}

export async function captureArea(
  rect: CaptureRect,
  displayId: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
): Promise<CaptureItem> {
  return ipcCaptureArea(rect, displayId, includeCursor, format);
}

export async function captureWindow(
  windowId: number,
  includeCursor = false,
  format: "png" | "jpeg" | "tiff" = "png"
): Promise<CaptureItem> {
  return ipcCaptureWindow(windowId, includeCursor, format);
}

// ─── Recording ──────────────────────────────────────────

export async function startRecording(
  target: RecordingTarget,
  config: RecordingConfig
): Promise<void> {
  return ipcStartRecording(target, config);
}

export async function stopRecording(): Promise<CaptureItem> {
  return ipcStopRecording();
}

export async function pauseRecording(): Promise<void> {
  // Note: pause/resume may not be in the current Rust backend.
  // This is a forward-looking API that will invoke "pause_recording"
  // once the command is implemented.
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke("pause_recording");
}

export async function resumeRecording(): Promise<void> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke("resume_recording");
}

export async function cancelRecording(): Promise<void> {
  return ipcCancelRecording();
}

export async function getRecordingState(): Promise<string> {
  return ipcGetRecordingState();
}

// ─── OCR ────────────────────────────────────────────────

export async function runOCR(
  imagePath: string,
  languages?: string[]
): Promise<TextBlock[]> {
  return ipcRecognizeText(imagePath, languages);
}

/**
 * Convenience: run OCR and return concatenated text string.
 */
export async function runOCRText(
  imagePath: string,
  languages?: string[]
): Promise<string> {
  const blocks = await runOCR(imagePath, languages);
  return blocks.map((b) => b.text).join("\n");
}

// ─── Permissions ────────────────────────────────────────

export interface PermissionsResult {
  screenRecording: PermissionStatus;
  microphone: PermissionStatus;
}

export async function checkPermissions(): Promise<PermissionsResult> {
  const [screenRecording, microphone] = await Promise.all([
    checkScreenRecordingPermission(),
    checkMicrophonePermission(),
  ]);
  return { screenRecording, microphone };
}

export function isPermissionGranted(status: PermissionStatus): boolean {
  return status === "authorized";
}
