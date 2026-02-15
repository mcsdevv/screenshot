/**
 * AnnotationStatusBar — bottom bar with zoom, dimensions, mouse position, selection info.
 */
import React from "react";
import { useAnnotationStore } from "./useAnnotationStore";
import styles from "./Annotation.module.css";

interface AnnotationStatusBarProps {
  mousePos: { x: number; y: number };
  imageWidth: number;
  imageHeight: number;
}

export const AnnotationStatusBar: React.FC<AnnotationStatusBarProps> = ({
  mousePos,
  imageWidth,
  imageHeight,
}) => {
  const store = useAnnotationStore();
  const zoomPct = Math.round(store.zoom * 100);

  const selectedAnnotation = store.selectedAnnotationId
    ? store.annotations.find((a) => a.id === store.selectedAnnotationId)
    : null;

  const handleZoomOut = () => store.setZoom(store.zoom - 0.25);
  const handleZoomIn = () => store.setZoom(store.zoom + 0.25);
  const handleZoomFit = () => {
    store.setZoom(1);
    store.setOffset({ x: 0, y: 0 });
  };

  return (
    <div className={styles.statusBar}>
      {/* Image dimensions */}
      <div className={styles.statusSection}>
        <span className={styles.statusSectionIcon}>
          <AspectRatioIcon />
        </span>
        {imageWidth} x {imageHeight}
      </div>

      {/* Mouse position */}
      <div className={styles.statusSection}>
        <span className={styles.statusSectionIcon}>
          <CrosshairIcon />
        </span>
        {mousePos.x}, {mousePos.y}
      </div>

      {/* Selected annotation info */}
      {selectedAnnotation && (
        <div className={styles.statusSection}>
          <span className={styles.statusSectionIcon}>
            <SelectionIcon />
          </span>
          {formatType(selectedAnnotation.type)}
          {" \u2014 "}
          {Math.round(selectedAnnotation.rect.width)} x{" "}
          {Math.round(selectedAnnotation.rect.height)}
        </div>
      )}

      {/* Layer count */}
      <div className={styles.statusSection}>
        <span className={styles.statusSectionIcon}>
          <LayersSmallIcon />
        </span>
        {store.annotations.length} layer{store.annotations.length !== 1 ? "s" : ""}
      </div>

      <div className={styles.statusSpacer} />

      {/* Zoom controls */}
      <div className={styles.zoomControls}>
        <button
          className={styles.zoomButton}
          onClick={handleZoomOut}
          title="Zoom out"
        >
          <MinusIcon />
        </button>
        <span className={styles.zoomLabel}>{zoomPct}%</span>
        <button
          className={styles.zoomButton}
          onClick={handleZoomIn}
          title="Zoom in"
        >
          <PlusIcon />
        </button>
        <button
          className={styles.zoomButton}
          onClick={handleZoomFit}
          title="Reset zoom"
        >
          <FitIcon />
        </button>
      </div>
    </div>
  );
};

function formatType(type: string): string {
  const map: Record<string, string> = {
    rectangleOutline: "Rectangle",
    rectangleSolid: "Filled Rect",
    circleOutline: "Circle",
    line: "Line",
    arrow: "Arrow",
    text: "Text",
    blur: "Blur",
    pencil: "Pencil",
    highlighter: "Highlight",
    numberedStep: "Step",
  };
  return map[type] ?? type;
}

/* ---- Tiny inline SVG icons ---- */

function AspectRatioIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <rect x="2" y="3" width="12" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.2" />
      <path d="M2 6h4v4" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function CrosshairIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <circle cx="8" cy="8" r="4" stroke="currentColor" strokeWidth="1.2" />
      <path d="M8 2v3M8 11v3M2 8h3M11 8h3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function SelectionIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <path d="M3 3h2M11 3h2M3 13h2M11 13h2M3 3v2M13 3v2M3 11v2M13 11v2" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function LayersSmallIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <path d="M8 2L2 5.5l6 3.5 6-3.5L8 2Z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" />
      <path d="M2 8l6 3.5L14 8" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M2 11l6 3 6-3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function MinusIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 16 16" fill="none">
      <path d="M4 8h8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function PlusIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 16 16" fill="none">
      <path d="M8 4v8M4 8h8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function FitIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 16 16" fill="none">
      <text x="3" y="12" fill="currentColor" fontSize="11" fontWeight="bold">1:1</text>
    </svg>
  );
}
