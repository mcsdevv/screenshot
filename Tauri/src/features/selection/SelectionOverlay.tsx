import React, { useState, useRef, useCallback, useEffect } from "react";
import clsx from "clsx";
import * as ipc from "@/lib/ipc";
import styles from "./Selection.module.css";

interface SelectionOverlayProps {
  displayId: number;
  onCapture?: (item: ipc.CaptureItem) => void;
  onCancel: () => void;
}

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Normalize a rect so width/height are always positive */
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

export const SelectionOverlay: React.FC<SelectionOverlayProps> = ({
  displayId,
  onCapture,
  onCancel,
}) => {
  const overlayRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [startPos, setStartPos] = useState<{ x: number; y: number } | null>(null);
  const [selection, setSelection] = useState<Rect | null>(null);
  const [confirmed, setConfirmed] = useState(false);

  // Draw dimming overlay
  const drawDimming = useCallback((rect: Rect | null) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    // Fill entire canvas with semi-transparent black
    ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Cut out the selection area
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
      if (e.key === "Enter" && selection && selection.w > 5 && selection.h > 5) {
        confirmCapture(selection);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [selection]); // eslint-disable-line react-hooks/exhaustive-deps

  const confirmCapture = async (rect: Rect) => {
    if (confirmed) return;
    setConfirmed(true);
    try {
      const item = await ipc.captureArea(
        { x: rect.x, y: rect.y, width: rect.w, height: rect.h },
        displayId
      );
      onCapture?.(item);
    } catch {
      onCancel();
    }
  };

  // Mouse handlers
  const handleMouseDown = (e: React.MouseEvent) => {
    if (e.button !== 0) return;
    setIsDragging(true);
    setStartPos({ x: e.clientX, y: e.clientY });
    setSelection(null);
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
      // Auto-confirm on mouse release (matches macOS Screenshot behavior)
      confirmCapture(rect);
    } else {
      setSelection(null);
      setStartPos(null);
    }
  };

  const sel = selection;

  return (
    <div
      ref={overlayRef}
      className={styles.overlay}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
    >
      {/* Dimming canvas */}
      <canvas ref={canvasRef} className={styles.dimmingCanvas} />

      {/* Crosshair (only when not dragging) */}
      {!isDragging && (
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

          {/* Resize handles */}
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

      {/* Info panel near cursor */}
      <div
        className={styles.infoPanel}
        style={{ left: mousePos.x + 20, top: mousePos.y + 20 }}
      >
        <div className={styles.infoRow}>
          <span>+</span>
          <span>{Math.round(mousePos.x)}, {Math.round(mousePos.y)}</span>
        </div>
        {sel && (
          <div className={styles.infoRow}>
            <span>{"\u25A1"}</span>
            <span>{Math.round(sel.w)} x {Math.round(sel.h)}</span>
          </div>
        )}
      </div>

      {/* Instructions (when no selection) */}
      {!sel && !isDragging && (
        <div className={styles.instructions}>
          Click and drag to select an area. Press Esc to cancel.
        </div>
      )}

      {/* Toolbar (when selection is made but not auto-confirmed) */}
      {sel && !confirmed && sel.w > 5 && sel.h > 5 && (
        <div
          className={styles.toolbar}
          style={{
            left: sel.x + sel.w / 2,
            top: sel.y + sel.h + 12,
            transform: "translateX(-50%)",
          }}
        >
          <button
            type="button"
            className={clsx(styles.toolbarButton, styles.toolbarButtonPrimary)}
            onClick={() => confirmCapture(sel)}
          >
            Capture
          </button>
          <button type="button" className={styles.toolbarButton} onClick={onCancel}>
            Cancel
          </button>
        </div>
      )}
    </div>
  );
};
