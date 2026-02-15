import React, { useRef, useEffect, useCallback } from "react";
import styles from "./Recording.module.css";

interface RecordingOverlayProps {
  /** The recording area rect (null = fullscreen) */
  rect?: { x: number; y: number; width: number; height: number } | null;
}

/**
 * Visual border indicator shown during recording.
 * Renders a dashed border around the recording area with a small
 * "REC" indicator in the corner. Fully non-interactive (pointer-events: none).
 */
export const RecordingOverlay: React.FC<RecordingOverlayProps> = ({ rect }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const drawDimming = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !rect) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    // Dim everything outside the recording rect
    ctx.fillStyle = "rgba(0, 0, 0, 0.35)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.clearRect(rect.x, rect.y, rect.width, rect.height);
  }, [rect]);

  useEffect(() => {
    drawDimming();
    const handler = () => drawDimming();
    window.addEventListener("resize", handler);
    return () => window.removeEventListener("resize", handler);
  }, [drawDimming]);

  const borderStyle = rect
    ? { left: rect.x, top: rect.y, width: rect.width, height: rect.height }
    : { inset: 0 };

  const indicatorStyle = rect
    ? { left: rect.x + rect.width - 60, top: rect.y + 8 }
    : { top: 8, right: 8 };

  return (
    <div className={styles.overlay}>
      {/* Dimming outside recording area */}
      {rect && <canvas ref={canvasRef} className={styles.dimmingCanvas} />}

      {/* Dashed border around recording area */}
      <div className={styles.overlayBorder} style={borderStyle} />

      {/* Small "REC" indicator */}
      <div className={styles.overlayIndicator} style={indicatorStyle}>
        <div className={styles.overlayDot} />
        REC
      </div>
    </div>
  );
};
