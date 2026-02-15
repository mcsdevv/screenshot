import React, { useEffect, useRef, useCallback, useState } from "react";
import clsx from "clsx";
import { useCaptureStore } from "@/stores/captureStore";
import * as ipc from "@/lib/ipc";
import styles from "./Recording.module.css";

interface RecordingControlsViewProps {
  /** When true, shows the "Record" button (pre-recording state) */
  showRecordButton?: boolean;
  /** Countdown value (null = no countdown) */
  countdown?: number | null;
  onRecord?: () => void;
  onStop?: () => void;
  onCancel?: () => void;
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  const t = Math.floor((seconds % 1) * 10);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}.${t}`;
}

export const RecordingControlsView: React.FC<RecordingControlsViewProps> = ({
  showRecordButton = false,
  countdown = null,
  onRecord,
  onStop,
  onCancel,
}) => {
  const recordingState = useCaptureStore((s) => s.recordingState);
  const elapsed = useCaptureStore((s) => s.recordingElapsed);
  const setElapsed = useCaptureStore((s) => s.setRecordingElapsed);
  const setRecordingState = useCaptureStore((s) => s.setRecordingState);

  const intervalRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined);
  const dragRef = useRef<{ startX: number; startY: number; elX: number; elY: number } | null>(null);
  const controlsRef = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState<{ x: number; y: number } | null>(null);

  const isRecording = recordingState === "recording";
  const isStopping = recordingState === "stopping";

  // Elapsed timer
  useEffect(() => {
    if (isRecording) {
      const start = Date.now() - elapsed * 1000;
      intervalRef.current = setInterval(() => {
        setElapsed((Date.now() - start) / 1000);
      }, 100);
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [isRecording]); // eslint-disable-line react-hooks/exhaustive-deps

  // Stop recording
  const handleStop = useCallback(async () => {
    setRecordingState("stopping");
    try {
      await ipc.stopRecording();
      setRecordingState("idle");
      setElapsed(0);
      onStop?.();
    } catch {
      setRecordingState("recording");
    }
  }, [setRecordingState, setElapsed, onStop]);

  // Cancel recording
  const handleCancel = useCallback(async () => {
    try {
      await ipc.cancelRecording();
    } catch { /* noop */ }
    setRecordingState("idle");
    setElapsed(0);
    onCancel?.();
  }, [setRecordingState, setElapsed, onCancel]);

  // Keyboard: Escape to stop
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (isRecording) handleStop();
        else handleCancel();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [isRecording, handleStop, handleCancel]);

  // Draggable
  const handleDragStart = (e: React.MouseEvent) => {
    if (!controlsRef.current) return;
    const rect = controlsRef.current.getBoundingClientRect();
    dragRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      elX: rect.left + rect.width / 2,
      elY: rect.top,
    };

    const handleDragMove = (ev: MouseEvent) => {
      if (!dragRef.current) return;
      const dx = ev.clientX - dragRef.current.startX;
      const dy = ev.clientY - dragRef.current.startY;
      setPosition({
        x: dragRef.current.elX + dx,
        y: dragRef.current.elY + dy,
      });
    };

    const handleDragEnd = () => {
      dragRef.current = null;
      window.removeEventListener("mousemove", handleDragMove);
      window.removeEventListener("mouseup", handleDragEnd);
    };

    window.addEventListener("mousemove", handleDragMove);
    window.addEventListener("mouseup", handleDragEnd);
  };

  // Status display
  let statusText: string;
  let dotClass: string;

  if (isStopping) {
    statusText = "Finalizing...";
    dotClass = styles.dotStopping;
  } else if (countdown != null && showRecordButton) {
    statusText = `Starting in ${countdown}...`;
    dotClass = styles.dotStopping;
  } else if (showRecordButton && !isRecording) {
    statusText = "Ready to record";
    dotClass = styles.dotReady;
  } else {
    statusText = formatDuration(elapsed);
    dotClass = styles.dotPulsing;
  }

  const positionStyle = position
    ? { left: position.x, top: position.y, bottom: "auto", transform: "translateX(-50%)" }
    : {};

  return (
    <div
      ref={controlsRef}
      className={styles.controls}
      style={positionStyle}
      onMouseDown={handleDragStart}
    >
      <div className={styles.status}>
        <div className={clsx(styles.recordingDot, dotClass)} />
        <span className={styles.timer}>{statusText}</span>
      </div>

      {!isStopping && (
        <div className={styles.buttonGroup}>
          {showRecordButton && (
            <>
              {countdown != null ? (
                <div className={styles.countdownBadge}>{countdown}</div>
              ) : (
                <button
                  type="button"
                  className={styles.recordButton}
                  onClick={(e) => {
                    e.stopPropagation();
                    onRecord?.();
                  }}
                >
                  {"\u23FA"} Record
                </button>
              )}
            </>
          )}

          <button
            type="button"
            className={clsx(styles.controlButton, styles.stopButton)}
            onClick={(e) => {
              e.stopPropagation();
              handleStop();
            }}
            title="Stop recording"
          >
            {"\u25A0"}
          </button>
        </div>
      )}
    </div>
  );
};
