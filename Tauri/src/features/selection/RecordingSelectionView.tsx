import React, { useState, useRef, useCallback, useEffect } from "react";
import clsx from "clsx";
import { useSettingsStore } from "@/stores/settingsStore";
import { useCaptureStore } from "@/stores/captureStore";
import * as ipc from "@/lib/ipc";
import styles from "./Selection.module.css";

interface RecordingSelectionViewProps {
  displayId: number;
  onStarted?: () => void;
  onCancel: () => void;
}

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

function normalizeRect(x1: number, y1: number, x2: number, y2: number): Rect {
  return {
    x: Math.min(x1, x2),
    y: Math.min(y1, y2),
    w: Math.abs(x2 - x1),
    h: Math.abs(y2 - y1),
  };
}

const HANDLE_POSITIONS = [
  { id: "tl", xF: 0, yF: 0 },
  { id: "t", xF: 0.5, yF: 0 },
  { id: "tr", xF: 1, yF: 0 },
  { id: "r", xF: 1, yF: 0.5 },
  { id: "br", xF: 1, yF: 1 },
  { id: "b", xF: 0.5, yF: 1 },
  { id: "bl", xF: 0, yF: 1 },
  { id: "l", xF: 0, yF: 0.5 },
];

export const RecordingSelectionView: React.FC<RecordingSelectionViewProps> = ({
  displayId,
  onStarted,
  onCancel,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [startPos, setStartPos] = useState<{ x: number; y: number } | null>(null);
  const [selection, setSelection] = useState<Rect | null>(null);

  // Recording options
  const recordingQuality = useSettingsStore((s) => s.recordingQuality);
  const recordingFPS = useSettingsStore((s) => s.recordingFPS);
  const recordShowCursor = useSettingsStore((s) => s.recordShowCursor);
  const recordMicrophone = useSettingsStore((s) => s.recordMicrophone);
  const recordSystemAudio = useSettingsStore((s) => s.recordSystemAudio);
  const showMouseClicks = useSettingsStore((s) => s.showMouseClicks);
  const setSetting = useSettingsStore((s) => s.setSetting);
  const setRecordingState = useCaptureStore((s) => s.setRecordingState);

  const [quality, setQuality] = useState(recordingQuality);
  const [audioEnabled, setAudioEnabled] = useState(recordMicrophone);
  const [isStarting, setIsStarting] = useState(false);

  // Draw dimming overlay
  const drawDimming = useCallback((rect: Rect | null) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    if (rect && rect.w > 0 && rect.h > 0) {
      ctx.clearRect(rect.x, rect.y, rect.w, rect.h);
    }
  }, []);

  useEffect(() => {
    drawDimming(selection);
  }, [selection, drawDimming]);

  // Escape to cancel
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onCancel]);

  const startRecording = async (rect: Rect) => {
    if (isStarting) return;
    setIsStarting(true);
    setRecordingState("starting");

    const config: ipc.RecordingConfig = {
      quality,
      fps: recordingFPS,
      include_cursor: recordShowCursor,
      show_mouse_clicks: showMouseClicks,
      include_microphone: audioEnabled,
      include_system_audio: recordSystemAudio,
      exclude_app_audio: false,
    };

    const target: ipc.RecordingTarget = {
      type: "area",
      x: rect.x,
      y: rect.y,
      width: rect.w,
      height: rect.h,
      display_id: displayId,
    };

    try {
      await ipc.startRecording(target, config);
      setRecordingState("recording");
      onStarted?.();
    } catch {
      setRecordingState("idle");
      onCancel();
    }
  };

  // Mouse handlers
  const handleMouseDown = (e: React.MouseEvent) => {
    if (e.button !== 0 || selection) return;
    setIsDragging(true);
    setStartPos({ x: e.clientX, y: e.clientY });
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    setMousePos({ x: e.clientX, y: e.clientY });
    if (isDragging && startPos) {
      setSelection(normalizeRect(startPos.x, startPos.y, e.clientX, e.clientY));
    }
  };

  const handleMouseUp = (e: React.MouseEvent) => {
    if (!isDragging || !startPos) return;
    setIsDragging(false);
    const rect = normalizeRect(startPos.x, startPos.y, e.clientX, e.clientY);
    if (rect.w > 5 && rect.h > 5) {
      setSelection(rect);
    } else {
      setSelection(null);
      setStartPos(null);
    }
  };

  const sel = selection;

  return (
    <div
      className={styles.overlay}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
    >
      <canvas ref={canvasRef} className={styles.dimmingCanvas} />

      {/* Crosshair (only before selection) */}
      {!isDragging && !sel && (
        <>
          <div className={styles.crosshairV} style={{ left: mousePos.x }} />
          <div className={styles.crosshairH} style={{ top: mousePos.y }} />
        </>
      )}

      {/* Selection rectangle */}
      {sel && sel.w > 0 && sel.h > 0 && (
        <>
          <div
            className={styles.selectionRect}
            style={{ left: sel.x, top: sel.y, width: sel.w, height: sel.h }}
          />

          {HANDLE_POSITIONS.map((hp) => (
            <div
              key={hp.id}
              className={styles.handle}
              style={{
                left: sel.x + sel.w * hp.xF - 4,
                top: sel.y + sel.h * hp.yF - 4,
              }}
            />
          ))}

          {/* Dimensions badge */}
          <div
            className={styles.dimensions}
            style={{ left: sel.x + sel.w / 2, top: sel.y - 28 }}
          >
            {Math.round(sel.w)} x {Math.round(sel.h)}
          </div>
        </>
      )}

      {/* Info panel */}
      {!sel && (
        <div
          className={styles.infoPanel}
          style={{ left: mousePos.x + 20, top: mousePos.y + 20 }}
        >
          <div className={styles.infoRow}>
            <span>+</span>
            <span>{Math.round(mousePos.x)}, {Math.round(mousePos.y)}</span>
          </div>
        </div>
      )}

      {/* Instructions */}
      {!sel && !isDragging && (
        <div className={styles.instructions}>
          Select recording area. Press Esc to cancel.
        </div>
      )}

      {/* Toolbar with recording controls (after selection) */}
      {sel && !isStarting && sel.w > 5 && sel.h > 5 && (
        <div
          className={styles.toolbar}
          style={{
            left: sel.x + sel.w / 2,
            top: sel.y + sel.h + 12,
            transform: "translateX(-50%)",
          }}
        >
          <div className={styles.recordingControls}>
            <select
              className={styles.qualitySelect}
              value={quality}
              onChange={(e) => {
                const v = e.target.value as "low" | "medium" | "high";
                setQuality(v);
                setSetting("recordingQuality", v);
              }}
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>

            <button
              type="button"
              className={clsx(styles.audioToggle, audioEnabled && styles.audioToggleActive)}
              onClick={() => {
                setAudioEnabled(!audioEnabled);
                setSetting("recordMicrophone", !audioEnabled);
              }}
            >
              {audioEnabled ? "\u{1F3A4}" : "\u{1F507}"} Audio
            </button>
          </div>

          <button
            type="button"
            className={clsx(styles.toolbarButton, styles.toolbarButtonPrimary)}
            onClick={() => startRecording(sel)}
          >
            Start Recording
          </button>
          <button type="button" className={styles.toolbarButton} onClick={onCancel}>
            Cancel
          </button>
        </div>
      )}
    </div>
  );
};
