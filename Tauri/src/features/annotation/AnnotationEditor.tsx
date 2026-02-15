/**
 * AnnotationEditor — main editor layout.
 * Full-window layout: toolbar (left), canvas (center), layer panel (right), status bar (bottom).
 */
import React, { useCallback, useEffect, useRef, useState } from "react";
import { useAnnotationStore } from "./useAnnotationStore";
import { AnnotationCanvas } from "./AnnotationCanvas";
import { AnnotationToolbar } from "./AnnotationToolbar";
import { AnnotationStatusBar } from "./AnnotationStatusBar";
import { LayerPanel } from "./LayerPanel";
import {
  DSTrafficLightButtons,
  DSPrimaryButton,
  DSSecondaryButton,
  DSIconButton,
} from "@/components";
import styles from "./Annotation.module.css";

interface AnnotationEditorProps {
  /** Path or captureId used to load the image */
  captureId?: string;
  /** Image data URL or file:// path */
  imageSrc?: string;
  /** Called when save completes */
  onSave?: () => void;
  /** Called when user cancels */
  onClose?: () => void;
}

export const AnnotationEditor: React.FC<AnnotationEditorProps> = ({
  captureId,
  imageSrc,
  onSave,
  onClose,
}) => {
  const store = useAnnotationStore();
  const [loadedImage, setLoadedImage] = useState<HTMLImageElement | null>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });
  const canvasAreaRef = useRef<HTMLDivElement>(null);

  // Load image from source
  useEffect(() => {
    const src = imageSrc ?? (captureId ? `file://${captureId}` : null);
    if (!src) return;

    const img = new Image();
    img.onload = () => setLoadedImage(img);
    img.onerror = () => console.error("AnnotationEditor: Failed to load image", src);
    img.src = src;
  }, [imageSrc, captureId]);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;

      // Cmd+Z / Cmd+Shift+Z — undo/redo
      if (meta && e.key === "z") {
        e.preventDefault();
        if (e.shiftKey) store.redo();
        else store.undo();
        return;
      }

      // Cmd+S — save
      if (meta && e.key === "s") {
        e.preventDefault();
        onSave?.();
        return;
      }

      // Cmd+C — copy
      if (meta && e.key === "c") {
        if (store.selectedAnnotationId) {
          e.preventDefault();
          store.copyAnnotation(store.selectedAnnotationId);
        }
        return;
      }

      // Cmd+V — paste
      if (meta && e.key === "v") {
        e.preventDefault();
        store.pasteAnnotation();
        return;
      }

      // Delete / Backspace — remove selected
      if (e.key === "Delete" || e.key === "Backspace") {
        if (store.selectedAnnotationId && store.currentTool === "select") {
          e.preventDefault();
          store.deleteAnnotation(store.selectedAnnotationId);
        }
        return;
      }

      // Escape — deselect
      if (e.key === "Escape") {
        e.preventDefault();
        store.selectAnnotation(null);
        store.setTool("select");
        return;
      }

      // Arrow keys — nudge
      if (
        store.selectedAnnotationId &&
        ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)
      ) {
        e.preventDefault();
        const step = e.shiftKey ? 10 : 1;
        const dx =
          e.key === "ArrowLeft" ? -step : e.key === "ArrowRight" ? step : 0;
        const dy =
          e.key === "ArrowUp" ? -step : e.key === "ArrowDown" ? step : 0;
        store.nudge(dx, dy);
      }
    };

    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [store, onSave]);

  const handleMouseMove = useCallback(
    (x: number, y: number) => setMousePos({ x, y }),
    []
  );

  const filename = captureId
    ? captureId.split("/").pop() ?? "Untitled"
    : "Untitled";

  return (
    <div className={styles.editor}>
      {/* ---- Top bar ---- */}
      <div className={styles.topBar}>
        <div className={styles.topBarLeft}>
          <DSTrafficLightButtons onClose={onClose} />
        </div>

        <span className={styles.topBarTitle}>{filename}</span>

        <div className={styles.topBarCenter}>
          <div className={styles.undoRedoGroup}>
            <DSIconButton
              icon={<UndoIcon />}
              onClick={store.undo}
              disabled={!store.canUndo}
              size="sm"
              tooltip="Undo (Cmd+Z)"
            />
            <DSIconButton
              icon={<RedoIcon />}
              onClick={store.redo}
              disabled={!store.canRedo}
              size="sm"
              tooltip="Redo (Cmd+Shift+Z)"
            />
          </div>
        </div>

        <div className={styles.topBarRight}>
          {store.selectedAnnotationId && (
            <DSIconButton
              icon={<TrashIcon />}
              onClick={() =>
                store.selectedAnnotationId &&
                store.deleteAnnotation(store.selectedAnnotationId)
              }
              size="sm"
              tooltip="Delete (Backspace)"
            />
          )}
          <DSIconButton
            icon={<LayersIcon />}
            onClick={store.toggleLayerPanel}
            selected={store.isLayerPanelVisible}
            size="sm"
            tooltip="Layers"
          />
          <DSSecondaryButton onClick={onClose}>Cancel</DSSecondaryButton>
          <DSPrimaryButton onClick={onSave} icon={<CheckIcon />}>
            Done
          </DSPrimaryButton>
        </div>
      </div>

      {/* ---- Main content: toolbar | canvas | layers ---- */}
      <div className={styles.mainContent}>
        <AnnotationToolbar />

        <div ref={canvasAreaRef} className={styles.canvasArea}>
          {loadedImage ? (
            <AnnotationCanvas
              image={loadedImage}
              onMouseMove={handleMouseMove}
            />
          ) : (
            <div className={styles.canvasLoading}>Loading image...</div>
          )}
        </div>

        <LayerPanel />
      </div>

      {/* ---- Status bar ---- */}
      <AnnotationStatusBar
        mousePos={mousePos}
        imageWidth={loadedImage?.naturalWidth ?? 0}
        imageHeight={loadedImage?.naturalHeight ?? 0}
      />
    </div>
  );
};

/* ---- Inline SVG icons ---- */
const UndoIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
    <path
      d="M3 7h7a3 3 0 0 1 0 6H8"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M5 4 2 7l3 3"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

const RedoIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
    <path
      d="M13 7H6a3 3 0 0 0 0 6h2"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M11 4l3 3-3 3"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

const TrashIcon = () => (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
    <path d="M2 4h12M5 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1m2 0v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4h10Z" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const LayersIcon = () => (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
    <path d="M8 1 1 5l7 4 7-4-7-4Z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round" />
    <path d="m1 8 7 4 7-4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    <path d="m1 11 7 4 7-4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const CheckIcon = () => (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
    <path d="M3 8l4 4 6-8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);
